// A throwaway harness for clicking through the web dashboard in a real browser
// WITHOUT a login. Not part of the app and never deployed.
//
// It mounts the real shell (WebShell) and the real route table
// (webOnGenerateRoute, the one the live site uses) over FAKE data, so a browser
// robot can click a report and see whether it opens. The point is to reproduce
// "I press a report in the dashboard and nothing happens" in the same compiled
// form the site ships in, instead of reasoning about it from the code.
//
//   flutter build web -t tool/web_demo/main.dart -o build/web_demo --pwa-strategy=none
import 'package:barangay_safety_app/l10n/app_strings.dart';
import 'package:barangay_safety_app/main_web.dart'
    show webNavigatorKey, webOnGenerateRoute;
import 'package:barangay_safety_app/models/incident_model.dart';
import 'package:barangay_safety_app/models/notification_model.dart';
import 'package:barangay_safety_app/widgets/alert_host.dart';
import 'package:barangay_safety_app/models/user_model.dart';
import 'package:barangay_safety_app/providers/auth_provider.dart';
import 'package:barangay_safety_app/providers/incident_provider.dart';
import 'package:barangay_safety_app/providers/language_provider.dart';
import 'package:barangay_safety_app/providers/notification_provider.dart';
import 'package:barangay_safety_app/screens/web/web_shell.dart';
import 'package:barangay_safety_app/screens/web/web_update_banner.dart';
import 'package:barangay_safety_app/services/supabase_service.dart';
import 'package:barangay_safety_app/utils/theme.dart';
import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

final _admin = UserModel(
  id: '00000000-0000-4000-8000-0000000000d1',
  email: 'juan@demo.ph',
  fullName: 'Juan Dela Cruz',
  phone: '09170000000',
  role: 'admin',
  position: 'secretary',
  barangayId: '00000000-0000-4000-8000-0000000000c3',
  barangayName: 'Barangay 3',
  isVerified: true,
  createdAt: DateTime.now(),
  updatedAt: DateTime.now(),
);

IncidentModel _incident(
  String id,
  String category,
  String status,
  int hoursAgo, {
  bool nonResident = false,
  int severity = 1,
  int minutesAgo = 0,
  int escalationLevel = 0,
}) {
  final created =
      DateTime.now().subtract(Duration(hours: hoursAgo, minutes: minutesAgo));
  return IncidentModel(
    id: id,
    barangayId: '00000000-0000-4000-8000-0000000000c3',
    category: category,
    description: nonResident
        ? 'Andrei reported an emergency via the non-resident flow. Contact: 09000000004'
        : 'Report ${id.substring(id.length - 2)}',
    severityLevel: severity,
    status: status,
    latitude: 13.9420,
    longitude: 121.1640,
    createdAt: created,
    updatedAt: created,
    reportedBySessionId: nonResident ? '00000000-0000-4000-8000-0000000000e1' : null,
    barangayName: 'Barangay 3',
    escalationLevel: escalationLevel,
  );
}

final _incidents = [
  // Unanswered reports: the live timers, one in each colour band.
  _incident('00000000-0000-4000-8000-0000000000c1', 'Fire', 'pending', 0, severity: 4, minutesAgo: 2),
  _incident('00000000-0000-4000-8000-0000000000c2', 'Vehicular Accident', 'pending', 0, severity: 3, minutesAgo: 7, escalationLevel: 1),
  _incident('00000000-0000-4000-8000-0000000000c3', 'Medical Emergency', 'pending', 0, severity: 4, minutesAgo: 12, escalationLevel: 2),
  _incident('00000000-0000-4000-8000-0000000000c4', 'Physical Assault', 'pending', 0, severity: 4, minutesAgo: 20, escalationLevel: 3),
  _incident('00000000-0000-4000-8000-0000000000a1', 'Emergency (Non-Resident)', 'resolved', 1200, nonResident: true),
  _incident('00000000-0000-4000-8000-0000000000a2', 'Emergency (Non-Resident)', 'responding', 1229, nonResident: true),
  _incident('00000000-0000-4000-8000-0000000000a3', 'Emergency (Non-Resident)', 'resolved', 1250, nonResident: true, severity: 4),
  _incident('00000000-0000-4000-8000-0000000000b1', 'Noise Disturbance', 'pending', 3),
  _incident('00000000-0000-4000-8000-0000000000b2', 'Public Disturbance', 'verified', 30, severity: 2),
];

