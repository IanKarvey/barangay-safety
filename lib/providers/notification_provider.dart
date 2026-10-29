import '../utils/notification_route.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';
import '../services/fcm_service.dart';
import '../services/local_notification_service.dart';
import '../services/supabase_service.dart';

class NotificationProvider extends ChangeNotifier {
  final _service = NotificationService();

  List<NotificationModel> _notifications = [];

  /// Ids the user has swiped away.
  ///
  /// Persisted, and that is the point. Dismissing deletes the row server-side,
  /// but the delete is refused when the `notifications` RLS policy grants only
  /// SELECT and UPDATE — which is the reported "dismissed notifications come
  /// back" bug. This set used to live only in memory, so it papered over the
  /// refusal until the app restarted and every dismissed item returned.
  ///
  /// Keeping it on disk makes dismissal stick regardless of what the server
  /// allows. It is a backstop, not the fix: see [_recordDismissed] for the
  /// logging that makes the underlying refusal visible.
  final Set<String> _dismissedIds = {};

  static const _dismissedKey = 'dismissed_notification_ids';

  String? get _uid => SupabaseService.instance.client.auth.currentUser?.id;

  /// Per-account, so one user's dismissals never hide another's alerts on a
  /// shared barangay-hall phone.
  String get _storageKey => '${_dismissedKey}_${_uid ?? 'anon'}';

  Future<void> _loadDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _dismissedIds
        ..clear()
        ..addAll(prefs.getStringList(_storageKey) ?? const []);
    } catch (e) {
      debugPrint('NotificationProvider: could not read dismissed ids — $e');
    }
  }

  Future<void> _recordDismissed(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_storageKey, _dismissedIds.toList());
    } catch (e) {
      debugPrint('NotificationProvider: could not persist dismissed ids — $e');
    }
  }

  /// Drops ids whose rows are genuinely gone from the server.
  ///
  /// Without this the set grows for the life of the install. With it, a
  /// successful delete prunes itself on the next load and only the ids the
  /// server refused to delete are retained.
  Future<void> _pruneDismissed(Iterable<String> serverIds) async {
    final live = serverIds.toSet();
    final before = _dismissedIds.length;
    _dismissedIds.removeWhere((id) => !live.contains(id));
    if (_dismissedIds.length != before) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_storageKey, _dismissedIds.toList());
      } catch (_) {
        // Pruning is housekeeping; failing to write it costs nothing today.
      }
    }
  }
  StreamSubscription? _subscription;

  /// Notifications that ARRIVE while the app is open (not the history loaded at
  /// start). The escalation pop-ups listen here; the notification list does not.
  final _arrivals = StreamController<NotificationModel>.broadcast();
  Stream<NotificationModel> get arrivals => _arrivals.stream;

  bool _isLoading = false;
  bool _subscriptionInitialized = false;

  List<NotificationModel> get notifications => _notifications;
  bool get isLoading => _isLoading;
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  List<NotificationModel> _filter(List<NotificationModel> list) =>
      list.where((n) => !_dismissedIds.contains(n.id)).toList();

  /// Start listening to real-time notifications for the signed-in user.
  void subscribe() {
    _subscription?.cancel();
    _subscriptionInitialized = false;
    // Realtime can deliver before load() finishes, and an un-hydrated filter
    // would flash previously dismissed items back onto the screen.
    unawaited(_loadDismissed());
    _subscribePush();
    _subscription = _service.streamMyNotifications().listen((data) {
      final updated = _filter(
        data.map((j) => NotificationModel.fromJson(j)).toList(),
      );

      // Skip banners on the first event (existing historical notifications).
      // Only fire banners for notifications that arrive after initial load.
      if (_subscriptionInitialized) {
        final existingIds = _notifications.map((n) => n.id).toSet();
        for (final n in updated) {
          if (!n.isRead && !existingIds.contains(n.id)) {
            if (!_arrivals.isClosed) _arrivals.add(n);
            // The system banner needs a plugin the browser doesn't have; on
            // the web dashboard the in-app pop-up takes its place.
            if (!kIsWeb) {
              LocalNotificationService.show(
                title: n.title,
                body: n.body,
                // Type travels with the id so a notification without an
                // incident still knows where to send the user.
                payload: encodeNotificationPayload(n.type, n.incidentId),
                id: n.id.hashCode,
              );
            }
          }
        }
      }

      _subscriptionInitialized = true;
      _notifications = updated;
      _safeNotify();
    });
  }

  /// Lets a push reach this phone while the app is closed. Best effort: the app
  /// works without it, and Firebase is not even present on the web dashboard.
  void _subscribePush() {
    final uid = _uid;
    if (kIsWeb || uid == null) return;
    FcmService.instance.subscribeToUser(uid).catchError((Object e) {
      debugPrint('NotificationProvider: push subscription failed — $e');
    });
  }

  Future<void> load() async {
    _isLoading = true;
    _safeNotify();
    try {
      await _loadDismissed();
      final all = await _service.getMyNotifications();
      await _pruneDismissed(all.map((n) => n.id));
      _notifications = _filter(all);
    } catch (e) {
      // Was unguarded: a thrown fetch left `_isLoading` true forever, so the
      // notifications screen sat on a spinner that never resolved and offered
      // no way to retry.
      debugPrint('NotificationProvider: load failed — $e');
    }
    _isLoading = false;
    _safeNotify();
  }

  Future<void> markRead(String id) async {
    try {
      await _service.markRead(id);
    } catch (e) {
      // Called from a tap handler; an uncaught throw here is an unhandled
      // async error, not something the user can see or retry.
      debugPrint('NotificationProvider: markRead failed — $e');
      return;
    }
    final idx = _notifications.indexWhere((n) => n.id == id);
    if (idx != -1) {
      _notifications[idx] = _notifications[idx].copyWith(isRead: true);
      _safeNotify();
    }
  }

  void dismiss(String id) {
    _dismissedIds.add(id);
    _notifications.removeWhere((n) => n.id == id);
    _safeNotify();

    // Local record first, so the dismissal holds even if the server refuses.
    unawaited(_recordDismissed(id));

    // The refusal itself is logged rather than discarded. `catchError((_) {})`
    // hid a policy problem that then presented as a UI bug nobody could trace:
    // the row was never deleted, and only an in-memory set was hiding it.
    unawaited(_service.delete(id).catchError((Object e) {
      debugPrint(
        'NotificationProvider: server refused to delete notification $id — $e. '
        'Dismissal is being held locally instead. If this repeats, the '
        'notifications table is missing a DELETE policy for the owning user.',
      );
    }));
  }

  Future<void> markAllRead() async {
    try {
      await _service.markAllRead();
    } catch (e) {
      debugPrint('NotificationProvider: markAllRead failed — $e');
      return;
    }
    _notifications = _notifications.map((n) => n.copyWith(isRead: true)).toList();
    _safeNotify();
  }

  void unsubscribe() {
    _subscription?.cancel();
    _subscription = null;
    _notifications = [];
    // Only the in-memory copy is cleared — the persisted set stays, keyed by
    // account, so signing out and back in does not resurrect every
    // notification the user already dealt with.
    _dismissedIds.clear();
    _safeNotify();
  }

// ── Disposal safety ───────────────────────────────────────────────────
  // Providers are torn down on logout and on navigation while their async
  // work is still in flight. `notifyListeners()` after `dispose()` throws
  // `A ChangeNotifier was used after being disposed` — an unhandled error on
  // a background future, which the user sees as a crash they cannot retry.
  bool _disposed = false;

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _arrivals.close();
    super.dispose();
  }
}
