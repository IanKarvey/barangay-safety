import 'package:barangay_safety_app/models/incident_model.dart';
import 'package:barangay_safety_app/models/user_model.dart';
import 'package:barangay_safety_app/utils/escalation_clock.dart';
import 'package:barangay_safety_app/utils/permissions.dart';
import 'package:barangay_safety_app/utils/stale_cases.dart';
import 'package:barangay_safety_app/widgets/volunteer_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/render.dart';

UserModel _user(String id, String position, {String role = 'admin'}) => UserModel(
      id: id,
      email: '$id@x.ph',
      fullName: id,
      phone: '0917',
      role: role,
      position: position,
      barangayId: 'b1',
      isVerified: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

final _t0 = DateTime(2026, 10, 20, 9);

IncidentModel _incident(
  String id, {
  String status = 'pending',
  String? assignedTo,
  DateTime? firstAction,
  DateTime? created,
  DateTime? updated,
}) =>
    IncidentModel(
      id: id,
      barangayId: 'b1',
      category: 'Vandalism',
      description: 'x',
      severityLevel: 2,
      status: status,
      latitude: 13.94,
      longitude: 121.16,
      createdAt: created ?? _t0,
      updatedAt: updated ?? created ?? _t0,
      assignedTo: assignedTo,
      firstActionAt: firstAction,
    );

void main() {
  setUpAll(loadRealFonts);

  final tanod = _user('tony', 'tanod');
  final staff = _user('frank', 'staff');
  final secretary = _user('sam', 'secretary');
  final captain = _user('cap', 'captain');

  final open = _incident('open'); // unassigned, pending
  final openVerified = _incident('verified', status: 'verified');
  final mine = _incident('mine', status: 'responding', assignedTo: 'tony');
  final others = _incident('others', status: 'responding', assignedTo: 'sam');
  final resolved = _incident('done', status: 'resolved', assignedTo: 'sam');
  final all = [open, openVerified, mine, others, resolved];

  group('who sees which reports', () {
    test('a tanod sees what is theirs AND what is open for volunteers', () {
      expect(visibleIncidents(tanod, all).map((i) => i.id), ['open', 'verified', 'mine']);
    });

    test('a tanod does not see another official\'s case or finished work', () {
      final ids = visibleIncidents(tanod, all).map((i) => i.id);
      expect(ids, isNot(contains('others')));
      expect(ids, isNot(contains('done')));
    });

    test('before this change a tanod saw an empty list; with nothing open and nothing assigned it is still empty', () {
      expect(visibleIncidents(tanod, [others, resolved]), isEmpty);
    });

    test('front-desk staff still see only what is assigned to them', () {
      expect(visibleIncidents(staff, all), isEmpty);
      expect(visibleIncidents(staff, [_incident('s', status: 'assigned', assignedTo: 'frank')]).length, 1);
    });

    test('secretary and captain see everything', () {
      expect(visibleIncidents(secretary, all), all);
      expect(visibleIncidents(captain, all), all);
    });

    test('opening a report follows the same rule', () {
      expect(canOpenIncident(tanod, open), isTrue);
      expect(canOpenIncident(tanod, openVerified), isTrue);
      expect(canOpenIncident(tanod, mine), isTrue);
      expect(canOpenIncident(tanod, others), isFalse);
      expect(canOpenIncident(tanod, resolved), isFalse);
      expect(canOpenIncident(staff, open), isFalse);
      expect(canOpenIncident(secretary, others), isTrue);
    });

    test('who may volunteer', () {
      expect(canVolunteer(tanod), isTrue);
      expect(canVolunteer(secretary), isTrue);
      expect(canVolunteer(captain), isTrue);
      expect(canVolunteer(staff), isFalse);
      expect(canVolunteer(null), isFalse);
      expect(canVolunteer(_user('r', 'tanod', role: 'resident')), isFalse);
    });

    test('the "is this case finished?" prompt never asks a tanod about reports that are not theirs', () {
      final old = _t0.subtract(const Duration(days: 3));
      final stale = StaleCases.forUser(tanod, [
        _incident('open-old', created: old, updated: old),
        _incident('mine-old', status: 'responding', assignedTo: 'tony', created: old, updated: old),
        _incident('others-old', status: 'responding', assignedTo: 'sam', created: old, updated: old),
      ]);
      expect(stale.map((i) => i.id), ['mine-old']);
    });
  });

  group('the first five minutes belong to the hall', () {
    Duration? lock(Duration waited, {bool tanod = true, bool untouched = true, Duration? step}) =>
        volunteerLockRemaining(
          tanod: tanod,
          untouched: untouched,
          waited: waited,
          step: step ?? kDefaultEscalationStep,
        );

    test('a tanod is held back, with the time left', () {
      expect(lock(Duration.zero), const Duration(minutes: 5));
      expect(lock(const Duration(minutes: 1, seconds: 18)), const Duration(minutes: 3, seconds: 42));
      expect(lock(const Duration(minutes: 4, seconds: 59)), const Duration(seconds: 1));
    });

    test('at 5 minutes it opens', () {
      expect(lock(const Duration(minutes: 5)), isNull);
      expect(lock(const Duration(minutes: 40)), isNull);
    });

    test('only a tanod is held back', () {
      expect(lock(Duration.zero, tanod: false), isNull);
    });

    test('once the hall has acted, the tanod does not wait', () {
      expect(lock(Duration.zero, untouched: false), isNull);
    });

    test('a 30-second demo interval shortens the lock', () {
      expect(lock(const Duration(seconds: 10), step: const Duration(seconds: 30)),
          const Duration(seconds: 20));
      expect(lock(const Duration(seconds: 30), step: const Duration(seconds: 30)), isNull);
    });
  });

  group('the volunteer button', () {
    Future<void> show(
      WidgetTester tester, {
      required UserModel user,
      required IncidentModel incident,
      required Duration waited,
      required VoidCallback onPressed,
      bool busy = false,
    }) async {
      useSize(tester, const Size(420, 300));
      await tester.pumpWidget(renderApp(
        Padding(
          padding: const EdgeInsets.all(16),
          child: VolunteerButton(
            incident: incident,
            user: user,
            busy: busy,
            now: () => _t0.add(waited),
            onPressed: onPressed,
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('grey with a countdown for a tanod in the first minutes; pressing does nothing', (tester) async {
      var pressed = 0;
      await show(tester,
          user: tanod, incident: open, waited: const Duration(minutes: 1, seconds: 18), onPressed: () => pressed++);
      expect(find.text("I'm responding — opens in 3:42"), findsOneWidget);
      expect(find.textContaining('barangay hall gets the first 5 minutes'), findsOneWidget);
      expect(find.byIcon(Icons.lock_clock_rounded), findsOneWidget);
      await snap(tester, 'volunteer_locked');

      await tester.tap(find.byType(VolunteerButton));
      await tester.pump();
      expect(pressed, 0);
      expect(find.textContaining('Not yet'), findsOneWidget);
    });

    testWidgets('red and pressable once 5 minutes have passed', (tester) async {
      var pressed = 0;
      await show(tester,
          user: tanod, incident: open, waited: const Duration(minutes: 5), onPressed: () => pressed++);
      expect(find.text("I'm responding"), findsOneWidget);
      expect(find.byIcon(Icons.directions_run_rounded), findsOneWidget);
      expect(find.byIcon(Icons.lock_clock_rounded), findsNothing);
      await snap(tester, 'volunteer_open');
      await tester.tap(find.byType(VolunteerButton));
      expect(pressed, 1);
    });

    testWidgets('a secretary is never held back', (tester) async {
      var pressed = 0;
      await show(tester, user: secretary, incident: open, waited: Duration.zero, onPressed: () => pressed++);
      expect(find.text("I'm responding"), findsOneWidget);
      await tester.tap(find.byType(VolunteerButton));
      expect(pressed, 1);
    });

    testWidgets('a tanod is not held back on a report the hall has already acted on', (tester) async {
      await show(tester,
          user: tanod,
          incident: _incident('v', status: 'verified', firstAction: _t0),
          waited: Duration.zero,
          onPressed: () {});
      expect(find.text("I'm responding"), findsOneWidget);
    });

    testWidgets('busy shows a spinner and ignores presses', (tester) async {
      var pressed = 0;
      await show(tester,
          user: secretary, incident: open, waited: Duration.zero, onPressed: () => pressed++, busy: true);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(VolunteerButton));
      expect(pressed, 0);
    });

    testWidgets('the countdown ticks down by itself and then turns red', (tester) async {
      var clock = _t0.add(const Duration(minutes: 4, seconds: 58));
      useSize(tester, const Size(420, 300));
      await tester.pumpWidget(renderApp(
        Padding(
          padding: const EdgeInsets.all(16),
          child: VolunteerButton(
            incident: open,
            user: tanod,
            now: () => clock,
            onPressed: () {},
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text("I'm responding — opens in 0:02"), findsOneWidget);

      clock = _t0.add(const Duration(minutes: 5, seconds: 1));
      await tester.pump(const Duration(seconds: 1)); // the button's own one-second tick
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text("I'm responding"), findsOneWidget);
    });
  });
}
