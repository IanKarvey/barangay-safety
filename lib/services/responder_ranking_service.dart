import 'dart:math' as math;

import '../models/incident_model.dart';
import '../models/user_model.dart';
import 'supabase_service.dart';

/// One official, scored for one incident.
class RankedResponder {
  final UserModel official;

  /// Metres from the incident, or null when they are not sharing location.
  final double? metresAway;

  /// How many active cases they already hold.
  final int openCases;

  /// 0..100. A sort key, not a measurement.
  final int score;

  /// Short human reason, e.g. "320m away · free". Shown instead of the number,
  /// because the number explains nothing and invites false precision.
  final String reason;

  const RankedResponder({
    required this.official,
    required this.metresAway,
    required this.openCases,
    required this.score,
    required this.reason,
  });

  /// Whether this is the top pick worth badging.
  bool get isSuggested => score >= 70;
}

/// §4.4 — suggests who to send, instead of an alphabetical list of names.
///
/// ## What was wrong with the list
///
/// Assignment was a plain list of every official in the barangay. Nothing in
/// it said who was nearest, who was already handling two other cases, or who
/// was even on duty. The official picking had to know all of that from memory,
/// at the moment they were least able to think about it.
///
/// ## Still a suggestion
///
/// The ranking is shown as an ordering plus a badge on the top pick. Every
/// official remains selectable, and nothing is auto-assigned. The system does
/// not know that the nearest tanod is at a funeral, and the person at the desk
/// does.
class ResponderRankingService {
  final _supabase = SupabaseService.instance;

  /// Ranks [officials] for [incident], best first.
  ///
  /// Never throws: on failure the officials come back unranked and in their
  /// original order, which is exactly the behaviour that existed before this
  /// feature. A ranking outage must not stop a dispatch.
  Future<List<RankedResponder>> rank({
    required IncidentModel incident,
    required List<UserModel> officials,
  }) async {
    Map<String, int> caseload;
    try {
      caseload = await _openCaseCounts(incident.barangayId);
    } catch (_) {
      caseload = const {};
    }

    final ranked = officials.map((o) {
      final open = caseload[o.id] ?? 0;
      final metres = _distanceTo(incident, o);
      return _score(o, metres, open, incident);
    }).toList();

    ranked.sort((a, b) => b.score.compareTo(a.score));
    return ranked;
  }

  RankedResponder _score(
    UserModel official,
    double? metres,
    int openCases,
    IncidentModel incident,
  ) {
    var score = 50;
    final bits = <String>[];

    // ── Distance ──────────────────────────────────────────────────────────
    // The single biggest factor, because it is the one that changes how long
    // someone waits. Only counts when they are actually sharing location —
    // an unknown position must never score as "far", or every official with
    // location off would sink below one who happens to be broadcasting from
    // the other side of the barangay.
    if (metres != null) {
      if (metres <= 300) {
        score += 35;
        bits.add('${metres.round()}m away');
      } else if (metres <= 1000) {
        score += 22;
        bits.add('${metres.round()}m away');
      } else if (metres <= 3000) {
        score += 10;
        bits.add('${(metres / 1000).toStringAsFixed(1)}km away');
      } else {
        bits.add('${(metres / 1000).toStringAsFixed(1)}km away');
      }
      // Being on the air at all means they are on duty right now.
      score += 8;
    } else {
      bits.add('location off');
    }

    // ── Caseload ──────────────────────────────────────────────────────────
    // Sending a fourth case to the person already holding three is how one
    // responder ends up the bottleneck for a whole barangay.
    if (openCases == 0) {
      score += 15;
      bits.add('free');
    } else if (openCases <= 2) {
      score += 5;
      bits.add('$openCases active');
    } else {
      score -= 15;
      bits.add('$openCases active');
    }

    // ── Role fit ──────────────────────────────────────────────────────────
    // A Tanod is the field responder — going to the scene is the job. The
    // Captain and Secretary can be assigned and sometimes should be, but they
    // are the case desk, and defaulting to them empties the desk.
    if (official.isTanod) {
      score += 12;
    } else if (official.isCaptain || official.isSecretary) {
      score -= 5;
    }

    // A locked or suspended account should never be the suggestion.
    if (official.isLocked || official.isActivelySuspended) {
      score -= 60;
      bits.add('unavailable');
    }

    return RankedResponder(
      official: official,
      metresAway: metres,
      openCases: openCases,
      score: math.max(0, math.min(100, score)),
      reason: bits.join(' · '),
    );
  }

  /// Metres from the incident to an official's last published position.
  ///
  /// Null when they are not sharing, have no fix yet, or the fix is stale.
  double? _distanceTo(IncidentModel incident, UserModel official) {
    if (!official.isSharingLocation) return null;
    final lat = official.lastLat;
    final lng = official.lastLng;
    if (lat == null || lng == null) return null;

    // A position from an hour ago is not where they are now. Treating a stale
    // fix as current is how the "nearest" responder turns out to be the one
    // who went home — worse than admitting the position is unknown.
    final at = official.lastLocationAt;
    if (at != null && DateTime.now().difference(at) > const Duration(minutes: 10)) {
      return null;
    }

    return _metresBetween(incident.latitude, incident.longitude, lat, lng);
  }

  /// Open case counts per official across the barangay, in one query.
  Future<Map<String, int>> _openCaseCounts(String barangayId) async {
    final rows = await _supabase.client
        .from('incidents')
        .select('assigned_to')
        .eq('barangay_id', barangayId)
        .not('assigned_to', 'is', null)
        // Everything that is not finished. `flagged` counts as closed — a
        // false report is not occupying anyone's time.
        // Unquoted, matching the working pattern in non_resident_service.dart.
        // PostgREST treats the double quotes as part of the value, so the
        // quoted form matched nothing and every assigned incident — resolved
        // ones included — counted as an open case, inflating every responder's
        // caseload and skewing the ranking.
        .not('status', 'in', '(resolved,closed,flagged)');

    final counts = <String, int>{};
    for (final row in rows as List) {
      final id = row['assigned_to'] as String?;
      if (id != null) counts[id] = (counts[id] ?? 0) + 1;
    }
    return counts;
  }

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
