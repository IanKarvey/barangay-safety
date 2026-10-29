import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import '../models/incident_model.dart';
import '../models/heat_incident_model.dart';
import '../config/app_config.dart';
import 'image_hash_service.dart';

class IncidentService {
  final _supabase = SupabaseService.instance;
  final _uuid = const Uuid();

  // Parses each row independently so one malformed/legacy record (e.g. a
  // deleted reporter breaking the profiles join) doesn't crash the whole list.
  List<IncidentModel> _parseIncidents(List data) {
    final incidents = <IncidentModel>[];
    for (final row in data) {
      try {
        incidents.add(IncidentModel.fromJson(row as Map<String, dynamic>));
      } catch (e) {
        debugPrint('IncidentService: skipping malformed incident row: $e');
      }
    }
    return incidents;
  }

  // ── Create Incident ───────────────────────────────────────────────────
  Future<IncidentModel> createIncident({
    required String reporterId,
    required String barangayId,
    required String category,
    required String description,
    required int severityLevel,
    required double latitude,
    required double longitude,
    String? address,
    String? landmark,
    List<File> photos = const [],
    List<File> videos = const [],
    bool reportedViaVpn = false,
    bool locationMocked = false,
  }) async {
    final incidentData = {
      'reporter_id': reporterId,
      'barangay_id': barangayId,
      'category': category,
      'description': description,
      'severity_level': severityLevel,
      'status': 'pending',
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'landmark': landmark,
      // Advisory only — see IntegrityService. Recorded at submission because
      // it cannot be reconstructed afterwards.
      'reported_via_vpn': reportedViaVpn,
      'location_mocked': locationMocked,
    };

    // §4.3 — hash the first photo before the row is written, so the duplicate
    // detector can act on the very first report rather than only on ones filed
    // after some later backfill. Null is fine and common: reports without a
    // photo simply fall back to proximity matching.
    if (photos.isNotEmpty) {
      incidentData['photo_hash'] = await ImageHashService.hashFile(photos.first);
    }

    final result = await _supabase.client
        .from('incidents')
        .insert(incidentData)
        .select('*, profiles!incidents_reporter_id_fkey(full_name, phone), assigned_profile:profiles!incidents_assigned_to_fkey(full_name), barangays(name)')
        .single();

    final incident = IncidentModel.fromJson(result);

    // Uploaded together rather than one after another. These were sequential
    // awaits, so three photos on barangay wifi meant three full round trips
    // end to end — and this runs while someone is standing at an emergency
    // waiting for the confirmation screen.
    //
    // The row already exists at this point, so a failed upload must not throw:
    // that would surface as "report failed" for a report that is already
    // filed, and the reporter would file it again.
    await Future.wait([
      for (final photo in photos)
        _uploadIncidentMedia(incident.id, photo, type: 'photo'),
      for (final video in videos)
        _uploadIncidentMedia(incident.id, video, type: 'video'),
    ]);

    return incident;
  }

  // ── Upload media (photo or video) ──────────────────────────────────
  Future<String?> _uploadIncidentMedia(String incidentId, File file, {String type = 'photo'}) async {
    try {
      return await _uploadOne(incidentId, file, type);
    } catch (e) {
      // One unreadable file must not discard the other photos, and must never
      // be reported as a failed incident — the incident row is already saved.
      debugPrint('IncidentService: media upload failed ($type): $e');
      return null;
    }
  }

  Future<String> _uploadOne(String incidentId, File file, String type) async {
    final fileExt = file.path.split('.').last.toLowerCase();
    final fileName = '${_uuid.v4()}.$fileExt';
    final filePath = '$incidentId/$fileName';
    final mimeType = lookupMimeType(file.path) ?? (type == 'video' ? 'video/mp4' : 'image/jpeg');

    await _supabase.storage.from(AppConfig.incidentPhotoBucket).upload(
          filePath,
          file,
          fileOptions: FileOptions(contentType: mimeType),
        );

    // The **path** is stored, not a public URL.
    //
    // `getPublicUrl()` used to be called here and its result written into
    // `incident_media.photo_url`. That made every incident photograph
    // retrievable by anyone with the link — and because the bucket also
    // listed anonymously, nobody even needed the link. Verified against the
    // live project on 2026-08-18: an image fetched with no apikey and no
    // Authorization header at all.
    //
    // Storing the path means the bucket can be private and each URL is minted
    // on demand, signed, and short-lived. See [_signMediaInRows].
    await _supabase.client.from('incident_media').insert({
      'incident_id': incidentId,
      'photo_url': filePath,
      'file_name': fileName,
      'media_type': type,
    });

    return filePath;
  }

