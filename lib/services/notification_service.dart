import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import '../models/notification_model.dart';

class NotificationService {
  final _supabase = SupabaseService.instance;

  /// Send a notification to a specific user.
  Future<void> send({
    required String userId,
    required String title,
    required String body,
    required String type,
    String? incidentId,
  }) async {
    await _supabase.client.from('notifications').insert({
      'user_id': userId,
      'title': title,
      'body': body,
      'type': type,
      'incident_id': incidentId,
      'is_read': false,
    });
  }

  /// Sends the same notification to many people in one round trip.
  ///
  /// A loop of single inserts would be N network calls and could half-succeed,
  /// leaving some of the hall alerted and the rest not — the worst outcome for
  /// a mass alert, because nobody can tell who was missed. One insert either
  /// reaches everyone or fails cleanly.
  Future<void> sendBulk({
    required List<String> userIds,
    required String title,
    required String body,
    required String type,
    String? incidentId,
  }) async {
    if (userIds.isEmpty) return;

    await _supabase.client.from('notifications').insert([
      for (final id in userIds)
        {
          'user_id': id,
          'title': title,
          'body': body,
          'type': type,
          'incident_id': incidentId,
          'is_read': false,
        }
    ]);
  }

  /// Get all notifications for the current user, newest first.
  Future<List<NotificationModel>> getMyNotifications() async {
    final userId = _supabase.client.auth.currentUser?.id;
    if (userId == null) return [];
    final data = await _supabase.client
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50);
    return (data as List).map((j) => NotificationModel.fromJson(j)).toList();
  }

  /// Unread count for the current user.
  Future<int> getUnreadCount() async {
    final userId = _supabase.client.auth.currentUser?.id;
    if (userId == null) return 0;
    // Counted server-side with a HEAD request. This used to select every
    // unread row and take `.length` — one row over the wire per unread
    // notification, to render a badge number.
    final data = await _supabase.client
        .from('notifications')
        .count(CountOption.exact)
        .eq('user_id', userId)
        .eq('is_read', false);
    return data;
  }

  /// Mark a single notification as read.
  Future<void> markRead(String notificationId) async {
    await _supabase.client
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId);
  }

  /// Mark all notifications as read for the current user.
  Future<void> markAllRead() async {
    final userId = _supabase.client.auth.currentUser?.id;
    if (userId == null) return;
    await _supabase.client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('is_read', false);
  }

  /// Delete a notification by id.
  Future<void> delete(String notificationId) async {
    await _supabase.client
        .from('notifications')
        .delete()
        .eq('id', notificationId);
  }

  /// Real-time stream of notifications for the current user.
  Stream<List<Map<String, dynamic>>> streamMyNotifications() {
    final userId = _supabase.client.auth.currentUser?.id;
    if (userId == null) return const Stream.empty();
    return _supabase.client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50);
  }
}
