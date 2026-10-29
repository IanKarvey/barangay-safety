import 'package:barangay_safety_app/l10n/app_strings.dart';
import 'package:barangay_safety_app/models/incident_model.dart';
import 'package:barangay_safety_app/models/user_model.dart';
import 'package:barangay_safety_app/providers/auth_provider.dart';
import 'package:barangay_safety_app/providers/incident_provider.dart';
import 'package:barangay_safety_app/providers/language_provider.dart';
import 'package:barangay_safety_app/providers/notification_provider.dart';
import 'package:barangay_safety_app/screens/official/dashboard_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Only the getters DashboardTab reads are real; everything else on these
// providers would reach for Supabase, which does not exist in a test.
class _FakeAuth extends ChangeNotifier implements AuthProvider {
  _FakeAuth(this._user);
  final UserModel _user;
  @override
  UserModel? get user => _user;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeIncidents extends ChangeNotifier implements IncidentProvider {
  _FakeIncidents(this._incidents, this._stats);
  final List<IncidentModel> _incidents;
  final Map<String, int> _stats;
  @override
  List<IncidentModel> get incidents => _incidents;
  @override
  Map<String, int> get stats => _stats;
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

IncidentModel _incident(int i, {int severity = 4, String status = 'pending'}) {
  final now = DateTime.now();
  return IncidentModel(
    id: 'incident-$i-aaaaaaaaaaaa',
    barangayId: 'b1',
    category: 'Fire',
    description: 'Report number $i',
    severityLevel: severity,
    status: status,
    latitude: 13.94,
    longitude: 121.16,
    createdAt: now.subtract(Duration(hours: i)),
    updatedAt: now,
  );
}

Future<List<String>> _pump(WidgetTester tester, double width) async {
  // IncidentCard wraps AppText (AutoSizeText -> LayoutBuilder) in an
  // IntrinsicHeight. Flutter asserts that combination in DEBUG builds only; a
  // release build, which is what runs on a phone and in the browser, quietly
  // treats it as zero. Without this the test fails on the card itself and
  // never reaches the layout being checked. This is a pre-existing quirk of
  // the card, unrelated to the dashboard layout.
  RenderObject.debugCheckingIntrinsics = true;
  addTearDown(() => RenderObject.debugCheckingIntrinsics = false);

  // takeException() folds several errors into one "Multiple exceptions" blob,
  // which hides what each one was. Collect them individually instead.
  final collected = <String>[];
  final previousHandler = FlutterError.onError;
  FlutterError.onError = (details) => collected.add(details.exceptionAsString());

  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

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

  final incidents = [
    for (var i = 0; i < 6; i++) _incident(i),
    _incident(7, severity: 1, status: 'resolved'),
  ];

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: _FakeAuth(admin)),
        ChangeNotifierProvider<IncidentProvider>.value(
          value: _FakeIncidents(incidents, {
            'total': 7,
            'pending': 6,
            'in_progress': 0,
            'resolved': 1,
            'flagged': 0,
          }),
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
            home: Scaffold(
              body: DashboardTab(onRefresh: () {}),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2));

  // Collect every layout exception — the failure that hid the dashboard was a
  // silent one in release, so under test it must be loud.
  //
  // Plain overflow warnings are filtered out. They come from IncidentCard's own
  // IntrinsicHeight under-measuring the card, which is separate from this
  // layout, depends on the test font, and does not stop layout. The errors that
  // matter here (infinite height, a failed constraint, a null geometry) all
  // still fail the test.
  FlutterError.onError = previousHandler;
  return [
    for (final text in collected)
      if (!text.contains('overflowed by')) text.split('\n').first,
  ];
}

void main() {
  for (final width in [1300.0, 400.0]) {
    testWidgets('the dashboard lays out with no errors at ${width.toInt()}px',
        (tester) async {
      final errors = await _pump(tester, width);
      expect(errors, isEmpty, reason: errors.join('\n'));
    });

    testWidgets(
        'everything below the stat cards is still on screen at ${width.toInt()}px',
        (tester) async {
      await _pump(tester, width);

      // These sit below the Overview row. When the resolution/severity pair
      // threw, they were the content that disappeared.
      expect(find.text('Resolution Rate'), findsWidgets,
          reason: 'the resolution card was missing');
      expect(find.text('Active by Severity'), findsWidgets,
          reason: 'the severity chart was missing');
    });
  }

  testWidgets('on a desktop the resolution and severity cards share a row',
      (tester) async {
    await _pump(tester, 1300);

    final resolution = tester.getTopLeft(find.text('Resolution Rate').first);
    final severity = tester.getTopLeft(find.text('Active by Severity').first);
    expect(severity.dx, greaterThan(resolution.dx));
    expect((severity.dy - resolution.dy).abs(), lessThan(40),
        reason: 'they should sit at about the same height');
  });

  testWidgets('on a phone they stack', (tester) async {
    await _pump(tester, 400);

    final resolution = tester.getTopLeft(find.text('Resolution Rate').first);
    final severity = tester.getTopLeft(find.text('Active by Severity').first);
    expect(severity.dy, greaterThan(resolution.dy + 40));
  });
}
