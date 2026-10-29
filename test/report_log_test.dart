import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:barangay_safety_app/models/incident_model.dart';
import 'package:barangay_safety_app/utils/analytics_report.dart';
import 'package:barangay_safety_app/utils/manila_time.dart';
import 'package:barangay_safety_app/utils/report_document.dart';
import 'package:barangay_safety_app/utils/report_log.dart';
import 'package:barangay_safety_app/widgets/report_log_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/render.dart';

// 09:00 Philippine time on 19 Oct 2026 = 01:00 UTC.
final _t0 = DateTime.utc(2026, 10, 19, 1);
final _now = _t0.add(const Duration(hours: 3, minutes: 20));

IncidentModel _incident(
  String id, {
  String category = 'Vandalism',
  int severity = 2,
  String status = 'pending',
  String? reporter = 'Rita Resident',
  String? responder,
  String description = 'Batang hamog defacing the DayCare center',
  String? sessionId,
  DateTime? created,
  DateTime? firstAction,
  DateTime? verified,
  DateTime? assigned,
  DateTime? responding,
  DateTime? onScene,
  DateTime? resolved,
  DateTime? closed,
}) {
  final c = created ?? _t0;
  return IncidentModel(
    id: id,
    reporterName: reporter,
    barangayId: 'b1',
    barangayName: 'Barangay 1',
    category: category,
    description: description,
    severityLevel: severity,
    status: status,
    latitude: 13.94,
    longitude: 121.16,
    address: '123 Secret Street',
    reporterPhone: '09171234567',
    assignedToName: responder,
    reportedBySessionId: sessionId,
    createdAt: c,
    updatedAt: c,
    firstActionAt: firstAction,
    verifiedAt: verified,
    assignedAt: assigned,
    respondingAt: responding,
    onSceneAt: onScene,
    resolvedAt: resolved,
    closedAt: closed,
  );
}

