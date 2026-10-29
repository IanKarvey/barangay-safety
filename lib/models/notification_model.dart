class NotificationModel {
  final String id;
  final String userId;       // recipient
  final String title;
  final String body;
  final String type;         // 'status_change' | 'new_critical' | 'assigned' | 'comment'
                             // | 'escalation' | 'escalation_resident' | 'responder_update'
  final String? incidentId;
  final bool isRead;
  final DateTime createdAt;

  /// Small structured payload (escalation level, responder role/name). Lets the
  /// app show the message in the user's own language instead of the stored
  /// English-then-Filipino text. Null on older notifications.
  final Map<String, dynamic>? data;

  const NotificationModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    this.incidentId,
    required this.isRead,
    required this.createdAt,
    this.data,
  });

  NotificationModel copyWith({bool? isRead}) => NotificationModel(
        id: id,
        userId: userId,
        title: title,
        body: body,
        type: type,
        incidentId: incidentId,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
        data: data,
      );

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      type: json['type'] as String? ?? 'general',
      incidentId: json['incident_id'] as String?,
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      data: json['data'] is Map
          ? Map<String, dynamic>.from(json['data'] as Map)
          : null,
    );
  }
}
