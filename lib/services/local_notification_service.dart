import '../utils/notification_route.dart';
import 'package:flutter/material.dart';
import '../config/app_config.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class LocalNotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static GlobalKey<NavigatorState>? _navigatorKey;

  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// Call once at app startup (before runApp or in main()).
  static Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    // The push messages from the server (supabase/functions/push-notification,
    // notify-new-incident) name this channel. Android creates a channel only when
    // something first uses it, and a push that names a channel which does not exist
    // falls back to a quiet default. Creating it now, with high importance, makes
    // those pushes pop up with a sound from the very first one.
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          'barangay_safety_channel',
          AppConfig.appName,
          description: 'Incident updates and official notifications',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ));

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        final payload = details.payload;
        final ctx = _navigatorKey?.currentContext;
        if (payload == null || payload.isEmpty || ctx == null) return;

        // Routes by type AND by role. Role matters because a resident must
        // never land on the official manage screen, which exposes Mark
        // Resolved / Flag / Delete on their own case.
        final target = targetFromPayload(ctx, payload);
        if (target != null) {
          _navigatorKey?.currentState?.pushNamed(
            target.route,
            arguments: target.arguments,
          );
        }
      },
    );

    _initialized = true;
  }

  /// Request device notification permission (Android 13+).
  /// Shows the system dialog the first time.
  static Future<bool> requestPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// Check if permission is already granted (no dialog).
  static Future<bool> isPermissionGranted() async {
    return await Permission.notification.isGranted;
  }

  /// Show a local notification banner immediately.
  static Future<void> show({
    required String title,
    required String body,
    String? payload,
    int id = 0,
  }) async {
    if (!_initialized) await initialize();

    const androidDetails = AndroidNotificationDetails(
      'barangay_safety_channel',
      AppConfig.appName,
      channelDescription: 'Incident updates and official notifications',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(id, title, body, details, payload: payload);
  }
}