class _FakeAuth extends ChangeNotifier implements AuthProvider {
  @override
  UserModel? get user => _admin;
  @override
  bool get isLoading => false;
  @override
  String? get error => null;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> signOut() async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeIncidents extends ChangeNotifier implements IncidentProvider {
  IncidentModel? _selected;
  @override
  List<IncidentModel> get incidents => _incidents;
  @override
  Map<String, int> get stats =>
      {'total': 5, 'pending': 1, 'in_progress': 1, 'resolved': 2, 'flagged': 0};
  @override
  bool get isLoading => false;
  @override
  String? get error => null;
  @override
  IncidentModel? get selectedIncident => _selected;
  @override
  Future<void> loadIncident(String id, {bool silent = false}) async {
    _selected = _incidents.firstWhere((i) => i.id == id);
    notifyListeners();
  }

  @override
  Future<void> loadBarangayIncidents(String id, {bool silent = false}) async {}
  @override
  Future<void> loadAllIncidents({bool silent = false}) async {}
  @override
  Future<void> loadStats(String? id) async {}
  @override
  void subscribeToBarangay(String id) {}
  @override
  void subscribeToAll() {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeNotifications extends ChangeNotifier implements NotificationProvider {
  final _arrivals = StreamController<NotificationModel>.broadcast();
  @override
  Stream<NotificationModel> get arrivals => _arrivals.stream;
  @override
  int get unreadCount => 1;
  @override
  bool get isLoading => false;
  @override
  void subscribe() {
    // Six seconds after the dashboard opens, an "unanswered report" alert
    // arrives, so the pop-up (and its web tone) can be seen in a real browser.
    Future.delayed(const Duration(seconds: 6), () {
      _arrivals.add(NotificationModel(
        id: 'demo-alert',
        userId: 'demo',
        title: 'UNATTENDED - last resort',
        body: 'Physical Assault in Barangay 3 has had NO response for 20 min. '
            'Flagged Unattended. City administrator alerted.',
        type: 'escalation',
        incidentId: '00000000-0000-4000-8000-0000000000c4',
        isRead: false,
        createdAt: DateTime.now(),
        data: const {'kind': 'unanswered', 'level': 3},
      ));
    });
  }
  @override
  Future<void> load() async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A release build collapses an exception to "Instance of 'minified:jh'", which
  // says nothing. Print the real message and where it came from.
  FlutterError.onError = (d) {
    debugPrint('FLUTTER ERROR: ${d.exceptionAsString()}');
    debugPrint('IN: ${d.context?.toDescription()}');
    debugPrint('STACK: ${d.stack.toString().split('\n').take(14).join(' | ')}');
  };
  PlatformDispatcher.instance.onError = (e, s) {
    debugPrint('ASYNC ERROR: $e');
    return true;
  };
  await initializeDateFormatting('en_US');
  // Real Supabase client, no session: calls the screens make on their own
  // (comments, audit log, officials) go out for real and come back empty, as
  // they would for any account that cannot see the data.
  await SupabaseService.initialize();
  runApp(const _Demo());
}

class _Demo extends StatelessWidget {
  const _Demo();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => _FakeAuth()),
        ChangeNotifierProvider<IncidentProvider>(create: (_) => _FakeIncidents()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => _FakeNotifications()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()..load()),
      ],
      child: Consumer<LanguageProvider>(
        builder: (context, lang, _) => AppStringsScope(
          language: lang.language,
          strings: lang.strings,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            navigatorKey: webNavigatorKey,
            home: const WebShell(),
            onGenerateRoute: webOnGenerateRoute,
            // Same placement as the live app (main_web.dart).
            builder: (context, child) => AlertHost(
              navigatorKey: webNavigatorKey,
              child: Column(
                children: [
                  const UpdateBanner(),
                  Expanded(child: child ?? const SizedBox()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
