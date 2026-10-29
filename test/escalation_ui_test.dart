import 'dart:async';

import 'package:barangay_safety_app/l10n/app_strings.dart';
import 'package:barangay_safety_app/l10n/response_strings.dart';
import 'package:barangay_safety_app/models/incident_model.dart';
import 'package:barangay_safety_app/models/notification_model.dart';
import 'package:barangay_safety_app/models/user_model.dart';
import 'package:barangay_safety_app/providers/auth_provider.dart';
import 'package:barangay_safety_app/providers/notification_provider.dart';
import 'package:barangay_safety_app/services/emergency_contacts_service.dart';
import 'package:barangay_safety_app/services/server_clock.dart';
import 'package:barangay_safety_app/utils/alert_sound.dart';
import 'package:barangay_safety_app/utils/theme.dart';
import 'package:barangay_safety_app/widgets/alert_host.dart';
import 'package:barangay_safety_app/widgets/emergency_numbers_sheet.dart';
import 'package:barangay_safety_app/widgets/waiting_for_response_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/render.dart';

final _submitted = DateTime(2026, 10, 20, 9, 0, 0);

IncidentModel _incident({int level = 0, String status = 'pending', DateTime? firstAction}) =>
    IncidentModel(
      id: '00000000-0000-4000-8000-0000000000a1',
      barangayId: 'b1',
      category: 'Fire',
      description: 'smoke',
      severityLevel: 4,
      status: status,
      latitude: 13.94,
      longitude: 121.16,
      createdAt: _submitted,
      updatedAt: _submitted,
      escalationLevel: level,
      firstActionAt: firstAction,
    );

