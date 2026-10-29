import 'package:flutter/foundation.dart';
import 'supabase_service.dart';
import '../models/comment_model.dart';

class CommentService {
  final _supabase = SupabaseService.instance;

  Future<List<CommentModel>> getComments(String incidentId) async {
    final data = await _supabase.client
        .from('incident_comments')
        .select()
        .eq('incident_id', incidentId)
        .order('created_at', ascending: true)
        // Bounded — a long back-and-forth on one incident should not pull the
        // whole thread on every open.
        .limit(200);

    return (data as List).map((json) => CommentModel.fromJson(json)).toList();
  }

  /// Live thread for one incident.
  ///
  /// Streams the table directly so a message posted by the other party shows
  /// up without anyone pulling to refresh — a conversation you have to
  /// manually reload isn't a conversation.
  ///
  /// Requires `incident_comments` to be in the `supabase_realtime`
  /// publication; a table missing from it makes the subscription receive
  /// nothing **silently**, which is how the non-resident status popup went
  /// unnoticed for three sessions.
  Stream<List<CommentModel>> watchComments(String incidentId) {
    return _supabase.client
        .from('incident_comments')
        .stream(primaryKey: ['id'])
        .eq('incident_id', incidentId)
        .order('created_at', ascending: true)
        .map((rows) {
          final comments = <CommentModel>[];
          for (final row in rows) {
            try {
              comments.add(CommentModel.fromJson(row));
            } catch (e) {
              debugPrint('CommentService: skipping bad comment row: $e');
            }
          }
          return comments;
        });
  }

  Future<CommentModel> postComment({
    required String incidentId,
    required String authorId,
    required String authorName,
    required String authorRole,
    required String message,
  }) async {
    final result = await _supabase.client
        .from('incident_comments')
        .insert({
          'incident_id': incidentId,
          'author_id': authorId,
          'author_name': authorName,
          'author_role': authorRole,
          'message': message,
        })
        .select()
        .single();

    return CommentModel.fromJson(result);
  }
}
