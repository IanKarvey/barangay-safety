import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'supabase_service.dart';
import 'incident_service.dart';
import 'barangay_service.dart';
import '../config/app_config.dart';
import '../models/non_resident_session_model.dart';

/// Drives the non-resident one-time reporting flow.
///
/// Non-residents sign in with a contact number + name only — no password, no
/// OTP. Under the hood this is a Supabase ANONYMOUS auth user, so auth.uid()
/// exists and RLS still applies. See §1 in BARANGAY_CONNECT_REQUIREMENTS.md
/// and `supabase/migration_non_resident_sessions.sql`.
class NonResidentService {
  final _supabase = SupabaseService.instance;
  final _barangayService = BarangayService();
  final _uuid = const Uuid();

  static const _table = 'non_resident_sessions';
  static const _selectWithBarangay = '*, barangays(name)';

  /// Whether this phone may start a new report, or is still inside its 7-day
  /// cooldown from a previous one.
  Future<bool> canReport(String phone) async {
    final result = await _supabase.client
        .rpc('can_non_resident_report', params: {'p_phone': phone});
    return result as bool? ?? false;
  }

  /// Sign in a non-resident and open their session.
  ///
  /// [lat]/[lng] come from GPS and decide the barangay — it is never chosen
  /// manually. Throws [NonResidentException] if the phone is still in
  /// cooldown or the location falls outside every known barangay.
  Future<NonResidentSessionModel> signInAndOpenSession({
    required String phone,
    required String fullName,
    required double lat,
    required double lng,
  }) async {
    if (!await canReport(phone)) {
      throw NonResidentException(
        'This number already has an active report. '
        'You may file another one after 7 days.',
      );
    }

    // Anonymous auth FIRST. The `barangays` table is readable only `TO
    // authenticated`, so looking up the barangay before signing in returns
    // zero rows and every sign-in would look like "outside coverage".
    final auth = await _supabase.auth.signInAnonymously();
    final authUserId = auth.user?.id;
    if (authUserId == null) {
      throw NonResidentException('Could not start a session. Please try again.');
    }

    // Auto-detect barangay from GPS — never user-selected.
    final barangay = await _barangayService.findNearestBarangay(lat, lng);
    if (barangay == null) {
      // Don't leave an orphaned anonymous user behind.
      await _supabase.auth.signOut();
      throw NonResidentException(
        'Your location is outside the areas this app covers. '
        'Please call your local barangay hall directly.',
      );
    }

    try {
      final inserted = await _supabase.client
          .from(_table)
          .insert({
            'auth_user_id': authUserId,
            'phone': phone,
            'full_name': fullName,
            'barangay_id': barangay.id,
            'status': 'active',
            'last_lat': lat,
            'last_lng': lng,
            'last_location_at': DateTime.now().toIso8601String(),
          })
          .select(_selectWithBarangay)
          .single();

      return NonResidentSessionModel.fromJson(inserted);
    } catch (e) {
      // Same reasoning as above — a failed insert must not strand a
      // signed-in anonymous user with no session row.
      await _supabase.auth.signOut();
      debugPrint('NonResidentService: session insert failed: $e');
      throw NonResidentException(
        'Could not start your session. Please try again.',
      );
    }
  }

  /// The current signed-in non-resident's session, or null if there is none.
  ///
  /// Used on app start to restore a session instead of bouncing back to the
  /// login screen — §1 requires that reopening the app keeps them signed in.
  Future<NonResidentSessionModel?> getCurrentSession() async {
    final authUserId = _supabase.auth.currentUser?.id;
    if (authUserId == null) return null;

    final rows = await _supabase.client
        .from(_table)
        .select(_selectWithBarangay)
        .eq('auth_user_id', authUserId)
        .limit(1);

    final list = rows as List;
    if (list.isEmpty) return null;

    final session =
        NonResidentSessionModel.fromJson(list.first as Map<String, dynamic>);

    // An expired session is treated as no session.
    if (session.isExpired) return null;
    return session;
  }

