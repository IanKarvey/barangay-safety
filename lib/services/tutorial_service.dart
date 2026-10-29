import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_service.dart';

/// Where the tutorial's usage is recorded. An interface so the screen can be
/// tested without a database.
abstract class TutorialLog {
  /// Records that the tutorial was opened. Returns an id to update later, or
  /// null when it could not be recorded.
  Future<String?> opened({required String source, bool practice = false});

  /// Records how far the person got, and whether they reached the end.
  Future<void> progress(String? logId,
      {required int stepsViewed, required bool completed});
}

/// Tutorial bookkeeping: whether it has been shown to this person before, and
/// the usage log.
///
/// Logging is best-effort by design. The tutorial is for someone who may be
/// stuck, so a failed write must never get in the way of it opening.
class TutorialService implements TutorialLog {
  final _db = SupabaseService.instance;

  static String _seenKey(String userId) => 'report_tutorial_seen_$userId';

  /// Has this person already been shown the tutorial automatically?
  /// Kept on the phone, per account: a second person signing in on a shared
  /// phone still gets their own first-time tutorial.
  static Future<bool> hasSeen(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_seenKey(userId)) ?? false;
    } catch (_) {
      // If storage is unreadable, do NOT show it: better to miss one showing
      // than to show it on every launch.
      return true;
    }
  }

  static Future<void> markSeen(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_seenKey(userId), true);
    } catch (e) {
      debugPrint('TutorialService: could not remember the tutorial was shown — $e');
    }
  }

  @override
  Future<String?> opened({required String source, bool practice = false}) async {
    try {
      final uid = _db.client.auth.currentUser?.id;
      if (uid == null) return null;
      final row = await _db.client
          .from('tutorial_logs')
          .insert({'user_id': uid, 'source': source, 'practice': practice})
          .select('id')
          .single();
      return row['id'] as String?;
    } catch (e) {
      debugPrint('TutorialService: usage not recorded — $e');
      return null;
    }
  }

  @override
  Future<void> progress(String? logId,
      {required int stepsViewed, required bool completed}) async {
    if (logId == null) return;
    try {
      await _db.client.from('tutorial_logs').update({
        'steps_viewed': stepsViewed,
        'completed': completed,
      }).eq('id', logId);
    } catch (e) {
      debugPrint('TutorialService: progress not recorded — $e');
    }
  }
}
