import 'package:barangay_safety_app/services/emergency_contacts_service.dart';
import 'package:barangay_safety_app/utils/escalation_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('traffic-light colour (green <5, yellow 5-10, orange 10-15, red 15+)', () {
    WaitBand at(int minutes, [int seconds = 0]) =>
        waitBandFor(Duration(minutes: minutes, seconds: seconds));

    test('boundaries', () {
      expect(at(0), WaitBand.green);
      expect(at(4, 59), WaitBand.green);
      expect(at(5), WaitBand.yellow);
      expect(at(9, 59), WaitBand.yellow);
      expect(at(10), WaitBand.orange);
      expect(at(14, 59), WaitBand.orange);
      expect(at(15), WaitBand.red);
      expect(at(600), WaitBand.red);
    });

    test('a 30-second demo interval moves every line with it', () {
      const step = Duration(seconds: 30);
      expect(waitBandFor(const Duration(seconds: 29), step: step), WaitBand.green);
      expect(waitBandFor(const Duration(seconds: 30), step: step), WaitBand.yellow);
      expect(waitBandFor(const Duration(seconds: 60), step: step), WaitBand.orange);
      expect(waitBandFor(const Duration(seconds: 90), step: step), WaitBand.red);
    });
  });

  group('tier a report should be in (mirrors the database)', () {
    test('0 until the first step, then 1, 2, 3 and never more', () {
      expect(escalationLevelFor(const Duration(minutes: 4, seconds: 59)), 0);
      expect(escalationLevelFor(const Duration(minutes: 5)), 1);
      expect(escalationLevelFor(const Duration(minutes: 10)), 2);
      expect(escalationLevelFor(const Duration(minutes: 15)), 3);
      expect(escalationLevelFor(const Duration(hours: 5)), 3);
    });

    test('negative time or a broken step is level 0, not a crash', () {
      expect(escalationLevelFor(const Duration(minutes: -3)), 0);
      expect(escalationLevelFor(const Duration(minutes: 9), step: Duration.zero), 0);
    });
  });

  group('countdown to the next update', () {
    test('counts down inside a step', () {
      expect(untilNextTier(Duration.zero), const Duration(minutes: 5));
      expect(untilNextTier(const Duration(minutes: 1, seconds: 18)),
          const Duration(minutes: 3, seconds: 42));
      expect(untilNextTier(const Duration(minutes: 5)), const Duration(minutes: 5));
      expect(untilNextTier(const Duration(minutes: 14, seconds: 59)),
          const Duration(seconds: 1));
    });

    test('there is no next update after the last tier', () {
      expect(untilNextTier(const Duration(minutes: 15)), isNull);
      expect(untilNextTier(const Duration(hours: 2)), isNull);
    });
  });

  group('clock text', () {
    test('minutes:seconds, then hours', () {
      expect(formatClock(Duration.zero), '0:00');
      expect(formatClock(const Duration(minutes: 3, seconds: 42)), '3:42');
      expect(formatClock(const Duration(minutes: 12, seconds: 5)), '12:05');
      expect(formatClock(const Duration(hours: 1, minutes: 2, seconds: 9)), '1:02:09');
    });

    test('never shows a negative time', () {
      expect(formatClock(const Duration(seconds: -4)), '0:00');
    });
  });

  group('waited by the SERVER clock', () {
    final submitted = DateTime(2026, 10, 20, 9, 0, 0);

    test('a phone running 3 minutes slow is corrected by the offset', () {
      // Server says 09:05:00; this phone thinks it is 09:02:00.
      final waited = waitedSince(
        submitted,
        serverOffset: const Duration(minutes: 3),
        deviceNow: DateTime(2026, 10, 20, 9, 2, 0),
      );
      expect(waited, const Duration(minutes: 5));
    });

    test('a phone running fast cannot show a wait that has not happened', () {
      final waited = waitedSince(
        submitted,
        deviceNow: DateTime(2026, 10, 20, 8, 59, 50),
      );
      expect(waited, Duration.zero);
    });
  });

  group('which emergency numbers a resident sees', () {
    EmergencyContact c(String id, String? barangay, String phone,
            {bool active = true, int order = 0}) =>
        EmergencyContact(
          id: id,
          barangayId: barangay,
          label: id,
          category: 'police',
          phoneNumber: phone,
          isActive: active,
          sortOrder: order,
        );

    test('the barangay\'s own numbers win, in the order set', () {
      final out = resolveEmergencyNumbers(
        barangay: [c('b2', 'b1', '222', order: 2), c('b1', 'b1', '111', order: 1)],
        city: [c('city', null, '999')],
      );
      expect(out.map((e) => e.id), ['b1', 'b2']);
    });

    test('inactive and blank numbers are skipped', () {
      final out = resolveEmergencyNumbers(
        barangay: [c('off', 'b1', '111', active: false), c('blank', 'b1', '  ')],
        city: [c('city', null, '999')],
      );
      expect(out.single.id, 'city');
    });

    test('no barangay numbers -> the city\'s', () {
      final out = resolveEmergencyNumbers(
        barangay: const [],
        city: [c('city1', null, '999'), c('city2', null, '998', order: 1)],
      );
      expect(out.map((e) => e.id), ['city1', 'city2']);
    });

    test('nothing saved anywhere -> the built-in Lipa City set, never an empty list', () {
      final out = resolveEmergencyNumbers(barangay: const [], city: const []);
      expect(out, kBuiltInEmergencyNumbers);
      expect(isBuiltInSet(out), isTrue);
    });

    test('the built-in set has police, ambulance and rescue first, then fire and 911', () {
      final labels = kBuiltInEmergencyNumbers.map((c) => c.label).toList();
      expect(labels, [
        'Police (PNP Lipa)',
        'Ambulance (CDRRMO)',
        'Rescue (CDRRMO Lipa)',
        'Fire (BFP Lipa)',
        'National Emergency (911)',
      ]);
      // The numbers are the ones already used by the "call this agency" pop-up.
      final dial = {for (final c in kBuiltInEmergencyNumbers) c.label: c.dial};
      expect(dial['Police (PNP Lipa)'], '+639000000001');
      expect(dial['Ambulance (CDRRMO)'], '+639000000002');
      expect(dial['Rescue (CDRRMO Lipa)'], '+63437560217');
      expect(dial['Fire (BFP Lipa)'], '+63437574168');
      expect(dial['National Emergency (911)'], '911');
      // Every one is dialable as stored.
      for (final c in kBuiltInEmergencyNumbers) {
        expect(c.dial, isNotEmpty, reason: c.label);
      }
    });

    test('numbers someone saved are never mistaken for the built-in set', () {
      final saved = [c('1', 'b1', '111')];
      expect(isBuiltInSet(resolveEmergencyNumbers(barangay: saved, city: const [])), isFalse);
    });

    test('a number typed with spaces and dashes still dials', () {
      expect(c('x', null, '(043) 757-4168').dial, '0437574168');
      expect(c('y', null, '+63 900 000 0001').dial, '+639000000001');
    });
  });
}