  // ── Signed media URLs ─────────────────────────────────────────────────

  /// How long a minted media URL stays valid.
  ///
  /// Long enough that an official can leave a case open on their desk and come
  /// back to it, short enough that a URL copied out of the app stops working
  /// the same shift. Matches the ID-verification TTL in §8.
  static const int _signedUrlTtlSeconds = 3600;

  /// Normalises whatever is stored in `photo_url` into a bucket path.
  ///
  /// Tolerates both shapes on purpose. Rows written before this change hold a
  /// full public URL, and the app cannot assume the backfill migration has
  /// been run yet — an APK can reach a phone before the SQL reaches the
  /// database, and photos must not disappear in that window.
  static String storagePathOf(String stored) {
    if (!stored.startsWith('http')) return stored;
    const marker = '/incident-photos/';
    final i = stored.indexOf(marker);
    if (i < 0) return stored;
    var path = stored.substring(i + marker.length);
    final q = path.indexOf('?');
    if (q >= 0) path = path.substring(0, q);
    return Uri.decodeComponent(path);
  }

  /// Rewrites every `incident_media.photo_url` in [rows] to a signed URL.
  ///
  /// One round trip for the whole batch via `createSignedUrls`, not one per
  /// photograph — a queue of fifty incidents would otherwise mean fifty
  /// signing requests before the list could render.
  ///
  /// Never throws. If signing fails the stored value is left untouched: the
  /// photographs may not load, but an official must still get their incident
  /// list. A broken thumbnail is recoverable; an empty queue is not.
  Future<void> _signMediaInRows(List rows) async {
    final paths = <String>{};
    for (final row in rows) {
      final media = (row as Map)['incident_media'];
      if (media is! List) continue;
      for (final m in media) {
        final v = (m as Map)['photo_url'];
        if (v is String && v.isNotEmpty) paths.add(storagePathOf(v));
      }
    }
    if (paths.isEmpty) return;

    Map<String, String> signed;
    try {
      final results = await _supabase.storage
          .from(AppConfig.incidentPhotoBucket)
          .createSignedUrls(paths.toList(), _signedUrlTtlSeconds);
      signed = {for (final r in results) r.path: r.signedUrl};
    } catch (e) {
      debugPrint('IncidentService: could not sign media URLs — $e');
      return;
    }

    for (final row in rows) {
      final media = (row as Map)['incident_media'];
      if (media is! List) continue;
      for (final m in media) {
        final v = (m as Map)['photo_url'];
        if (v is! String || v.isEmpty) continue;
        final url = signed[storagePathOf(v)];
        if (url != null) m['photo_url'] = url;
      }
    }
  }

  // ── Get Incidents (for officials — all in a barangay) ─────────────────
  Future<List<IncidentModel>> getIncidentsByBarangay(
    String barangayId, {
    String? statusFilter,
    int? severityFilter,
    int limit = 50,
    int offset = 0,
  }) async {
    var query = _supabase.client
        .from('incidents')
        .select('*, profiles!incidents_reporter_id_fkey(full_name, phone), assigned_profile:profiles!incidents_assigned_to_fkey(full_name), barangays(name), incident_media(photo_url, media_type)')
        .eq('barangay_id', barangayId);

    if (statusFilter != null) {
      query = query.eq('status', statusFilter);
    }
    if (severityFilter != null) {
      query = query.eq('severity_level', severityFilter);
    }

    final data = await query.order('created_at', ascending: false).range(offset, offset + limit - 1);
    await _signMediaInRows(data as List);
    return _parseIncidents(data);
  }

