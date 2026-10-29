import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:barangay_safety_app/models/response_metric.dart';
import 'package:barangay_safety_app/utils/manila_time.dart';
import 'package:barangay_safety_app/utils/response_export.dart';
import 'package:barangay_safety_app/utils/response_stats.dart';
import 'package:flutter_test/flutter_test.dart';

/// 09:00 Philippine time on 20 Oct 2026 = 01:00 UTC.
final _t0 = DateTime.utc(2026, 10, 20, 1, 0, 0);

ResponseMetricRow _row(
  String id, {
  String? resident = 'Rita Resident',
  String barangay = 'Barangay 3',
  String category = 'Fire',
  int severity = 4,
  String status = 'resolved',
  DateTime? submitted,
  int? firstResponse,
  int? dispatch,
  int? travel,
  int? resolve,
  int level = 0,
  String? responder = 'Tony Tanod',
}) {
  final sub = submitted ?? _t0;
  DateTime? after(int? s) => s == null ? null : sub.add(Duration(seconds: s));
  return ResponseMetricRow(
    reportId: id,
    residentName: resident,
    barangayId: 'b-$barangay',
    barangayName: barangay,
    category: category,
    severity: severity,
    finalStatus: status,
    submittedAt: sub,
    firstActionAt: after(firstResponse),
    dispatchedAt: after(dispatch),
    onSceneAt: dispatch == null || travel == null ? null : after(dispatch + travel),
    resolvedAt: after(resolve),
    escalationLevel: level,
    level1At: level >= 1 ? sub.add(const Duration(minutes: 5)) : null,
    level2At: level >= 2 ? sub.add(const Duration(minutes: 10)) : null,
    level3At: level >= 3 ? sub.add(const Duration(minutes: 15)) : null,
    responderName: responder,
    responderRole: responder == null ? null : 'tanod',
    secsToFirstResponse: firstResponse,
    secsToDispatch: dispatch,
    secsTravel: travel,
    secsToResolve: resolve,
    answeredWithin5: firstResponse == null ? null : firstResponse <= 300,
    answeredWithin10: firstResponse == null ? null : firstResponse <= 600,
    answeredWithin15: firstResponse == null ? null : firstResponse <= 900,
  );
}

