import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../utils/escalation_clock.dart';
import 'supabase_service.dart';

/// What happened when an official pressed "I'm responding".
class ClaimResult {
  const ClaimResult({
    required this.claimed,
    this.reason,
    this.byName,
    this.byRole,
    this.secondsLeft,
  });

  final bool claimed;

  /// For `too_early`: how long until a tanod may volunteer.
  final int? secondsLeft;

  /// `already_handled` | `not_allowed` | `unavailable` when [claimed] is false.
  final String? reason;

  /// The winner: you (when [claimed]) or whoever got there first.
  final String? byName;
  final String? byRole;

  bool get alreadyHandled => !claimed && reason == 'already_handled';
  bool get tooEarly => !claimed && reason == 'too_early';

  factory ClaimResult.fromJson(Map<String, dynamic> json) => ClaimResult(
        claimed: json['claimed'] as bool? ?? false,
        reason: json['reason'] as String?,
        byName: json['by_name'] as String?,
        byRole: json['by_role'] as String?,
        secondsLeft: (json['seconds_left'] as num?)?.toInt(),
      );
}

/// The database does not have the "claim" function yet — the latest SQL update
/// has not been run. Distinct from "could not reach the server" because the fix
/// is different: retrying will never help.
class ClaimUnavailableException implements Exception {
  const ClaimUnavailableException();
  @override
  String toString() => 'claim_incident is not installed on this database';
}

/// Database calls for the unanswered-report flow.
class ResponseService {
  final _db = SupabaseService.instance;

  Duration? _serverOffset;
  Duration? _step;

  /// "I'm responding." The database decides who wins: two officials pressing it
  /// at the same instant get exactly one `claimed: true`.
  Future<ClaimResult> claimIncident(String incidentId) async {
    try {
      final result = await _db.client
          .rpc('claim_incident', params: {'p_incident': incidentId});
      return ClaimResult.fromJson(Map<String, dynamic>.from(result as Map));
    } on PostgrestException catch (e) {
      // PGRST202: "could not find the function in the schema cache".
      if (e.code == 'PGRST202') throw const ClaimUnavailableException();
      rethrow;
    }
  }

  /// Records that an official opened the report. Fire-and-forget: the record is
  /// useful, but failing to write it must never get in the way of the screen.
  Future<void> markSeen(String incidentId) async {
    try {
      await _db.client.rpc('mark_incident_seen', params: {'p_incident': incidentId});
    } catch (e) {
      debugPrint('ResponseService: mark seen failed — $e');
    }
  }

  /// `server time - device time`, measured once. Falls back to zero offline.
  Future<Duration> serverOffset() async {
    if (_serverOffset != null) return _serverOffset!;
    try {
      final before = DateTime.now();
      final raw = await _db.client.rpc('server_time');
      final after = DateTime.now();
      final server = DateTime.parse(raw as String);
      // Compare against the middle of the round trip, not either end.
      final deviceMid = before.add(after.difference(before) ~/ 2);
      _serverOffset = server.difference(deviceMid);
    } catch (e) {
      debugPrint('ResponseService: server time unavailable — $e');
      return Duration.zero; // not cached: try again next time
    }
    return _serverOffset!;
  }

  /// The configured gap between tiers (`escalation_settings.step_seconds`).
  Future<Duration> escalationStep() async {
    if (_step != null) return _step!;
    try {
      final row = await _db.client
          .from('escalation_settings')
          .select('step_seconds')
          .maybeSingle();
      final secs = (row?['step_seconds'] as num?)?.toInt();
      if (secs != null && secs > 0) return _step = Duration(seconds: secs);
    } catch (e) {
      debugPrint('ResponseService: escalation step unavailable — $e');
    }
    return kDefaultEscalationStep;
  }
}
