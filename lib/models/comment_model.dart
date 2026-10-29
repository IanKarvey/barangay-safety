class CommentModel {
  final String id;
  final String incidentId;
  final String authorId;
  final String? authorName;
  final String? authorRole;
  final String message;
  final DateTime createdAt;

  const CommentModel({
    required this.id,
    required this.incidentId,
    required this.authorId,
    this.authorName,
    this.authorRole,
    required this.message,
    required this.createdAt,
  });

  factory CommentModel.fromJson(Map<String, dynamic> json) {
    return CommentModel(
      id: json['id'] as String,
      incidentId: json['incident_id'] as String,
      authorId: json['author_id'] as String,
      authorName: json['author_name'] as String?,
      authorRole: json['author_role'] as String?,
      message: json['message'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