  /// Push the live location up. Called on a timer while the session is open —
  /// the Secretary watches this to know where the reporter is.
  Future<void> updateLocation(String sessionId, double lat, double lng) async {
    await _supabase.client.from(_table).update({
      'last_lat': lat,
      'last_lng': lng,
      'last_location_at': DateTime.now().toIso8601String(),
    }).eq('id', sessionId);
  }

  /// Move the session to a new stage of the lifecycle.
  Future<NonResidentSessionModel> setStatus(
    String sessionId,
    String status, {
    String? disregardReason,
  }) async {
    final updates = <String, dynamic>{'status': status};
    if (disregardReason != null) {
      updates['disregard_reason'] = disregardReason;
    }
    // Logout stays locked for as long as a report is in flight.
    updates['logout_locked'] =
        const {'reported', 'called', 'proof_ready', 'deployed'}.contains(status);

    final updated = await _supabase.client
        .from(_table)
        .update(updates)
        .eq('id', sessionId)
        .select(_selectWithBarangay)
        .single();

    return NonResidentSessionModel.fromJson(updated);
  }

  /// Mark the one allowed report as filed and link it to the incident.
  Future<NonResidentSessionModel> markReported(
    String sessionId, {
    String? incidentId,
  }) async {
    final updated = await _supabase.client
        .from(_table)
        .update({
          'has_reported': true,
          'status': 'reported',
          'logout_locked': true,
          if (incidentId != null) 'incident_id': incidentId,
        })
        .eq('id', sessionId)
        .select(_selectWithBarangay)
        .single();

    return NonResidentSessionModel.fromJson(updated);
  }

  /// Upload photo/video proof for a session and move it to `proof_ready`,
  /// which is what lets the barangay review before deploying anyone.
  ///
  /// Stored under `non-resident/<sessionId>/` in the incident photo bucket so
  /// it reuses the storage policies already in place.
  Future<NonResidentSessionModel> uploadProof(
    String sessionId,
    File file, {
    String type = 'photo',
  }) async {
    final ext = file.path.split('.').last.toLowerCase();
    final fileName = '${_uuid.v4()}.$ext';
    final path = 'non-resident/$sessionId/$fileName';
    final mimeType =
        lookupMimeType(file.path) ?? (type == 'video' ? 'video/mp4' : 'image/jpeg');

    await _supabase.storage.from(AppConfig.incidentPhotoBucket).upload(
          path,
          file,
          fileOptions: FileOptions(contentType: mimeType),
        );

    // The path, not a public URL — proof photographs share the
    // `incident-photos` bucket, which was world-readable until 2026-08-18.
    // See IncidentService for the full reasoning; the short version is that
    // a non-resident's proof photo could be downloaded by anyone.
    final updated = await _supabase.client
        .from(_table)
        .update({
          'proof_url': path,
          'proof_type': type,
          'status': 'proof_ready',
          'logout_locked': true,
        })
        .eq('id', sessionId)
        .select(_selectWithBarangay)
        .single();

    return NonResidentSessionModel.fromJson(updated);
  }

  /// Assign a barangay official to this report, so the reporter knows who is
  /// coming and can ring them directly.
  Future<NonResidentSessionModel> assignOfficial(
      String sessionId, String? officialId) async {
    final updated = await _supabase.client
        .from(_table)
        .update({'assigned_official_id': officialId})
        .eq('id', sessionId)
        .select(_selectWithBarangay)
        .single();

    return NonResidentSessionModel.fromJson(updated);
  }

  /// Officials in a barangay who can be assigned. Tanods first — they are
  /// usually the ones dispatched on foot.
  Future<List<ResponderContact>> getAssignableOfficials(
      String barangayId) async {
    final result = await _supabase.client.rpc(
      'get_assignable_officials',
      params: {'p_barangay_id': barangayId},
    );

    final officials = <ResponderContact>[];
    for (final row in (result as List)) {
      try {
        officials.add(ResponderContact.fromJson(row as Map<String, dynamic>));
      } catch (e) {
        debugPrint('NonResidentService: bad official row: $e');
      }
    }
    return officials;
  }

