import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../config/app_config.dart';
import 'local_notification_service.dart';
import '../utils/incident_route.dart';

// Top-level handler — runs even when app is killed
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await LocalNotificationService.show(
    title: message.notification?.title ?? AppConfig.appName,
    body: message.notification?.body ?? '',
    payload: message.data['incidentId'],
  );
}

/// Notification types the app already turns into a pop-up itself while it is
/// open (see lib/widgets/alert_host.dart). A push for one of these that arrives
/// in the foreground would show the same message twice.
const Set<String> kInAppEscalationTypes = {
  'escalation',
  'escalation_resident',
  'responder_update',
  'responder_taken',
};

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  /// Resolved on use, not on construction.
  ///
  /// This was `final _fcm = FirebaseMessaging.instance;`, a field initializer,
  /// which runs the moment anything first touches [instance]. `FirebaseMessaging
  /// .instance` throws `[core/no-app]` when `Firebase.initializeApp()` has not
  /// run — and the web entry point (`lib/main_web.dart`) deliberately never
  /// calls it, because push on web needs a service worker and VAPID key an
  /// admin dashboard has no use for.
  ///
  /// The visible symptom was Sign out throwing for an admin: `signOut()` calls
  /// `FcmService.instance.unsubscribeFromBarangay(...).catchError(...)`, and
  /// the throw happened while *evaluating* `instance`, before any Future
  /// existed for `catchError` to attach to. A lazy getter plus the [kIsWeb]
  /// guards below mean the browser never reaches this at all.
  FirebaseMessaging get _fcm => FirebaseMessaging.instance;

  static GlobalKey<NavigatorState>? _navigatorKey;

  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  Future<void> initialize() async {
    // Register background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    // Request permission (iOS + Android 13+)
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Foreground notification display (Android)
    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Listen to foreground messages
    FirebaseMessaging.onMessage.listen((message) {
      // The open app shows these as pop-ups from its own realtime feed.
      if (kInAppEscalationTypes.contains(message.data['type'])) return;
      final notification = message.notification;
      if (notification != null) {
        LocalNotificationService.show(
          title: notification.title ?? AppConfig.appName,
          body: notification.body ?? '',
          payload: message.data['incidentId'],
        );
      }
    });

    // App opened from a notification (background → foreground)
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleNotificationTap(message.data);
    });

    // App launched from a terminated state via notification
    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      _handleNotificationTap(initial.data);
    }
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    final incidentId = data['incidentId'];
    if (incidentId != null) {
      // Route by role: a resident must never land on the official
          // manage screen, which exposes Mark Resolved / Flag / Delete.
          final ctx = _navigatorKey?.currentContext;
          final route = ctx != null
              ? incidentRouteForCurrentUser(ctx)
              : '/report-detail';
          _navigatorKey?.currentState?.pushNamed(route, arguments: incidentId);
    }
  }

  // ── Topic subscriptions ───────────────────────────────────────────────────
  //
  // Each is a no-op on web. Topic subscription is an FCM feature that needs an
  // initialised Firebase app and a registered service worker; the web
  // dashboard has neither by design. Returning quietly rather than throwing
  // keeps the callers — sign-in, sign-out, opening an incident — identical on
  // both surfaces, so neither has to know which platform it is running on.

  Future<String?> getToken() async => kIsWeb ? null : await _fcm.getToken();

  // Subscribe to barangay topic so officials get alerts for their area
  Future<void> subscribeToBarangay(String barangayId) async {
    if (kIsWeb) return;
    await _fcm.subscribeToTopic('barangay_$barangayId');
  }

  Future<void> unsubscribeFromBarangay(String barangayId) async {
    if (kIsWeb) return;
    await _fcm.unsubscribeFromTopic('barangay_$barangayId');
  }

  Future<void> subscribeToTopic(String topic) async {
    if (kIsWeb) return;
    await _fcm.subscribeToTopic(topic);
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    if (kIsWeb) return;
    await _fcm.unsubscribeFromTopic(topic);
  }

  /// The person's own topic, `user_<id>`: how a push reaches THIS person's
  /// phone while the app is closed (supabase/functions/push-notification). A
  /// topic rather than a stored device token, so there is no token table to
  /// keep in step; the id is a UUID, so the name is not guessable.
  Future<void> subscribeToUser(String userId) async {
    if (kIsWeb) return;
    await _fcm.subscribeToTopic('user_$userId');
  }

  Future<void> unsubscribeFromUser(String userId) async {
    if (kIsWeb) return;
    await _fcm.unsubscribeFromTopic('user_$userId');
  }

  // Subscribe to a specific incident for updates
  Future<void> subscribeToIncident(String incidentId) async {
    if (kIsWeb) return;
    await _fcm.subscribeToTopic('incident_$incidentId');
  }
}
