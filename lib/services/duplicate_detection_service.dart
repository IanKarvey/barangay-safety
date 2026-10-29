import 'dart:math' as math;

import '../models/incident_model.dart';
import 'image_hash_service.dart';
import 'supabase_service.dart';

/// How a candidate came to be suspected.
enum DuplicateReason {
  /// Same category, close by, within minutes.
  proximity,

  /// The same photograph, wherever and whenever it was filed.
  sameImage,

  /// Both — the strongest signal there is.
  both,
}

/// A report that may already be on file.
class DuplicateCandidate {
  final IncidentModel incident;
  final DuplicateReason reason;

  /// Metres between the two reports. Null when either lacks coordinates.
  final double? metresApart;

  /// Minutes between the two reports.
  final int minutesApart;

  /// 0..100. Not a probability — a sort key with a label attached.
  final int confidence;

  const DuplicateCandidate({
    required this.incident,
    required this.reason,
    required this.metresApart,
    required this.minutesApart,
    required this.confidence,
  });
}

/// §4.2 / §4.3 — spots reports that describe an emergency already on file.
///
/// ## The failure this prevents
///
/// Five neighbours see one fire. Today that is five incident rows, five
/// dispatch decisions, five resolutions, and an analytics page that says the
/// barangay had five fires that afternoon.
///
/// ## The failure this must not cause
///
/// **Nothing here merges anything.** Two genuine emergencies happen close
/// together all the time — a fire that spreads to the next roof, a brawl that
/// splits down an alley. Auto-merging those loses one of them, and a lost
/// emergency is incomparably worse than an official seeing one extra card.
///
/// So this only ever *suggests*. `duplicate_of_id` is written when a human
/// says so, and `duplicate_checked_at` records that a human said no, so the
/// same pair is never suggested twice.
class DuplicateDetectionService {
  final _supabase = SupabaseService.instance;

  /// How far apart two reports can be and still be the same event.
  ///
  /// 150m is roughly a block. Wider starts linking genuinely separate
  /// incidents on a dense street; much tighter misses the neighbour who
  /// reported from their own doorway across the road.
  static const double _radiusMetres = 150;

  /// How long after the first report a second can still be the same event.
  ///
  /// An hour covers the realistic window in which people notice, find the app,
  /// and finish a form. Beyond that, a second report of the same category at
  /// the same place is more likely a genuinely new event — a fire that
  /// reignited, a second robbery on the same corner.
  static const Duration _window = Duration(hours: 1);

  /// Candidates for [incident], newest first, strongest first.
  ///
  /// Returns an empty list rather than throwing on failure: this annotates a
  /// queue, and an official must never be blocked from working a real incident
  /// because a suggestion query timed out.
  Future<List<DuplicateCandidate>> findCandidatesFor(
    IncidentModel incident,
  ) async {
    try {
      final since = incident.createdAt.subtract(_window).toUtc();

      final rows = await _supabase.client
          .from('incidents')
          .select('*, profiles!incidents_reporter_id_fkey(full_name, phone)')
          .eq('barangay_id', incident.barangayId)
          .gte('created_at', since.toIso8601String())
          .neq('id', incident.id)
          // Already-linked reports are settled; re-suggesting them is noise.
          .isFilter('duplicate_of_id', null)
          .order('created_at', ascending: false)
          .limit(50);

      final others =
          (rows as List).map((j) => IncidentModel.fromJson(j)).toList();

      final out = <DuplicateCandidate>[];
      for (final other in others) {
        final candidate = _score(incident, other);
        if (candidate != null) out.add(candidate);
      }

      out.sort((a, b) => b.confidence.compareTo(a.confidence));
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Null when the pair is not suspicious enough to raise.
  DuplicateCandidate? _score(IncidentModel a, IncidentModel b) {
    final minutes = a.createdAt.difference(b.createdAt).inMinutes.abs();
    final metres = _metresBetween(a.latitude, a.longitude, b.latitude, b.longitude);

    final sameImage = a.photoHash != null &&
        b.photoHash != null &&
        ImageHashService.looksLikeSameImage(a.photoHash, b.photoHash);

    // Category has to match for proximity to mean anything. A fire and a theft
    // reported from the same corner within the hour are two incidents, and
    // suggesting otherwise would teach officials to dismiss these on sight.
    final nearby = a.category == b.category && metres <= _radiusMetres;

    if (!sameImage && !nearby) return null;

    final reason = sameImage && nearby
        ? DuplicateReason.both
        : sameImage
            ? DuplicateReason.sameImage
            : DuplicateReason.proximity;

    // Confidence is a sort key, not a probability. The weights are blunt on
    // purpose: a number like "87.3%" invites an official to trust it as a
    // measurement rather than read the two reports.
    var confidence = switch (reason) {
      DuplicateReason.both => 95,
      // The same photograph is far stronger evidence than two people standing
      // near each other — it is nearly impossible to produce by coincidence.
      DuplicateReason.sameImage => 85,
      DuplicateReason.proximity => 55,
    };

    if (reason != DuplicateReason.sameImage) {
      // Closer and sooner both raise it, but never past the same-image tier.
      if (metres <= 40) confidence += 10;
      if (minutes <= 10) confidence += 10;
    }

    return DuplicateCandidate(
      incident: b,
      reason: reason,
      metresApart: metres,
      minutesApart: minutes,
      confidence: math.min(99, confidence),
    );
  }

  /// Confirms [duplicateId] is the same event as [originalId].
  ///
  /// The child keeps its own row, its own reporter and its own photos —
  /// nothing is deleted. It gains a pointer to the original so the queue can
  /// fold it away and so status updates can be applied to the group.
  Future<void> linkAsDuplicate({
    required String duplicateId,
    required String originalId,
  }) async {
    await _supabase.client.from('incidents').update({
      'duplicate_of_id': originalId,
      'duplicate_checked_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', duplicateId);
  }

  /// Records that an official looked and said these are different events.
  ///
  /// Without this the same pair is re-suggested on every screen refresh, and a
  /// suggestion that will not go away is one officials learn to ignore — at
  /// which point the feature is worse than not having it.
  Future<void> dismissSuggestion(String incidentId) async {
    await _supabase.client.from('incidents').update({
      'duplicate_checked_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', incidentId);
  }

  /// Every report linked to [originalId], for the "5 people reported this"
  /// group view.
  Future<List<IncidentModel>> linkedReports(String originalId) async {
    try {
      final rows = await _supabase.client
          .from('incidents')
          .select('*, profiles!incidents_reporter_id_fkey(full_name, phone)')
          .eq('duplicate_of_id', originalId)
          .order('created_at');
      return (rows as List).map((j) => IncidentModel.fromJson(j)).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Great-circle distance in metres.
  double _metresBetween(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusMetres = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadiusMetres * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _toRad(double deg) => deg * math.pi / 180.0;
}