  // ── Get All Incidents (for superadmin) ────────────────────────────────
  Future<List<IncidentModel>> getAllIncidents({
    String? statusFilter,
    int? severityFilter,
    int limit = 100,
    int offset = 0,
  }) async {
    var query = _supabase.client
        .from('incidents')
        .select('*, profiles!incidents_reporter_id_fkey(full_name, phone), assigned_profile:profiles!incidents_assigned_to_fkey(full_name), barangays(name), incident_media(photo_url, media_type)');

    if (statusFilter != null) {
      query = query.eq('status', statusFilter);
    }
    if (severityFilter != null) {
      query = query.eq('severity_level', severityFilter);
    }

    final data = await query.order('created_at', ascending: false).range(offset, offset + limit - 1);
    await _signMediaInRows(data as List);
    return _parseIncidents(data);
  }

  // ── Get Incidents by Reporter (for residents) ─────────────────────────
  /// A resident's own reports, newest first.
  ///
  /// Bounded, unlike before. Every other list in this service had a limit and
  /// this one did not, so a long-standing account pulled its entire history —
  /// with the joined media rows — every time the home screen opened.
  Future<List<IncidentModel>> getMyIncidents(
    String reporterId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final data = await _supabase.client
        .from('incidents')
        .select('*, barangays(name), incident_media(photo_url, media_type)')
        .eq('reporter_id', reporterId)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    await _signMediaInRows(data as List);
    return _parseIncidents(data);
  }

  // ── Get Single Incident ───────────────────────────────────────────────
  Future<IncidentModel> getIncident(String incidentId) async {
    final data = await _supabase.client
        .from('incidents')
        .select('*, profiles!incidents_reporter_id_fkey(full_name, phone), assigned_profile:profiles!incidents_assigned_to_fkey(full_name), barangays(name), incident_media(photo_url, media_type)')
        .eq('id', incidentId)
        .single();

    await _signMediaInRows([data]);
    return IncidentModel.fromJson(data);
  }

