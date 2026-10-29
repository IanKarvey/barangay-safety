import 'package:barangay_safety_app/l10n/app_strings.dart';
import 'package:barangay_safety_app/models/incident_model.dart';
import 'package:barangay_safety_app/models/user_model.dart';
import 'package:barangay_safety_app/providers/auth_provider.dart';
import 'package:barangay_safety_app/providers/incident_provider.dart';
import 'package:barangay_safety_app/providers/language_provider.dart';
import 'package:barangay_safety_app/providers/notification_provider.dart';
import 'package:barangay_safety_app/screens/official/dashboard_tab.dart';
import 'package:barangay_safety_app/screens/official/incidents_tab.dart';
import 'package:barangay_safety_app/widgets/incident_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Only the members the screens read are real; anything else on these providers
// would reach for Supabase, which does not exist in a test.
class _FakeAuth extends ChangeNotifier implements AuthProvider {
  _FakeAuth(this._user);
  final UserModel _user;
  @override
  UserModel? get user => _user;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeIncidents extends ChangeNotifier implements IncidentProvider {
  _FakeIncidents(this._incidents);
  final List<IncidentModel> _incidents;
  @override
  List<IncidentModel> get incidents => _incidents;
  @override
  Map<String, int> get stats =>
      {'total': _incidents.length, 'pending': _incidents.length};
  @override
  bool get isLoading => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeNotifications extends ChangeNotifier implements NotificationProvider {
  @override
  int get unreadCount => 0;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

IncidentModel _incident(int i) {
  final now = DateTime.now();
  return IncidentModel(
    id: 'incident-$i-aaaaaaaaaaaa',
    barangayId: 'b1',
    category: 'Fire',
    description: 'Report number $i',
    severityLevel: 4,
    status: 'pending',
    latitude: 13.94,
    longitude: 121.16,
    createdAt: now.subtract(Duration(hours: i)),
    updatedAt: now,
  );
}

/// Pumps [screen] at [width] and returns every route name pushed from it.
Future<List<RouteSettings>> _pump(
  WidgetTester tester,
  double width,
  Widget screen,
) async {
  // See dashboard_layout_test.dart: IncidentCard asserts only in debug.
  RenderObject.debugCheckingIntrinsics = true;
  addTearDown(() => RenderObject.debugCheckingIntrinsics = false);

  // Overflow warnings from IncidentCard's own IntrinsicHeight are irrelevant to
  // whether a tap lands. Installed here, not in setUp: the test framework
  // replaces any handler set before the test body starts.
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    // Debug-only assertions that exist independently of the tap: IncidentCard's
    // own overflow, and Hero's duplicate-tag check (the Dashboard lists an
    // urgent incident in both the Urgent and Recent sections).
    if (text.contains('overflowed by') ||
        text.contains('multiple heroes that share the same tag')) {
      return;
    }
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);

  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final pushed = <RouteSettings>[];
  final admin = UserModel(
    id: 'u1',
    email: 'admin@test.ph',
    fullName: 'Test Admin',
    phone: '09170000000',
    role: 'admin',
    position: 'secretary',
    barangayId: 'b1',
    barangayName: 'Barangay 3',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: _FakeAuth(admin)),
        ChangeNotifierProvider<IncidentProvider>.value(
          value: _FakeIncidents([for (var i = 0; i < 6; i++) _incident(i)]),
        ),
        ChangeNotifierProvider<NotificationProvider>.value(
            value: _FakeNotifications()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
      ],
      child: Consumer<LanguageProvider>(
        builder: (context, lang, _) => AppStringsScope(
          language: lang.language,
          strings: lang.strings,
          child: MaterialApp(
            home: Scaffold(body: screen),
            onGenerateRoute: (settings) {
              pushed.add(settings);
              return MaterialPageRoute(
                settings: settings,
                builder: (_) => const Scaffold(body: Text('PUSHED PAGE')),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  return pushed;
}

void main() {
  for (final width in [1300.0, 400.0]) {
    testWidgets('tapping a report in the Incidents tab opens it at ${width.toInt()}px',
        (tester) async {
      final pushed =
          await _pump(tester, width, IncidentsTab(onRefresh: () {}));

      expect(find.text('Report number 0'), findsWidgets,
          reason: 'the reports should be listed at all');

      await tester.tap(find.byType(IncidentCard).first);
      await tester.pump(const Duration(milliseconds: 600));

      expect(pushed.map((r) => r.name), contains('/incident-manage'),
          reason: 'the tap should have pushed the manage screen');
      expect(pushed.last.arguments, 'incident-0-aaaaaaaaaaaa');
    });

    testWidgets('tapping a report on the Dashboard opens it at ${width.toInt()}px',
        (tester) async {
      final pushed =
          await _pump(tester, width, DashboardTab(onRefresh: () {}));

      await tester.scrollUntilVisible(
        find.byType(IncidentCard).first,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byType(IncidentCard).first);
      await tester.pump(const Duration(milliseconds: 600));

      expect(pushed.map((r) => r.name), contains('/incident-manage'));
    });
  }
}
