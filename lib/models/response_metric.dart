/// One report as seen by the response-time analytics: the
/// `report_response_metrics` view, row for row.
///
/// Privacy is a property of the VIEW, not of this class: the view has no
/// coordinates, address, landmark, phone, email, ID or photo column, so there is
/// nothing here to forget to leave out of an export. The resident's name is the
/// only personal field, as the brief allows.
///
/// Every timestamp is UTC as stored; display code converts to Philippine time.
/// A null timestamp means "has not happened yet" or "happened before response
/// tracking existed" — it is never filled with an estimate.
class ResponseMetricRow {
  const ResponseMetricRow({
    required this.reportId,
    required this.residentName,
    required this.barangayId,
    required this.barangayName,
    required this.category,
    required this.severity,
    required this.finalStatus,
    required this.submittedAt,
    this.firstSeenAt,
    this.firstActionAt,
    this.acknowledgedAt,
    this.assignedAt,
    this.dispatchedAt,
    this.onSceneAt,
    this.resolvedAt,
    this.closedAt,
    this.escalationLevel = 0,
    this.level1At,
    this.level2At,
    this.level3At,
    this.responderName,
    this.responderRole,
    this.secsToFirstSeen,
    this.secsToFirstResponse,
    this.secsToDispatch,
    this.secsTravel,
    this.secsToResolve,
    this.secsTotalOpen,
    this.answeredWithin5,
    this.answeredWithin10,
    this.answeredWithin15,
  });

  final String reportId;
  final String? residentName;
  final String? barangayId;
  final String? barangayName;
  final String category;
  final int severity;
  final String finalStatus;

  final DateTime submittedAt;
  final DateTime? firstSeenAt;
  final DateTime? firstActionAt;
  final DateTime? acknowledgedAt;
  final DateTime? assignedAt;
  final DateTime? dispatchedAt;
  final DateTime? onSceneAt;
  final DateTime? resolvedAt;
  final DateTime? closedAt;

  /// Highest tier reached: 0 none, 1 / 2 / 3.
  final int escalationLevel;
  final DateTime? level1At;
  final DateTime? level2At;
  final DateTime? level3At;

  final String? responderName;
  final String? responderRole;

  /// Whole seconds; null when the step has not happened (or predates tracking).
  final int? secsToFirstSeen;
  final int? secsToFirstResponse;
  final int? secsToDispatch;
  final int? secsTravel;
  final int? secsToResolve;
  final int? secsTotalOpen;

  /// Null while unanswered.
  final bool? answeredWithin5;
  final bool? answeredWithin10;
  final bool? answeredWithin15;

  bool get wasEscalated => escalationLevel > 0;

  /// Someone has responded (a recorded first action).
  bool get isAnswered => firstActionAt != null;

  /// Still waiting for anyone to act on it, by the database's own record.
  bool get isUnansweredNow => firstActionAt == null && finalStatus == 'pending';

  static DateTime? _date(dynamic v) =>
      v == null ? null : DateTime.parse(v as String).toUtc();
  static int? _int(dynamic v) => (v as num?)?.toInt();

  factory ResponseMetricRow.fromJson(Map<String, dynamic> j) =>
      ResponseMetricRow(
        reportId: j['report_id'] as String,
        residentName: j['resident_name'] as String?,
        barangayId: j['barangay_id'] as String?,
        barangayName: j['barangay_name'] as String?,
        category: j['category'] as String? ?? '',
        severity: _int(j['severity']) ?? 1,
        finalStatus: j['final_status'] as String? ?? 'pending',
        submittedAt: DateTime.parse(j['submitted_at'] as String).toUtc(),
        firstSeenAt: _date(j['first_seen_at']),
        firstActionAt: _date(j['first_action_at']),
        acknowledgedAt: _date(j['acknowledged_at']),
        assignedAt: _date(j['assigned_at']),
        dispatchedAt: _date(j['dispatched_at']),
        onSceneAt: _date(j['on_scene_at']),
        resolvedAt: _date(j['resolved_at']),
        closedAt: _date(j['closed_at']),
        escalationLevel: _int(j['escalation_level_reached']) ?? 0,
        level1At: _date(j['level_1_at']),
        level2At: _date(j['level_2_at']),
        level3At: _date(j['level_3_at']),
        responderName: j['responder_name'] as String?,
        responderRole: j['responder_role'] as String?,
        secsToFirstSeen: _int(j['secs_to_first_seen']),
        secsToFirstResponse: _int(j['secs_to_first_response']),
        secsToDispatch: _int(j['secs_to_dispatch']),
        secsTravel: _int(j['secs_travel']),
        secsToResolve: _int(j['secs_to_resolve']),
        secsTotalOpen: _int(j['secs_total_open']),
        answeredWithin5: j['answered_within_5'] as bool?,
        answeredWithin10: j['answered_within_10'] as bool?,
        answeredWithin15: j['answered_within_15'] as bool?,
      );
}

/// One status change, from `report_status_logs`.
class StatusLogRow {
  const StatusLogRow({
    required this.reportId,
    required this.fromStatus,
    required this.toStatus,
    required this.changedByName,
    required this.changedByRole,
    required this.changedAt,
    this.remarks,
  });

  final String reportId;
  final String? fromStatus;
  final String toStatus;
  final String? changedByName;
  final String? changedByRole;
  final DateTime changedAt;
  final String? remarks;

  factory StatusLogRow.fromJson(Map<String, dynamic> j) => StatusLogRow(
        reportId: j['report_id'] as String,
        fromStatus: j['from_status'] as String?,
        toStatus: j['to_status'] as String,
        changedByName: j['changed_by_name'] as String?,
        changedByRole: j['changed_by_role'] as String?,
        changedAt: DateTime.parse(j['changed_at'] as String).toUtc(),
        remarks: j['remarks'] as String?,
      );
}

/// One escalation, from `report_escalation_events`.
class EscalationEventRow {
  const EscalationEventRow({
    required this.reportId,
    required this.level,
    required this.triggeredAt,
    required this.notifiedRoles,
    required this.notifiedCount,
    this.residentNotifiedAt,
  });

  final String reportId;
  final int level;
  final DateTime triggeredAt;
  final List<String> notifiedRoles;
  final int notifiedCount;
  final DateTime? residentNotifiedAt;

  factory EscalationEventRow.fromJson(Map<String, dynamic> j) =>
      EscalationEventRow(
        reportId: j['report_id'] as String,
        level: (j['level'] as num).toInt(),
        triggeredAt: DateTime.parse(j['triggered_at'] as String).toUtc(),
        notifiedRoles: ((j['notified_roles'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        notifiedCount: ((j['notified_user_ids'] as List?) ?? const []).length,
        residentNotifiedAt: j['resident_notified_at'] == null
            ? null
            : DateTime.parse(j['resident_notified_at'] as String).toUtc(),
      );
}
