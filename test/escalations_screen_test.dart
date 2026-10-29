import 'package:barangay_safety_app/screens/shared/escalations_screen.dart';
import 'package:barangay_safety_app/services/escalation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/render.dart';

class _FakeSource implements EscalationSource {
  _FakeSource({
    this.escalationList = const [],
    this.referralList = const [],
    this.fail = false,
  });

  final List<EscalationEntry> escalationList;
  final List<ReferralEntry> referralList;
  final bool fail;

  @override
  Future<List<EscalationEntry>> escalations() async {
    if (fail) throw Exception('offline');
    return escalationList;
  }

  @override
  Future<List<ReferralEntry>> referrals() async {
    if (fail) throw Exception('offline');
    return referralList;
  }
}

EscalationEntry _esc(int level, String category, int hoursAgo, {int told = 2}) =>
    EscalationEntry(
      id: 'e$level$category',
      incidentId: 'incident-$level',
      level: level,
      recipients: told,
      createdAt: DateTime.now().subtract(Duration(hours: hoursAgo)),
      category: category,
      barangayName: 'Barangay 3',
      status: 'responding',
    );

EscalationEntry _unanswered(int level, String category, int minutesAgo, {int told = 3}) =>
    EscalationEntry(
      id: 'u$level$category',
      incidentId: 'incident-u$level',
      level: level,
      recipients: told,
      createdAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
      category: category,
      barangayName: 'Barangay 7',
      status: 'pending',
      unanswered: true,
    );

ReferralEntry _ref(String category, String agency, int hoursAgo) => ReferralEntry(
      id: 'r$category',
      category: category,
      agency: agency,
      createdAt: DateTime.now().subtract(Duration(hours: hoursAgo)),
      barangayName: 'Barangay 1',
    );

void main() {
  setUpAll(loadRealFonts);

  final source = _FakeSource(
    escalationList: [
      _esc(3, 'Vandalism', 2, told: 4),
      _esc(2, 'Public Disturbance', 5),
      _esc(1, 'Noise Disturbance', 9, told: 1),
    ],
    referralList: [
      _ref('Fire', 'fire', 1),
      _ref('Vehicular Accident', 'lto', 3),
      _ref('Physical Assault', 'police', 6),
      _ref('Flooding', 'disaster', 20),
    ],
  );

  for (final size in [const Size(400, 760), const Size(1280, 800)]) {
    testWidgets('renders both lists at ${size.width.toInt()}px', (tester) async {
      useSize(tester, size);
      await tester.pumpWidget(renderApp(EscalationsScreen(source: source)));
      // Settle, not a fixed pump: the tiles fade in on a stagger, and a picture
      // taken mid-fade shows an empty list.
      await tester.pumpAndSettle();

      // Escalations tab first
      expect(find.text('City level'), findsWidgets);
      expect(find.text('Overdue'), findsWidgets);
      expect(find.text('Reminder'), findsWidgets);
      expect(find.textContaining('4 officials notified'), findsOneWidget);
      expect(find.textContaining('1 official notified'), findsOneWidget);
      await snap(tester, 'escalations_${size.width.toInt()}');

      await tester.tap(find.textContaining('Referrals ('));
      await tester.pumpAndSettle();
      expect(find.textContaining('sent to call Police'), findsOneWidget);
      expect(find.textContaining('sent to call LTO'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await snap(tester, 'referrals_${size.width.toInt()}');
    });
  }

  testWidgets('unanswered-report tiers are listed and counted apart from the slow ones', (tester) async {
    useSize(tester, const Size(1000, 900));
    await tester.pumpWidget(renderApp(EscalationsScreen(
      source: _FakeSource(escalationList: [
        _unanswered(3, 'Fire', 1, told: 7),
        _unanswered(2, 'Fire', 6),
        _unanswered(1, 'Noise Disturbance', 20, told: 2),
        _esc(1, 'Vandalism', 30),
      ]),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Nobody answered — 5 / 10 / 15 minutes'), findsOneWidget);
    expect(find.text('Taking too long — 24 / 48 / 72 hours'), findsOneWidget);
    expect(find.text('No response'), findsWidgets);
    expect(find.text('Whole barangay'), findsWidgets);
    expect(find.text('Last resort'), findsWidgets);
    // Same words as before for the hour-based one.
    expect(find.text('Reminder'), findsWidgets);
    expect(find.textContaining('7 officials notified'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await snap(tester, 'escalations_unanswered');
  });

  testWidgets('tapping an escalation opens that report', (tester) async {
    final pushed = <RouteSettings>[];
    useSize(tester, const Size(400, 760));
    await tester.pumpWidget(
        renderApp(EscalationsScreen(source: source), routeLog: pushed));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.textContaining('4 officials notified'));
    await tester.pumpAndSettle();

    expect(pushed.map((r) => r.name), contains('/incident-manage'));
    expect(pushed.last.arguments, 'incident-3');
  });

  testWidgets('an empty list says so instead of showing a blank page',
      (tester) async {
    useSize(tester, const Size(400, 760));
    await tester.pumpWidget(renderApp(EscalationsScreen(source: _FakeSource())));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Nothing escalated'), findsOneWidget);
    await tester.tap(find.textContaining('Referrals ('));
    await tester.pumpAndSettle();
    expect(find.text('No referrals yet'), findsOneWidget);
  });

  testWidgets('a failed load offers to try again', (tester) async {
    useSize(tester, const Size(400, 760));
    await tester.pumpWidget(
        renderApp(EscalationsScreen(source: _FakeSource(fail: true))));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Could not load'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // Let the error view's entrance animation finish before the test ends.
    await tester.pumpAndSettle();
  });
}