  /// The official assigned to the CURRENT reporter's session.
  ///
  /// Goes through an RPC because the reporter is an anonymous user with no
  /// profiles row — RLS denies them every profile, and widening that would
  /// expose every official's personal number to every visitor. The function
  /// returns exactly one official: theirs.
  Future<ResponderContact?> getMyAssignedOfficial() async {
    final result = await _supabase.client.rpc('get_my_assigned_official');
    final list = result as List;
    if (list.isEmpty) return null;
    try {
      return ResponderContact.fromJson(list.first as Map<String, dynamic>);
    } catch (e) {
      debugPrint('NonResidentService: bad assigned official row: $e');
      return null;
    }
  }

  /// Record that the reporter could not complete the call.
  ///
  /// Deliberately does NOT advance the status to 'called' — marking a call
  /// that never happened would leave the Secretary waiting for one. The
  /// barangay was already notified at the 'reported' stage, so the report
  /// stands; they just need to phone OUT instead of waiting for a call in.
  Future<NonResidentSessionModel> markCallFailed(
    String sessionId, {
    String reason = 'other',
  }) async {
    final updated = await _supabase.client
        .from(_table)
        .update({
          'call_failed': true,
          'call_failed_reason': reason,
        })
        .eq('id', sessionId)
        .select(_selectWithBarangay)
        .single();

    return NonResidentSessionModel.fromJson(updated);
  }

  /// Close out a session the barangay decided to ignore (bogus, abandoned,
  /// or location lost).
  Future<void> disregard(String sessionId, String reason) async {
    await setStatus(sessionId, 'disregarded', disregardReason: reason);
  }

  /// Watch a single session live — powers the full-screen tracking map, so
  /// the marker moves as the reporter moves.
  Stream<NonResidentSessionModel?> watchSession(String sessionId) {
    return _supabase.client
        .from(_table)
        .stream(primaryKey: ['id'])
        .eq('id', sessionId)
        .map((rows) {
      if (rows.isEmpty) return null;
      try {
        return NonResidentSessionModel.fromJson(rows.first);
      } catch (e) {
        debugPrint('NonResidentService: bad session row in stream: $e');
        return null;
      }
    });
  }

  /// Live queue of non-resident sessions.
  ///
  /// Pass null for [barangayId] to watch every barangay — superadmins are
  /// city-wide and were previously blind to reports outside their own
  /// barangay, which defeats the point of the role.
  Stream<List<Map<String, dynamic>>> subscribeToBarangaySessions(
      String? barangayId) {
    final stream =
        _supabase.client.from(_table).stream(primaryKey: ['id']);
    if (barangayId == null) {
      return stream.order('updated_at', ascending: false);
    }
    return stream
        .eq('barangay_id', barangayId)
        .order('updated_at', ascending: false);
  }

  /// Open (not yet closed) sessions. Null [barangayId] means city-wide.
  Future<List<NonResidentSessionModel>> getActiveSessions(
      String? barangayId) async {
    var query = _supabase.client.from(_table).select(_selectWithBarangay);

    if (barangayId != null) {
      query = query.eq('barangay_id', barangayId);
    }

    final data = await query
        .not('status', 'in', '(completed,disregarded)')
        .order('updated_at', ascending: false);

    await _signProofUrls(data as List);

    final sessions = <NonResidentSessionModel>[];
    for (final row in data) {
      try {
        sessions.add(NonResidentSessionModel.fromJson(row));
      } catch (e) {
        debugPrint('NonResidentService: skipping malformed session row: $e');
      }
    }
    return sessions;
  }

