import 'package:barangay_safety_app/models/incident_model.dart';
import 'package:barangay_safety_app/utils/helpers.dart';
import 'package:flutter_test/flutter_test.dart';

IncidentModel _incident(String status, DateTime createdAt,
        {DateTime? firstActionAt}) =>
    IncidentModel(
      id: 'i1',
      barangayId: 'b1',
      category: 'Noise Disturbance',
      description: 'x',
      severityLevel: 1,
      status: status,
      latitude: 13.94,
      longitude: 121.16,
      createdAt: createdAt,
      updatedAt: createdAt,
      firstActionAt: firstActionAt,
    );

void main() {
  final now = DateTime(2026, 10, 15, 12);

  String sla(String status, int hoursOld) =>
      slaStatus(_incident(status, now.subtract(Duration(hours: hoursOld))),
          now: now);

  // The cases below are the same ones the server checks when the escalation
  // migration runs (supabase/migration_2026_10_15_escalation.sql, section 5),
  // reduced to the two states the badge shows. If the app and the database ever
  // disagree about when a report is late, a supervisor gets an alert for a
  // report whose card says everything is fine.
  group('unanswered (pending, nobody has acted): 5 min warning, 15 min overdue', () {
    String slaMin(int minutes, {DateTime? firstAction}) => slaStatus(
          _incident('pending', now.subtract(Duration(minutes: minutes)),
              firstActionAt: firstAction),
          now: now,
        );

    test('boundaries', () {
      expect(slaMin(4), 'ok');
      expect(slaMin(5), 'warning');
      expect(slaMin(14), 'warning');
      expect(slaMin(15), 'overdue');
      expect(slaMin(60 * 300), 'overdue');
    });

    test('a shorter demo interval moves the lines with it', () {
      final created = now.subtract(const Duration(seconds: 35));
      expect(
        slaStatus(_incident('pending', created),
            now: now, step: const Duration(seconds: 30)),
        'warning',
      );
      expect(
        slaStatus(_incident('pending', created),
            now: now, step: const Duration(seconds: 10)),
        'overdue',
      );
    });

    test('answered by a message (still pending) uses the slow rule', () {
      expect(slaMin(30, firstAction: now), 'ok');
    });
  });

  group('being handled (incl. verified): 24h warning, 48h overdue', () {
    // Before 2026-10-15 only in_progress was checked. The other three are what
    // the six-stage flow actually writes, and all of them read 'ok' forever.
    for (final status in ['verified', 'assigned', 'in_progress', 'responding', 'on_scene']) {
      test(status, () {
        expect(sla(status, 23), 'ok');
        expect(sla(status, 24), 'warning');
        expect(sla(status, 47), 'warning');
        expect(sla(status, 48), 'overdue');
        expect(sla(status, 300), 'overdue');
      });
    }
  });

  group('finished or set aside is never late', () {
    for (final status in ['resolved', 'closed', 'flagged']) {
      test(status, () => expect(sla(status, 500), 'ok'));
    }
  });

  test('a report filed in the future is not late', () {
    expect(sla('pending', -5), 'ok');
  });
}