void main() {
  group('summaries', () {
    test('median / average / min / max / 90th percentile', () {
      final s = summarizeSeconds([60, 120, 180, 240, 3000]);
      expect(s.count, 5);
      expect(s.median, 180);
      expect(s.average, 720);
      expect(s.min, 60);
      expect(s.max, 3000);
      expect(s.p90, 3000); // nearest rank: ceil(0.9 * 5) = 5th value
    });

    test('median of an even count is the middle pair averaged', () {
      expect(summarizeSeconds([100, 200, 300, 400]).median, 250);
    });

    test('nearest-rank percentile only reports times that happened', () {
      final v = List<int>.generate(10, (i) => (i + 1) * 10); // 10..100
      expect(percentileNearestRank(v, 90), 90);
      expect(percentileNearestRank(v, 100), 100);
      expect(percentileNearestRank(v, 10), 10);
    });

    test('blanks are skipped, not counted as zero', () {
      final s = summarizeSeconds([null, 60, null, 120]);
      expect(s.count, 2);
      expect(s.average, 90);
    });

    test('nothing to summarise gives nulls, not zeros', () {
      final s = summarizeSeconds(const [null, null]);
      expect(s.count, 0);
      expect(s.median, isNull);
    });
  });

  group('response summary', () {
    final rows = [
      _row('a', firstResponse: 120, dispatch: 300, travel: 240, resolve: 1500), // answered in 2 min
      _row('b', firstResponse: 420, dispatch: 600, level: 1, status: 'responding'), // 7 min, L1
      _row('c', firstResponse: 1000, dispatch: 1200, level: 3), // 16:40, L3
      _row('d', firstResponse: null, status: 'pending', level: 2, responder: null), // still waiting, L2
      _row('old', firstResponse: null, status: 'resolved', responder: null), // predates tracking
    ];
    final s = summarizeRows(rows);

    test('counts', () {
      expect(s.total, 5);
      expect(s.answered, 3);
      expect(s.unansweredNow, 1); // only the pending one; the old resolved one is just blank
    });

    test('within 5 / 10 / 15 minutes are of ANSWERED reports', () {
      expect(s.within5, 1);
      expect(s.within10, 2);
      expect(s.within15, 2);
      expect(s.percentWithin5, closeTo(33.33, 0.01));
      expect(s.percentWithin10, closeTo(66.67, 0.01));
    });

    test('escalation counts are "reached at least"', () {
      expect(s.reachedLevel1, 3);
      expect(s.reachedLevel2, 2);
      expect(s.reachedLevel3, 1);
      expect(s.escalated, 3);
    });

    test('comparison with the manual baseline', () {
      // dispatch times 300, 600, 1200 -> median 600 s = 10 min
      expect(s.dispatch.median, 600);
      expect(s.dispatchImprovementVs(30), closeTo(66.67, 0.01));
      expect(s.dispatchImprovementVs(60), closeTo(83.33, 0.01));
    });

    test('slower than the baseline is a negative improvement, not hidden', () {
      final slow = summarizeRows([_row('x', firstResponse: 60, dispatch: 7200)]);
      expect(slow.dispatchImprovementVs(60), lessThan(0));
    });

    test('no answered reports: percentages are null, not 0%', () {
      final none = summarizeRows([_row('x', firstResponse: null, status: 'pending')]);
      expect(none.percentWithin5, isNull);
      expect(none.dispatchImprovementVs(30), isNull);
    });
  });

  group('grouping and trend', () {
    test('groups by barangay in a stable order', () {
      final g = groupSummaries([
        _row('1', barangay: 'Barangay 7', firstResponse: 60),
        _row('2', barangay: 'Barangay 10', firstResponse: 120),
        _row('3', barangay: 'Barangay 7', firstResponse: 180),
      ], (r) => r.barangayName!);
      expect(g.map((e) => e.key), ['Barangay 10', 'Barangay 7']);
      expect(g.last.summary.total, 2);
      expect(g.last.summary.firstResponse.median, 120);
    });

    test('the trend uses the Philippine calendar day', () {
      // 23:30 UTC on the 19th is 07:30 on the 20th in Manila.
      final t = dailyTrend([
        _row('1', submitted: DateTime.utc(2026, 10, 19, 23, 30), firstResponse: 60),
        _row('2', submitted: DateTime.utc(2026, 10, 20, 1, 0), firstResponse: 180),
        _row('3', submitted: DateTime.utc(2026, 10, 21, 1, 0), firstResponse: 90),
      ]);
      expect(t.map((p) => p.day), ['2026-10-20', '2026-10-21']);
      expect(t.first.reports, 2);
      expect(t.first.medianFirstResponseSecs, 120);
    });
  });

  group('Philippine time', () {
    test('formats UTC as UTC+8, YYYY-MM-DD HH:mm:ss', () {
      expect(formatManila(DateTime.utc(2026, 10, 20, 1, 5, 9)), '2026-10-20 09:05:09');
      expect(formatManila(DateTime.utc(2026, 12, 31, 20, 0, 0)), '2027-01-01 04:00:00');
    });

    test('a missing time stays blank', () => expect(formatManila(null), ''));

    test('a device in another zone changes nothing', () {
      final local = DateTime.parse('2026-10-20T01:05:09Z').toLocal();
      expect(formatManila(local), '2026-10-20 09:05:09');
    });

    test('mm:ss and minutes', () {
      expect(formatMinSec(272), '4:32');
      expect(formatMinSec(4530), '75:30');
      expect(formatMinSec(null), '');
      expect(secondsToMinutes(272), 4.53);
      expect(secondsToMinutes(null), isNull);
    });

    test('a Manila day starts at 16:00 UTC the day before', () {
      expect(manilaDayStartUtc(2026, 10, 20), DateTime.utc(2026, 10, 19, 16));
    });
  });

  group('the export', () {
    final rows = [
      _row('11111111-aaaa', firstResponse: 120, dispatch: 300, travel: 240, resolve: 1500, level: 1),
      _row('22222222-bbbb', barangay: 'Barangay 7', category: 'Noise', severity: 1, firstResponse: null, status: 'pending', responder: null),
    ];
    final logs = [
      StatusLogRow(reportId: '11111111-aaaa', fromStatus: null, toStatus: 'pending', changedByName: 'Rita Resident', changedByRole: 'resident', changedAt: _t0),
      StatusLogRow(reportId: '11111111-aaaa', fromStatus: 'pending', toStatus: 'verified', changedByName: 'Sam Secretary', changedByRole: 'secretary', changedAt: _t0.add(const Duration(seconds: 120))),
      StatusLogRow(reportId: 'not-in-the-filter', fromStatus: null, toStatus: 'pending', changedByName: 'X', changedByRole: 'resident', changedAt: _t0),
    ];
    final events = [
      EscalationEventRow(reportId: '11111111-aaaa', level: 1, triggeredAt: _t0.add(const Duration(minutes: 5)), notifiedRoles: const ['secretary', 'captain'], notifiedCount: 2, residentNotifiedAt: _t0.add(const Duration(minutes: 5))),
    ];
    final filters = ExportFilters(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31), barangayName: 'Barangay 3');
    final export = ResponseExport(rows: rows, statusLogs: logs, escalations: events, filters: filters, generatedAt: _t0);

    test('file name', () {
      expect(export.fileName('xlsx'), 'response_time_report_barangay_3_2026-10-01_2026-10-31.xlsx');
      final all = ResponseExport(rows: rows, statusLogs: const [], escalations: const [],
          filters: ExportFilters(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31)));
      expect(all.fileName('csv'), 'response_time_report_all_barangays_2026-10-01_2026-10-31.csv');
    });

    test('CSV: BOM, header, one row per report, Manila time, blanks stay blank', () {
      final bytes = export.buildCsv();
      expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
      final text = utf8.decode(bytes.sublist(3));
      final lines = const LineSplitter().convert(text);
      expect(lines.length, 3); // header + 2 reports
      expect(lines.first.split(',').first, 'Report ID');
      expect(lines[1], contains('2026-10-20 09:00:00')); // submitted, Manila
      expect(lines[1], contains('2026-10-20 09:02:00')); // first action
      expect(lines[1], contains('2:00')); // time to first response
      // The unanswered report has an empty first-action cell, not a made-up time.
      expect(lines[2], contains('2026-10-20 09:00:00,,'));
    });

    test('CSV: quoting', () {
      final tricky = ResponseExport(
        rows: [_row('x', resident: 'Dela Cruz, Juan "JD"')],
        statusLogs: const [], escalations: const [], filters: filters, generatedAt: _t0);
      final text = utf8.decode(tricky.buildCsv().sublist(3));
      expect(text, contains('"Dela Cruz, Juan ""JD"""'));
    });

    test('CSV: a name that starts a spreadsheet formula is defused', () {
      for (final evil in ['=HYPERLINK("http://evil","x")', '+1+1', '-2+3', '@SUM(A1)']) {
        final e = ResponseExport(rows: [_row('x', resident: evil)], statusLogs: const [],
            escalations: const [], filters: filters, generatedAt: _t0);
        final cells = utf8.decode(e.buildCsv().sublist(3)).split('\r\n')[1];
        expect(cells, isNot(contains(',$evil')), reason: evil);
        expect(cells, contains("'${evil.replaceAll('"', '""')}"), reason: evil);
      }
    });

    test('privacy: no location, phone, email, ID or photo column anywhere', () {
      final banned = RegExp(
        r'latitude|longitude|\blat\b|\blng\b|gps|coordinate|address|landmark|street|phone|mobile|contact|email|passport|\bid photo|government|photo|picture|video',
        caseSensitive: false,
      );
      for (final h in ResponseExport.reportLogHeaders) {
        expect(banned.hasMatch(h), isFalse, reason: 'column "$h"');
      }
      // The only personal field is the resident's name, as the brief allows.
      expect(ResponseExport.reportLogHeaders, contains('Resident'));
    });

    test('Excel: a valid zip with the six sheets, in order', () {
      final bytes = export.buildXlsx();
      final zip = ZipDecoder().decodeBytes(bytes);
      final names = zip.files.map((f) => f.name).toSet();
      for (final part in [
        '[Content_Types].xml', '_rels/.rels', 'xl/workbook.xml',
        'xl/_rels/workbook.xml.rels', 'xl/styles.xml',
        for (var i = 1; i <= 6; i++) 'xl/worksheets/sheet$i.xml',
      ]) {
        expect(names, contains(part));
      }
      final workbook = utf8.decode(zip.findFile('xl/workbook.xml')!.content as List<int>);
      final order = RegExp(r'<sheet name="([^"]+)"').allMatches(workbook).map((m) => m.group(1)).toList();
      expect(order, ['Summary', 'Report Log', 'Status Timeline', 'Escalations', 'Per Barangay', 'Per Category & Severity'.replaceAll('&', '&amp;')]);
    });

    test('Excel: timeline holds only the filtered reports, with minutes since submission', () {
      final zip = ZipDecoder().decodeBytes(export.buildXlsx());
      final sheet3 = utf8.decode(zip.findFile('xl/worksheets/sheet3.xml')!.content as List<int>);
      expect(sheet3, contains('Sam Secretary'));
      expect(sheet3, contains('(new report)'));
      expect(sheet3, isNot(contains('not-in-the-filter')));
      expect(sheet3, contains('<v>2.0</v>')); // verified two minutes after submission
    });

    test('Excel: special characters cannot corrupt the file', () {
      final e = ResponseExport(
        rows: [_row('x', resident: 'A & B <script>\u0001</script> "q"')],
        statusLogs: const [], escalations: const [], filters: filters, generatedAt: _t0);
      final zip = ZipDecoder().decodeBytes(e.buildXlsx());
      final sheet2 = utf8.decode(zip.findFile('xl/worksheets/sheet2.xml')!.content as List<int>);
      expect(sheet2, contains('A &amp; B &lt;script&gt;&lt;/script&gt; "q"'));
      expect(sheet2.contains('\u0001'), isFalse);
    });

    test('Excel: writes a real file for an outside reader to open', () {
      final dir = Platform.environment['XLSX_OUT'];
      if (dir == null) return; // only when a person wants to inspect it
      File('$dir/response_time_report.xlsx').writeAsBytesSync(export.buildXlsx());
      File('$dir/response_time_report.csv').writeAsBytesSync(export.buildCsv());
    });
  });
}