  /// Rewrites `proof_url` on each row to a short-lived signed URL.
  ///
  /// Signed here rather than at upload because the bucket is private: a stored
  /// URL would be a permanent public link to a photograph the reporter
  /// submitted as evidence, which is exactly the exposure this change closes.
  ///
  /// One batch call for the whole queue. Never throws — an official must still
  /// get their queue even if signing fails, because the queue is how they
  /// learn an emergency exists. A missing thumbnail degrades the card; an
  /// empty queue hides the report.
  Future<void> _signProofUrls(List rows) async {
    final paths = <String>{};
    for (final row in rows) {
      final v = (row as Map)['proof_url'];
      if (v is String && v.isNotEmpty) {
        paths.add(IncidentService.storagePathOf(v));
      }
    }
    if (paths.isEmpty) return;

    Map<String, String> signed;
    try {
      final results = await _supabase.storage
          .from(AppConfig.incidentPhotoBucket)
          .createSignedUrls(paths.toList(), 3600);
      signed = {for (final r in results) r.path: r.signedUrl};
    } catch (e) {
      debugPrint('NonResidentService: could not sign proof URLs — $e');
      return;
    }

    for (final row in rows) {
      final v = (row as Map)['proof_url'];
      if (v is! String || v.isEmpty) continue;
      final url = signed[IncidentService.storagePathOf(v)];
      if (url != null) row['proof_url'] = url;
    }
  }

  /// Sessions in barangays that have **no active official assigned**.
  ///
  /// A report routed to a barangay with nobody watching would otherwise sit
  /// unseen — no queue entry anyone opens, and the notification trigger has
  /// nobody to insert rows for. Superadmins need to catch these.
  Future<List<NonResidentSessionModel>> getOrphanedSessions() async {
    final sessions = await getActiveSessions(null);
    if (sessions.isEmpty) return [];

    // Barangays that do have at least one unlocked official.
    final staffed = await _supabase.client
        .from('profiles')
        .select('barangay_id')
        .inFilter('role', ['admin', 'superadmin'])
        .eq('is_locked', false)
        .not('barangay_id', 'is', null);

    final staffedIds = (staffed as List)
        .map((r) => (r as Map<String, dynamic>)['barangay_id'] as String?)
        .whereType<String>()
        .toSet();

    return sessions
        .where((s) => s.barangayId == null || !staffedIds.contains(s.barangayId))
        .toList();
  }

  /// End the session and sign the anonymous user out.
  Future<void> endSession() async {
    await _supabase.auth.signOut();
  }
}

/// A barangay official the reporter can be told about and can ring.
///
/// Deliberately narrow: name, position and phone only. It is populated from
/// SECURITY DEFINER functions that return a single official — the one
/// assigned to the caller's own session — so a reporter never gains blanket
/// read access to staff records.
class ResponderContact {
  final String id;
  final String fullName;
  final String? position;
  final String? phone;

  const ResponderContact({
    required this.id,
    required this.fullName,
    this.position,
    this.phone,
    this.lat,
    this.lng,
    this.locationAt,
    this.isSharing = false,
  });

  /// Live position — present only while they are actively sharing and the
  /// report is still open. The database nulls these otherwise, so a closed
  /// report cannot keep revealing where staff are.
  final double? lat;
  final double? lng;
  final DateTime? locationAt;
  final bool isSharing;

  bool get hasLocation => lat != null && lng != null;

  factory ResponderContact.fromJson(Map<String, dynamic> json) {
    return ResponderContact(
      id: json['id'] as String,
      fullName: json['full_name'] as String? ?? 'Barangay Official',
      position: json['position'] as String?,
      phone: json['phone'] as String?,
      lat: (json['last_lat'] as num?)?.toDouble(),
      lng: (json['last_lng'] as num?)?.toDouble(),
      locationAt: json['last_location_at'] != null
          ? DateTime.parse(json['last_location_at'] as String)
          : null,
      isSharing: json['is_sharing'] as bool? ?? false,
    );
  }
}

class NonResidentException implements Exception {
  final String message;
  NonResidentException(this.message);

  @override
  String toString() => message;
}
