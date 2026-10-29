import 'package:flutter/foundation.dart';

import 'supabase_service.dart';

/// A report that crossed a response-time line and was escalated.
///
/// Two kinds, both written by database jobs and never by the app:
///   * UNANSWERED — nobody acted within 5 / 10 / 15 minutes
///     (`escalate_unanswered_reports`, migration_2026_10_20_three_features.sql);
///   * taking too long — someone took it but it is still open after 24 / 48 / 72
///     hours (`escalate_overdue_incidents`, migration_2026_10_15_escalation.sql).
class EscalationEntry {
  const EscalationEntry({
    required this.id,
    required this.incidentId,
    required this.level,
    required this.recipients,
    required this.createdAt,
    required this.category,
    required this.barangayName,
    required this.status,
    this.unanswered = false,
  });

  /// True for the minute-based "nobody has answered" escalation.
  final bool unanswered;

  final String id;
  final String incidentId;

  /// 1 reminder, 2 overdue, 3 city level.
  final int level;

  /// How many people were notified.
  final int recipients;
  final DateTime createdAt;
  final String category;
  final String? barangayName;
  final String? status;

  /// A row of `report_escalation_events` (an unanswered-report tier).
  factory EscalationEntry.fromUnansweredEvent(Map<String, dynamic> json) {
    final incident = (json['incidents'] as Map?)?.cast<String, dynamic>();
    final barangay = (incident?['barangays'] as Map?)?.cast<String, dynamic>();
    return EscalationEntry(
      id: json['id'] as String,
      incidentId: json['report_id'] as String,
      level: (json['level'] as num).toInt(),
      recipients: ((json['notified_user_ids'] as List?) ?? const []).length,
      createdAt: DateTime.parse(json['triggered_at'] as String).toLocal(),
      category: (incident?['category'] as String?) ?? 'Report',
      barangayName: barangay?['name'] as String?,
      status: incident?['status'] as String?,
      unanswered: true,
    );
  }

  factory EscalationEntry.fromJson(Map<String, dynamic> json) {
    final incident = (json['incidents'] as Map?)?.cast<String, dynamic>();
    final barangay = (incident?['barangays'] as Map?)?.cast<String, dynamic>();
    return EscalationEntry(
      id: json['id'] as String,
      incidentId: json['incident_id'] as String,
      level: (json['level'] as num).toInt(),
      recipients: (json['recipients'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      category: (incident?['category'] as String?) ?? 'Report',
      barangayName: barangay?['name'] as String?,
      status: incident?['status'] as String?,
    );
  }
}

/// A person who tried to report something beyond the barangay (a fire, an
/// accident) and was sent to call the right agency instead.
///
/// Not an incident: nothing here is assigned or expected to be actioned. It is
/// the barangay's record that the event happened in its area.
class ReferralEntry {
  const ReferralEntry({
    required this.id,
    required this.category,
    required this.agency,
    required this.createdAt,
    required this.barangayName,
  });

  final String id;
  final String category;

  /// fire, police, medical, disaster, lto — see LguAgency.
  final String agency;
  final DateTime createdAt;
  final String? barangayName;

  factory ReferralEntry.fromJson(Map<String, dynamic> json) {
    final barangay = (json['barangays'] as Map?)?.cast<String, dynamic>();
    return ReferralEntry(
      id: json['id'] as String,
      category: json['category'] as String,
      agency: json['agency'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      barangayName: barangay?['name'] as String?,
    );
  }
}

/// Where the escalations screen gets its data. An interface so the screen can be
/// rendered and tested without a database.
abstract class EscalationSource {
  Future<List<EscalationEntry>> escalations();
  Future<List<ReferralEntry>> referrals();
}

/// Reads from Supabase. Row-level security does the scoping: an official gets
/// their own barangay's rows and the superadmin gets all of them, so no filter
/// is applied here — asking for "all" and receiving only what you may see is the
/// intended behaviour, and a client-side filter would only hide a policy bug.
class SupabaseEscalationSource implements EscalationSource {
  static const _limit = 100;

  final _supabase = SupabaseService.instance;

  @override
  Future<List<EscalationEntry>> escalations() async {
    final rows = await _supabase.client
        .from('incident_escalations')
        .select('id, incident_id, level, recipients, created_at, '
            'incidents(category, status, barangays(name))')
        .order('created_at', ascending: false)
        .limit(_limit);
    final slow = [
      for (final r in rows as List)
        EscalationEntry.fromJson((r as Map).cast<String, dynamic>()),
    ];

    // The unanswered-report tiers. Read separately and tolerated if missing, so
    // this screen keeps working on a database where the migration has not been
    // run yet.
    var unanswered = <EscalationEntry>[];
    try {
      final events = await _supabase.client
          .from('report_escalation_events')
          .select('id, report_id, level, triggered_at, notified_user_ids, '
              'incidents(category, status, barangays(name))')
          .order('triggered_at', ascending: false)
          .limit(_limit);
      unanswered = [
        for (final r in events as List)
          EscalationEntry.fromUnansweredEvent((r as Map).cast<String, dynamic>()),
      ];
    } catch (e) {
      debugPrint('EscalationService: unanswered tiers unavailable — $e');
    }

    return [...unanswered, ...slow]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<List<ReferralEntry>> referrals() async {
    final rows = await _supabase.client
        .from('incident_referrals')
        .select('id, category, agency, created_at, barangays(name)')
        .order('created_at', ascending: false)
        .limit(_limit);
    return [
      for (final r in rows as List)
        ReferralEntry.fromJson((r as Map).cast<String, dynamic>()),
    ];
  }
}
