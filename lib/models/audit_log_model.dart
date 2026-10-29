class AuditLogModel {
  final String id;
  final String userId;
  final String? userName;
  final String action; // e.g. 'status_update', 'severity_change', 'flag_report', 'lock_user'
  final String? incidentId;
  final String? details;
  final DateTime createdAt;

  AuditLogModel({
    required this.id,
    required this.userId,
    this.userName,
    required this.action,
    this.incidentId,
    this.details,
    required this.createdAt,
  });

  factory AuditLogModel.fromJson(Map<String, dynamic> json) {
    return AuditLogModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      userName: json['profiles'] != null
          ? json['profiles']['full_name'] as String?
          : json['user_name'] as String?,
      action: json['action'] as String,
      incidentId: json['incident_id'] as String?,
      details: json['details'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'action': action,
      'incident_id': incidentId,
      'details': details,
    };
  }
}