class _FakeNotifs extends ChangeNotifier implements NotificationProvider {
  final ctrl = StreamController<NotificationModel>.broadcast();
  @override
  Stream<NotificationModel> get arrivals => ctrl.stream;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeAuth extends ChangeNotifier implements AuthProvider {
  @override
  UserModel? get user => UserModel(
        id: 'u1',
        email: 'r@x.ph',
        fullName: 'Rita',
        phone: '0917',
        role: 'resident',
        barangayId: 'b1',
        isVerified: true,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

NotificationModel _notif(String type, {Map<String, dynamic>? data, String body = 'body text'}) =>
    NotificationModel(
      id: 'n-$type-${data?['level']}',
      userId: 'u1',
      title: 'title',
      body: body,
      type: type,
      incidentId: '00000000-0000-4000-8000-0000000000a1',
      isRead: false,
      createdAt: DateTime.now(),
      data: data,
    );

void main() {
  setUpAll(loadRealFonts);
  setUp(ServerClock.reset);

  group('messages are exactly the ones in the brief', () {
    const en = ResponseStrings(AppLanguage.english);
    const tl = ResponseStrings(AppLanguage.tagalog);

    test('English', () {
      expect(en.escalationMessage(1),
          "We're sorry, it looks like our barangay officials are currently busy. Please wait another 5 minutes.");
      expect(en.escalationMessage(2),
          "We're sorry for the inconvenience. We are now notifying the whole barangay so someone can take action quickly.");
      expect(en.escalationMessage(3),
          'It seems our barangay is busy right now. Please call these numbers for immediate help:');
      expect(en.goodNews('Tanod', 'Juan Cruz'),
          'Good news! Tanod Juan Cruz is now responding to your report.');
    });

    test('Filipino', () {
      expect(tl.escalationMessage(1),
          'Pasensya na po, mukhang abala pa ang aming mga barangay official. Mangyaring maghintay ng 5 minuto pa.');
      expect(tl.escalationMessage(2),
          'Paumanhin po sa abala. Inaabisuhan na namin ang buong barangay para may agad na tumugon.');
      expect(tl.escalationMessage(3),
          'Mukhang abala ang buong barangay ngayon. Mangyaring tumawag agad sa mga numerong ito:');
      expect(tl.goodNews('Tanod', 'Juan Cruz'),
          'Magandang balita po! May tumutugon na sa inyong report: Tanod Juan Cruz.');
    });

    test('the tutorial has the same number of steps in both languages', () {
      for (var i = 0; i < ResponseStrings.tutorialStepCount; i++) {
        expect(en.stepTitle(i), isNot(tl.stepTitle(i)));
        expect(en.stepText(i).isNotEmpty && tl.stepText(i).isNotEmpty, isTrue);
      }
    });
  });

  group('waiting card (resident)', () {
    Future<void> show(WidgetTester tester, IncidentModel i, Duration waited,
        {VoidCallback? onCall}) async {
      useSize(tester, const Size(420, 700));
      await tester.pumpWidget(renderApp(
        SingleChildScrollView(
          child: WaitingForResponseCard(
            incident: i,
            now: () => _submitted.add(waited),
            onCallForHelp: onCall,
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('first minute: waiting + countdown, no apology, no call button', (tester) async {
      await show(tester, _incident(), const Duration(minutes: 1, seconds: 18));
      expect(find.text('Report sent. Waiting for barangay response.'), findsOneWidget);
      expect(find.text('Next update in 3:42'), findsOneWidget);
      expect(find.text('Waiting 1:18'), findsOneWidget);
      expect(find.text('Call for help now'), findsNothing);
      expect(find.textContaining("We're sorry"), findsNothing);
      expect(tester.takeException(), isNull);
      await snap(tester, 'waiting_0118');
    });

    testWidgets('tier 1 shows message 1', (tester) async {
      await show(tester, _incident(level: 1), const Duration(minutes: 6));
      expect(find.textContaining('wait another 5 minutes'), findsOneWidget);
      expect(find.text('Call for help now'), findsNothing);
      await snap(tester, 'waiting_tier1');
    });

    testWidgets('tier 2 shows message 2', (tester) async {
      await show(tester, _incident(level: 2), const Duration(minutes: 11));
      expect(find.textContaining('notifying the whole barangay'), findsOneWidget);
      await snap(tester, 'waiting_tier2');
    });

    testWidgets('tier 3 shows the call button and it works', (tester) async {
      var called = 0;
      await show(tester, _incident(level: 3), const Duration(minutes: 16),
          onCall: () => called++);
      expect(find.text('Call for help now'), findsOneWidget);
      expect(find.text('Next update in', skipOffstage: false), findsNothing);
      await tester.tap(find.text('Call for help now'));
      expect(called, 1);
      expect(tester.takeException(), isNull);
      await snap(tester, 'waiting_tier3');
    });

    testWidgets('a phone that has not heard from the server yet still escalates by its clock', (tester) async {
      // escalationLevel is still 0 from the database, but 16 minutes have passed.
      await show(tester, _incident(level: 0), const Duration(minutes: 16));
      expect(find.text('Call for help now'), findsOneWidget);
    });
  });

  group('emergency numbers pop-up', () {
    testWidgets('lists every number as a big tap target', (tester) async {
      useSize(tester, const Size(420, 800));
      await tester.pumpWidget(renderApp(
        EmergencyNumbersDialog(
          barangayId: 'b1',
          service: EmergencyContactsService(),
          contacts: const [
            EmergencyContact(
                id: '1', barangayId: 'b1', label: 'Lipa Police', category: 'police', phoneNumber: '+639000000001'),
            EmergencyContact(
                id: '2', barangayId: 'b1', label: 'Barangay Clinic', category: 'hospital', phoneNumber: '(043) 757 0000'),
          ],
        ),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Lipa Police'), findsOneWidget);
      expect(find.text('+639000000001'), findsOneWidget);
      expect(find.text('Barangay Clinic'), findsOneWidget);
      expect(find.textContaining('Please call these numbers'), findsOneWidget);
      // Every call button is at least 56 dp tall.
      for (final label in ['Lipa Police', 'Barangay Clinic']) {
        final box = tester.getRect(find.ancestor(
          of: find.text(label),
          matching: find.byType(InkWell),
        ).first);
        expect(box.height, greaterThanOrEqualTo(56));
      }
      expect(tester.takeException(), isNull);
      await snap(tester, 'emergency_numbers');
    });

    testWidgets('with nothing saved, the standard Lipa City numbers show — not just 911', (tester) async {
      useSize(tester, const Size(420, 900));
      await tester.pumpWidget(renderApp(
        EmergencyNumbersDialog(
          barangayId: 'b1',
          service: EmergencyContactsService(),
          contacts: kBuiltInEmergencyNumbers,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      for (final label in [
        'Police (PNP Lipa)',
        'Ambulance (CDRRMO)',
        'Rescue (CDRRMO Lipa)',
        'Fire (BFP Lipa)',
        'National Emergency (911)',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // Written the way people read numbers, but dialled in full.
      expect(find.text('+63 900 000 0002'), findsOneWidget);
      expect(find.text('(043) 757 4168'), findsOneWidget);
      expect(find.textContaining('standard Lipa City emergency numbers'), findsOneWidget);
      // The old "SOS" badge is gone.
      expect(find.byIcon(Icons.sos_rounded), findsNothing);
      expect(tester.takeException(), isNull);
      await snap(tester, 'emergency_numbers_builtin');
    });

    testWidgets('numbers an admin saved do not carry the "standard numbers" note', (tester) async {
      useSize(tester, const Size(420, 800));
      await tester.pumpWidget(renderApp(
        EmergencyNumbersDialog(
          barangayId: 'b1',
          service: EmergencyContactsService(),
          contacts: const [
            EmergencyContact(id: 'x', barangayId: 'b1', label: 'Brgy Hall', category: 'other', phoneNumber: '(043) 111 2222'),
          ],
        ),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('standard Lipa City'), findsNothing);
    });
  });

  group('pop-ups that arrive while the app is open', () {
    final navKey = GlobalKey<NavigatorState>();

    Future<_FakeNotifs> mount(WidgetTester tester) async {
      useSize(tester, const Size(420, 800));
      final notifs = _FakeNotifs();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<NotificationProvider>.value(value: notifs),
          ChangeNotifierProvider<AuthProvider>(create: (_) => _FakeAuth()),
        ],
        child: AppStringsScope(
          language: AppLanguage.english,
          strings: AppStrings.en,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            navigatorKey: navKey,
            builder: (context, child) =>
                AlertHost(navigatorKey: navKey, child: child!),
            home: const Scaffold(body: Text('HOME')),
          ),
        ),
      ));
      await tester.pump();
      return notifs;
    }

    testWidgets('an official gets a pop-up that stays until dismissed, with sound', (tester) async {
      final notifs = await mount(tester);
      notifs.ctrl.add(_notif('escalation',
          data: {'kind': 'unanswered', 'level': 1},
          body: 'Fire in Barangay 3 has had no response for 5 min.'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Unanswered report'), findsOneWidget);
      expect(find.textContaining('no response for 5 min'), findsOneWidget);
      expect(AlertSound.isPlaying, isTrue);

      // Tapping outside does not close it.
      await tester.tapAt(const Offset(5, 5));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Unanswered report'), findsOneWidget);

      await tester.tap(find.text('Dismiss'));
      await tester.pump(); // starts the exit animation
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Unanswered report'), findsNothing);
      expect(AlertSound.isPlaying, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an official\'s old-style hour notification is NOT a pop-up', (tester) async {
      final notifs = await mount(tester);
      notifs.ctrl.add(_notif('escalation', data: null));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(OfficialAlertDialog), findsNothing);
    });

    testWidgets('two alerts queue up, one at a time', (tester) async {
      final notifs = await mount(tester);
      notifs.ctrl.add(_notif('escalation', data: {'kind': 'unanswered', 'level': 1}, body: 'first'));
      notifs.ctrl.add(_notif('escalation', data: {'kind': 'unanswered', 'level': 3}, body: 'second'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('first'), findsOneWidget);
      expect(find.text('second'), findsNothing);
      await tester.tap(find.text('Dismiss'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('second'), findsOneWidget);
      expect(find.text('UNATTENDED — last resort'), findsOneWidget);
      await tester.tap(find.text('Dismiss'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(AlertSound.isPlaying, isFalse);
    });

    testWidgets('a resident gets message 1 and message 2', (tester) async {
      final notifs = await mount(tester);
      notifs.ctrl.add(_notif('escalation_resident', data: {'level': 1}));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('wait another 5 minutes'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pump(const Duration(milliseconds: 400));

      notifs.ctrl.add(_notif('escalation_resident', data: {'level': 2}));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('notifying the whole barangay'), findsOneWidget);
    });

    testWidgets('a resident at the last tier gets the emergency numbers', (tester) async {
      final notifs = await mount(tester);
      notifs.ctrl.add(_notif('escalation_resident', data: {'level': 3}));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(EmergencyNumbersDialog), findsOneWidget);
      expect(find.textContaining('Please call these numbers'), findsOneWidget);
      // With no database reachable (as here, and as on a phone with no signal)
      // the resident still gets police, ambulance and rescue, not only 911.
      expect(find.text('Police (PNP Lipa)'), findsOneWidget);
      expect(find.text('Ambulance (CDRRMO)'), findsOneWidget);
      expect(find.text('Rescue (CDRRMO Lipa)'), findsOneWidget);
    });

    testWidgets('a "still waiting" reminder does not re-open the numbers pop-up every five minutes', (tester) async {
      final notifs = await mount(tester);
      notifs.ctrl.add(_notif('escalation_resident', data: {'level': 3, 'reminder': 2}));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(EmergencyNumbersDialog), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('but an official still gets the pop-up for each reminder', (tester) async {
      final notifs = await mount(tester);
      notifs.ctrl.add(_notif('escalation',
          data: {'kind': 'unanswered', 'level': 3, 'reminder': 2},
          body: 'Fire in Barangay 3 still has NO response after 25 min.'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('still has NO response after 25 min'), findsOneWidget);
      await tester.tap(find.text('Dismiss'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('"report taken" is a notification, not a pop-up', (tester) async {
      final notifs = await mount(tester);
      notifs.ctrl.add(_notif('responder_taken', data: {'role': 'tanod', 'name': 'Tony'}));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('good news names the role and the person', (tester) async {
      final notifs = await mount(tester);
      notifs.ctrl.add(_notif('responder_update',
          data: {'role': 'captain', 'name': 'Maria Santos'}));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Help is on the way'), findsOneWidget);
      expect(find.text('Good news! Barangay Captain Maria Santos is now responding to your report.'),
          findsOneWidget);
    });

    testWidgets('old notifications loaded late are not shown as news', (tester) async {
      final notifs = await mount(tester);
      notifs.ctrl.add(NotificationModel(
        id: 'old',
        userId: 'u1',
        title: 't',
        body: 'ancient',
        type: 'escalation',
        incidentId: 'x',
        isRead: false,
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
        data: const {'kind': 'unanswered', 'level': 2},
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('ancient'), findsNothing);
    });
  });
}