  // ── Update Incident Status ────────────────────────────────────────────
  Future<void> updateIncidentStatus(
    String incidentId,
    String newStatus, {
    String? resolutionNotes,
    String? assignedTo,
  }) async {
    final updates = <String, dynamic>{
      'status': newStatus,
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (resolutionNotes != null) updates['resolution_notes'] = resolutionNotes;
    if (assignedTo != null) updates['assigned_to'] = assignedTo;
    if (newStatus == 'resolved') {
      updates['resolved_at'] = DateTime.now().toIso8601String();
    }

    await _supabase.client
        .from('incidents')
        .update(updates)
        .eq('id', incidentId);
  }

  /// §6 — records that an official confirmed a quiet case is still active.
  ///
  /// Touches `updated_at` only. Nothing about the case has changed, so the
  /// status must not: writing a status here would corrupt the six-stage
  /// timeline and fire a "status updated" notification at the reporter for an
  /// event that never happened.
  Future<void> touchIncident(String incidentId) async {
    await _supabase.client.from('incidents').update({
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', incidentId);
  }

  // ── Update Severity Level ─────────────────────────────────────────────
  Future<void> updateSeverityLevel(String incidentId, int newLevel) async {
    await _supabase.client.from('incidents').update({
      'severity_level': newLevel,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', incidentId);
  }

  // ── Heat map points (privacy-safe) ────────────────────────────────────
  /// Anonymised incident locations for the heat map.
  ///
  /// Goes through the `get_incident_heat_points` RPC rather than selecting
  /// from `incidents` directly: RLS limits residents to `reporter_id =
  /// auth.uid()`, so a resident querying the table would see only their own
  /// reports. The function returns coordinates, severity, category and date
  /// and nothing else — no reporter, description, address or media — and
  /// rounds coordinates to ~100m server-side so a density map cannot
  /// pinpoint a specific home.
  Future<List<HeatIncident>> getHeatPoints({
    String? barangayId,
    int? days,
  }) async {
    final result = await _supabase.client.rpc(
      'get_incident_heat_points',
      params: {'p_barangay_id': barangayId, 'p_days': days},
    );

    final points = <HeatIncident>[];
    for (final row in (result as List)) {
      try {
        points.add(HeatIncident.fromJson(row as Map<String, dynamic>));
      } catch (e) {
        debugPrint('IncidentService: skipping bad heat point: $e');
      }
    }
    return points;
  }

  // ── Get Incident Statistics ───────────────────────────────────────────
  /// The five dashboard counters.
  ///
  /// Counted server-side with HEAD requests rather than by downloading rows.
  /// The previous implementation selected the `status` column of every
  /// incident in the barangay and called `.length` on the result — so showing
  /// "1,204 total" first pulled 1,204 rows over mobile data, and it did that
  /// again on every realtime event. The counters are the cheapest thing on
  /// the dashboard to compute and were the most expensive thing to fetch.
  ///
  /// `.count()` issues `HEAD` with `Prefer: count=exact`; Postgres answers
  /// from the index and the response body is empty. Five of them in parallel
  /// cost less than one row of the old query.
  Future<Map<String, int>> getIncidentStats(String barangayId) =>
      _statsFor(barangayId);

  // ── Get All Barangay Stats (superadmin) ───────────────────────────────
  /// City-wide counters. Same HEAD-count approach — and it matters more here,
  /// because the superadmin's version had no barangay filter at all and so
  /// downloaded every incident row in the system.
  Future<Map<String, int>> getAllIncidentStats() => _statsFor(null);

  /// Shared counter query. [barangayId] null means city-wide.
  Future<Map<String, int>> _statsFor(String? barangayId) async {
    PostgrestFilterBuilder<int> q() {
      final base = _supabase.client.from('incidents').count(CountOption.exact);
      return barangayId == null ? base : base.eq('barangay_id', barangayId);
    }

    // Issued together: five sequential round trips on a slow barangay-hall
    // connection is a visible pause before the dashboard settles.
    final counts = await Future.wait([
      q(),
      q().eq('status', 'pending'),
      q().eq('status', 'in_progress'),
      q().eq('status', 'resolved'),
      q().eq('status', 'flagged'),
    ]);

    return {
      'total': counts[0],
      'pending': counts[1],
      'in_progress': counts[2],
      'resolved': counts[3],
      'flagged': counts[4],
    };
  }

  // ── Subscribe to real-time incident updates (barangay) ───────────────
  /// Realtime signal that something in this barangay changed.
  ///
  /// Limited on purpose. A Supabase `.stream()` re-emits the *whole* matched
  /// set on every change, so an unbounded stream pushes every incident the
  /// barangay has ever had down the websocket each time one row is touched.
  /// The listener only uses the emission as a "something changed" trigger and
  /// refetches properly, so a small window is all that is needed here.
  Stream<List<Map<String, dynamic>>> subscribeToIncidents(String barangayId) {
    return _supabase.client
        .from('incidents')
        .stream(primaryKey: ['id'])
        .eq('barangay_id', barangayId)
        .order('created_at', ascending: false)
        .limit(20);
  }

  /// Realtime signal that one resident's own reports changed.
  ///
  /// Residents had no incident subscription at all — only officials and
  /// superadmins did. So an official verifying, assigning or resolving a
  /// report never reached the reporter's screen: the only thing that refreshed
  /// it was tapping the push notification, because that navigates and triggers
  /// a fetch. Backing out then showed the stale screen again.
  ///
  /// RLS already restricts residents to `reporter_id = auth.uid()`, and the
  /// filter here matches it so the stream carries nothing extra.
  Stream<List<Map<String, dynamic>>> subscribeToMyIncidents(String reporterId) {
    return _supabase.client
        .from('incidents')
        .stream(primaryKey: ['id'])
        .eq('reporter_id', reporterId)
        .order('created_at', ascending: false)
        .limit(20);
  }

  // ── Subscribe to all incidents (superadmin) ───────────────────────────
  /// City-wide realtime signal. Same bounding rationale as
  /// [subscribeToIncidents], and more important here — this one had no
  /// barangay filter either, so it streamed every incident in Lipa City.
  Stream<List<Map<String, dynamic>>> subscribeToAllIncidents() {
    return _supabase.client
        .from('incidents')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(20);
  }

  // ── Assign Incident to an official ───────────────────────────────────
  Future<void> assignIncident(String incidentId, String? assignedToId) async {
    await _supabase.client.from('incidents').update({
      'assigned_to': assignedToId,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', incidentId);
  }

  // ── Delete Incident ───────────────────────────────────────────────────
  Future<void> deleteIncident(String incidentId) async {
    final result = await _supabase.client
        .from('incidents')
        .delete()
        .eq('id', incidentId)
        .select('id');

    if ((result as List).isEmpty) {
      throw Exception(
        'Unable to delete this report. It may have already been removed, '
        'or you do not have permission to delete it.',
      );
    }
  }
}