void main() {
  setUpAll(loadRealFonts);

  group('how long things took', () {
    test('humanDuration reads like a person would say it', () {
      expect(humanDuration(const Duration(seconds: 45)), '45 s');
      expect(humanDuration(const Duration(minutes: 12)), '12 min');
      expect(humanDuration(const Duration(hours: 2, minutes: 14)), '2 h 14 min');
      expect(humanDuration(const Duration(hours: 3)), '3 h');
      expect(humanDuration(const Duration(days: 3, hours: 4, minutes: 9)), '3 d 4 h');
      expect(humanDuration(const Duration(days: 2)), '2 d');
      expect(humanDuration(const Duration(seconds: -5)), '0 s');
    });

    final finished = _incident(
      'aaaaaaaa-1111',
      status: 'resolved',
      responder: 'Tony Tanod',
      verified: _t0.add(const Duration(minutes: 3)),
      responding: _t0.add(const Duration(minutes: 10)),
      onScene: _t0.add(const Duration(minutes: 40)),
      resolved: _t0.add(const Duration(hours: 2, minutes: 14)),
    );

    test('a finished report: reported, first response, finished, and the time it took', () {
      final e = buildReportLog([finished], now: _now).single;
      expect(e.timeToFirstResponse, const Duration(minutes: 3));
      expect(e.timeToFinish, const Duration(hours: 2, minutes: 14));
      expect(e.outcome, 'Finished in 2 h 14 min');
      expect(e.isFinished, isTrue);
      expect(e.isOpen, isFalse);
      expect(e.openFor, isNull);
      expect(e.responderName, 'Tony Tanod');
      expect(e.shortId, 'AAAAAAAA');
    });

    test('a report still waiting says how long it has been waiting', () {
      final e = buildReportLog([_incident('bbbbbbbb-2222')], now: _now).single;
      expect(e.isOpen, isTrue);
      expect(e.timeToFinish, isNull);
      expect(e.openFor, const Duration(hours: 3, minutes: 20));
      expect(e.outcome, 'Still open - waiting 3 h 20 min');
    });

    test('a flagged report is set aside, not "open" and not "finished"', () {
      final e = buildReportLog([_incident('cccccccc-3333', status: 'flagged')], now: _now).single;
      expect(e.isOpen, isFalse);
      expect(e.isFinished, isFalse);
      expect(e.outcome, 'Set aside (flagged)');
    });

    test('a closed report counts as finished using its closing time', () {
      final e = buildReportLog([
        _incident('dddddddd-4444', status: 'closed', closed: _t0.add(const Duration(minutes: 90))),
      ], now: _now).single;
      expect(e.timeToFinish, const Duration(minutes: 90));
    });

    test('resolved with no finish time on record is NOT given an invented one', () {
      final e = buildReportLog([_incident('eeeeeeee-5555', status: 'resolved')], now: _now).single;
      expect(e.timeToFinish, isNull);
      expect(e.outcome, 'Finished (time not recorded)');
      expect(e.isOpen, isFalse);
    });

    test('first response prefers the recorded first action, else the earliest real stamp', () {
      final recorded = buildReportLog([
        _incident('x1', firstAction: _t0.add(const Duration(minutes: 1)), verified: _t0.add(const Duration(minutes: 9))),
      ], now: _now).single;
      expect(recorded.timeToFirstResponse, const Duration(minutes: 1));

      final derived = buildReportLog([
        _incident('x2', verified: _t0.add(const Duration(minutes: 9)), responding: _t0.add(const Duration(minutes: 4))),
      ], now: _now).single;
      expect(derived.timeToFirstResponse, const Duration(minutes: 4));

      final none = buildReportLog([_incident('x3')], now: _now).single;
      expect(none.timeToFirstResponse, isNull);
    });

    test('newest report first', () {
      final log = buildReportLog([
        _incident('old', created: _t0),
        _incident('new', created: _t0.add(const Duration(hours: 1))),
        _incident('mid', created: _t0.add(const Duration(minutes: 30))),
      ], now: _now);
      expect(log.map((e) => e.id), ['new', 'mid', 'old']);
    });
  });

  group('who reported it', () {
    test('a resident is shown by name', () {
      expect(reporterNameFor(_incident('a')), 'Rita Resident');
    });

    test('a walk-in is read back from the report sentence — the name only', () {
      final i = _incident(
        'w',
        reporter: null,
        sessionId: 'session-1',
        description:
            'Andrei reported an emergency via the non-resident flow. Contact: 09000000004',
      );
      expect(reporterNameFor(i), 'Andrei (walk-in)');
      expect(reporterNameFor(i).contains('0994'), isFalse);
    });

    test('a walk-in whose sentence cannot be read is a plain visitor, never a number', () {
      expect(
        reporterNameFor(_incident('w2', reporter: null, sessionId: 's', description: 'something else')),
        'Walk-in visitor',
      );
      expect(
        reporterNameFor(_incident('w3',
            reporter: null,
            sessionId: 's',
            description: '09000000004 reported an emergency via the non-resident flow. Contact: x')),
        'Walk-in visitor',
      );
    });

    test('no name and not a walk-in is "Unknown", not blank', () {
      expect(reporterNameFor(_incident('u', reporter: null)), 'Unknown');
    });
  });

  group('per responder', () {
    test('counts what each person took, finished and still holds, and how long they took', () {
      final log = buildReportLog([
        _incident('r1', status: 'resolved', responder: 'Tony', resolved: _t0.add(const Duration(minutes: 30))),
        _incident('r2', status: 'resolved', responder: 'Tony', resolved: _t0.add(const Duration(minutes: 90))),
        _incident('r3', status: 'responding', responder: 'Tony'),
        _incident('r4', status: 'resolved', responder: 'Cap', resolved: _t0.add(const Duration(minutes: 10))),
        _incident('r5'), // nobody
      ], now: _now);
      final stats = ReportLogStats.from(log);
      expect(stats.total, 5);
      expect(stats.finished, 3);
      expect(stats.open, 2);
      final tony = stats.byResponder.first;
      expect(tony.name, 'Tony'); // took the most
      expect(tony.taken, 3);
      expect(tony.finished, 2);
      expect(tony.stillOpen, 1);
      expect(tony.timeToFinish.average, 3600); // (30 + 90) min / 2
      expect(tony.timeToFinish.min, 1800);
      expect(tony.timeToFinish.max, 5400);
      expect(stats.fastest!.id, 'r4');
      expect(stats.slowest!.id, 'r2');
    });
  });

  group('the report list in Excel and Word', () {
    final incidents = [
      _incident('aaaaaaaa-1111',
          status: 'resolved',
          responder: 'Tony Tanod',
          category: 'Fire',
          severity: 4,
          verified: _t0.add(const Duration(minutes: 3)),
          resolved: _t0.add(const Duration(hours: 2, minutes: 14))),
      _incident('bbbbbbbb-2222',
          reporter: null,
          sessionId: 's1',
          category: 'Emergency (Non-Resident)',
          severity: 1,
          created: _t0.add(const Duration(minutes: 20)),
          description: 'Andrei reported an emergency via the non-resident flow. Contact: 09000000004'),
      _incident('cccccccc-3333', status: 'flagged', reporter: 'Maria Cruz', created: _t0.add(const Duration(minutes: 40))),
    ];
    final log = buildReportLog(incidents, now: _now, isOverdue: (i) => i.id.startsWith('bbbb'));

    final report = buildAnalyticsReport(
      appName: 'Barangay Safety',
      barangayName: 'Barangay 1',
      periodLabel: 'All time',
      generatedAt: _now,
      today: _now,
      total: 3,
      nonResident: 1,
      pending: 1,
      inProgress: 0,
      resolved: 1,
      flagged: 1,
      overdue: 1,
      resolutionRate: 33.3,
      avgResolutionHours: 2.2,
      slaCompliance: 100,
      categories: const [MapEntry('Fire', 1)],
      last7Days: const [0, 0, 0, 0, 0, 0, 3],
      log: log,
    );

    ReportSection section(String name) => report.sections.firstWhere((s) => s.heading == name);

    test('there is one row for EVERY report, with who, when and how long', () {
      final rows = section('All Reports').rows;
      expect(rows.length, 3);
      final headers = section('All Reports').headers;
      int col(String h) => headers.indexOf(h);

      // newest first: Maria (09:40), Andrei (09:20), Rita's fire (09:00)
      expect(rows[0][col('Reported by')], 'Maria Cruz');
      expect(rows[1][col('Reported by')], 'Andrei (walk-in)');
      expect(rows[1][col('Reporter type')], 'Walk-in');
      expect(rows[2][col('Reported by')], 'Rita Resident');
      expect(rows[2][col('Reported (Philippine time)')], '2026-10-19 09:00:00');
      expect(rows[2][col('Responder')], 'Tony Tanod');
      expect(rows[2][col('Time to first response')], '3 min');
      expect(rows[2][col('Finished at')], '2026-10-19 11:14:00');
      expect(rows[2][col('Time to finish')], '2 h 14 min');
      expect(rows[2][col('Minutes to finish')], 134.0);
      expect(rows[1][col('Outcome')], 'Still open - waiting 3 h');
      expect(rows[1][col('Overdue')], 'Yes');
      expect(rows[0][col('Outcome')], 'Set aside (flagged)');
    });

    test('the summary gains response-time lines and a per-responder table', () {
      final perf = {for (final r in section('Response Performance').rows) r[0]: r[1]};
      expect(perf['Average time to first response'], '3 min');
      expect(perf['Average time to finish'], '2 h 14 min');
      expect(perf['Fastest finish'], contains('Fire'));
      final resp = section('Reports by Responder').rows;
      expect(resp.single[0], 'Tony Tanod');
      expect(resp.single[1], 1);
    });

    test('Excel: an "All Reports" sheet with every column, minutes as real numbers', () {
      final zip = ZipDecoder().decodeBytes(report.toXlsx());
      final book = utf8.decode(zip.findFile('xl/workbook.xml')!.content as List<int>);
      final names = RegExp(r'<sheet name="([^"]+)"').allMatches(book).map((m) => m.group(1)).toList();
      expect(names, contains('All Reports'));
      expect(names, contains('Reports by Responder'));
      final idx = names.indexOf('All Reports') + 1;
      final sheet = utf8.decode(zip.findFile('xl/worksheets/sheet$idx.xml')!.content as List<int>);
      expect(sheet, contains('Rita Resident'));
      expect(sheet, contains('Andrei (walk-in)'));
      expect(sheet, contains('<v>134.0</v>'));
      expect(RegExp('<row ').allMatches(sheet).length, greaterThanOrEqualTo(4)); // header + 3 (+ note)
    });

    test('Word: landscape, with the nine columns a page can hold', () {
      final zip = ZipDecoder().decodeBytes(report.toDocx());
      final doc = utf8.decode(zip.findFile('word/document.xml')!.content as List<int>);
      expect(doc, contains('w:orient="landscape"'));
      for (final h in ['Reported by', 'Reported (Philippine time)', 'Responder', 'Time to first response', 'Outcome']) {
        expect(doc, contains('>$h<'), reason: h);
      }
      // The columns left to Excel are not crammed into the page.
      expect(doc, isNot(contains('>Dispatched at<')));
      expect(doc, contains('Finished in 2 h 14 min'));
      expect(doc, contains('Maria Cruz'));
      expect(doc, contains('Reports listed: 3'));
    });

    test('PRIVACY: no phone number, address, coordinates or description anywhere in either file', () {
      final xlsx = ZipDecoder().decodeBytes(report.toXlsx());
      final docx = ZipDecoder().decodeBytes(report.toDocx());
      final everything = [
        for (final f in [...xlsx.files, ...docx.files])
          if (f.isFile) utf8.decode(f.content as List<int>, allowMalformed: true),
      ].join('\n');
      expect(everything.contains('09000000004'), isFalse, reason: "a walk-in's phone");
      expect(everything.contains('09171234567'), isFalse, reason: "a resident's phone");
      expect(everything.contains('Secret Street'), isFalse, reason: 'an address');
      expect(everything.contains('13.94'), isFalse, reason: 'coordinates');
      expect(everything.contains('Contact:'), isFalse, reason: 'the description a walk-in typed');
      expect(everything.contains('DayCare'), isFalse, reason: 'report descriptions');
    });

    test('writes real files for an outside reader to open', () {
      final dir = Platform.environment['XLSX_OUT'];
      if (dir == null) return;
      File('$dir/analytics_detailed.xlsx').writeAsBytesSync(report.toXlsx());
      File('$dir/analytics_detailed.docx').writeAsBytesSync(report.toDocx());
    });
  });

  group('friendly Philippine time', () {
    test('reads the way a person says it', () {
      expect(formatManilaFriendly(DateTime.utc(2026, 10, 19, 1, 38)), 'Oct 19, 2026 · 9:38 AM');
      expect(formatManilaFriendly(DateTime.utc(2026, 10, 19, 4, 5)), 'Oct 19, 2026 · 12:05 PM');
      expect(formatManilaFriendly(DateTime.utc(2026, 10, 18, 16, 0)), 'Oct 19, 2026 · 12:00 AM');
      expect(formatManilaFriendly(DateTime.utc(2026, 12, 31, 20, 30)), 'Jan 1, 2027 · 4:30 AM');
      expect(formatManilaFriendly(null), '');
    });
  });

  group('the report log on screen', () {
    List<ReportLogEntry> twenty() => buildReportLog([
          for (var i = 0; i < 20; i++)
            _incident('id$i-aaaaaaaa',
                reporter: i == 3 ? 'Findme Person' : 'Resident $i',
                status: i.isEven ? 'resolved' : 'pending',
                responder: i.isEven ? 'Tony' : null,
                category: i == 5 ? 'Unusual Category' : 'Vandalism',
                created: _t0.add(Duration(minutes: i)),
                resolved: i.isEven ? _t0.add(Duration(minutes: i + 45)) : null),
        ], now: _now);

    Future<void> mount(WidgetTester tester, List<ReportLogEntry> entries, {Size size = const Size(420, 2200)}) async {
      useSize(tester, size);
      await tester.pumpWidget(renderApp(
        SingleChildScrollView(child: ReportLogSection(entries: entries)),
      ));
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('shows who, when, who responded and how long, for each report', (tester) async {
      await mount(tester, buildReportLog([
        _incident('aaaaaaaa-1111',
            status: 'resolved',
            responder: 'Tony Tanod',
            verified: _t0.add(const Duration(minutes: 3)),
            resolved: _t0.add(const Duration(hours: 2, minutes: 14))),
        _incident('bbbbbbbb-2222', created: _t0.add(const Duration(minutes: 20))),
      ], now: _now));
      expect(find.text('Reported by'), findsNWidgets(2));
      expect(find.text('Rita Resident'), findsNWidgets(2));
      expect(find.text('Oct 19, 2026 · 9:00 AM'), findsOneWidget);
      expect(find.text('Tony Tanod'), findsOneWidget);
      expect(find.text('Nobody yet'), findsOneWidget);
      expect(find.text('Finished in 2 h 14 min'), findsOneWidget);
      expect(find.text('after 3 min'), findsOneWidget);
      expect(find.textContaining('Still open - waiting'), findsOneWidget);
      expect(find.text('#AAAAAAAA'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await snap(tester, 'report_log_section');
    });

    testWidgets('lists 15 at a time and offers the rest', (tester) async {
      await mount(tester, twenty());
      expect(find.text('Showing 15 of 20'), findsOneWidget);
      await tester.ensureVisible(find.text('Show 5 more'));
      await tester.tap(find.text('Show 5 more'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Showing 20 of 20'), findsOneWidget);
    });

    testWidgets('Open and Finished filters', (tester) async {
      await mount(tester, twenty());
      await tester.tap(find.text('Open (10)'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Showing 10 of 10'), findsOneWidget);
      expect(find.textContaining('Finished in'), findsNothing);
      await tester.tap(find.text('Finished (10)'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Showing 10 of 10'), findsOneWidget);
      expect(find.textContaining('Still open'), findsNothing);
    });

    testWidgets('search finds a person or a category', (tester) async {
      await mount(tester, twenty());
      await tester.enterText(find.byType(TextField), 'findme');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Showing 1 of 1'), findsOneWidget);
      expect(find.text('Findme Person'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'unusual');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Unusual Category'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('No reports match.'), findsOneWidget);
    });

    testWidgets('an empty period says so', (tester) async {
      await mount(tester, const []);
      expect(find.text('No reports in this period.'), findsOneWidget);
    });

    testWidgets('tapping a report opens it', (tester) async {
      ReportLogEntry? opened;
      useSize(tester, const Size(420, 2200));
      await tester.pumpWidget(renderApp(
        SingleChildScrollView(
          child: ReportLogSection(
            entries: buildReportLog([_incident('tapme-aaaa')], now: _now),
            onOpen: (e) => opened = e,
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Vandalism').first);
      expect(opened?.id, 'tapme-aaaa');
    });
  });
}
