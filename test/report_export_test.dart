import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:barangay_safety_app/models/response_metric.dart';
import 'package:barangay_safety_app/utils/analytics_report.dart';
import 'package:barangay_safety_app/utils/docx_writer.dart';
import 'package:barangay_safety_app/utils/report_document.dart';
import 'package:barangay_safety_app/utils/response_export.dart';
import 'package:barangay_safety_app/widgets/export_format_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

String _part(List<int> bytes, String name) {
  final zip = ZipDecoder().decodeBytes(bytes);
  final f = zip.findFile(name);
  expect(f, isNotNull, reason: 'missing $name');
  return utf8.decode(f!.content as List<int>);
}

ReportDocument _sample() => buildAnalyticsReport(
      appName: 'Barangay Safety',
      barangayName: 'Barangay 3',
      periodLabel: 'All time',
      generatedAt: DateTime.utc(2026, 10, 20, 1, 5, 9),
      today: DateTime.utc(2026, 10, 20, 1),
      total: 20,
      nonResident: 3,
      pending: 1,
      inProgress: 2,
      resolved: 17,
      flagged: 0,
      overdue: 2,
      resolutionRate: 85,
      avgResolutionHours: 152.5,
      slaCompliance: 65,
      categories: const [MapEntry('Public Disturbance', 3), MapEntry('Fire', 3), MapEntry('Vandalism', 1)],
      last7Days: const [0, 1, 0, 2, 0, 0, 3],
    );

void main() {
  group('Word writer', () {
    final bytes = writeDocx(const [
      DocxParagraph('Report', style: DocxStyle.title),
      DocxParagraph('Barangay 3', style: DocxStyle.small),
      DocxParagraph('Overview', style: DocxStyle.heading1),
      DocxTable(['Metric', 'Count'], [
        ['Total', '20'],
        ['A & B <x>', '1'],
      ], columnWeights: [3, 1]),
      DocxTable(['Second'], [
        ['row'],
      ]),
    ]);

    test('is a zip with every part Word needs', () {
      final names = ZipDecoder().decodeBytes(bytes).files.map((f) => f.name).toSet();
      expect(names, containsAll([
        '[Content_Types].xml',
        '_rels/.rels',
        'word/document.xml',
        'word/styles.xml',
        'word/_rels/document.xml.rels',
      ]));
      expect(bytes.sublist(0, 2), [0x50, 0x4B]);
    });

    test('headings use heading styles and tables have a repeating header row', () {
      final doc = _part(bytes, 'word/document.xml');
      expect(doc, contains('<w:pStyle w:val="Title"/>'));
      expect(doc, contains('<w:pStyle w:val="Heading1"/>'));
      expect(RegExp('<w:tblHeader/>').allMatches(doc).length, 2);
      expect(doc, contains('w:fill="1D4ED8"')); // shaded header
    });

    test('special characters are escaped so the file always opens', () {
      final doc = _part(bytes, 'word/document.xml');
      expect(doc, contains('A &amp; B &lt;x&gt;'));
      final dirty = _part(writeDocx(const [DocxParagraph('bad \u0001 byte')]), 'word/document.xml');
      expect(dirty.contains('\u0001'), isFalse);
    });

    test('a table is always followed by a paragraph (Word refuses otherwise)', () {
      final doc = _part(bytes, 'word/document.xml');
      expect(doc, contains('</w:tbl><w:p>'));
      expect(doc.indexOf('<w:sectPr>'), greaterThan(doc.lastIndexOf('</w:tbl>')));
    });

    test('column widths follow the weights and add up to the page width', () {
      final doc = _part(bytes, 'word/document.xml');
      final grid = RegExp(r'<w:gridCol w:w="(\d+)"/>').allMatches(doc).map((m) => int.parse(m.group(1)!)).toList();
      expect(grid.take(2).toList(), [7228, 2409]); // 3:1 of 9638
    });
  });

  group('the analytics report', () {
    final report = _sample();

    test('has the same four tables the PDF had, and no PDF', () {
      expect(report.sections.map((s) => s.heading),
          ['Overview', 'Response Performance', 'Top Categories', 'Incidents - Last 7 Days']);
    });

    test('numbers and percentages are right', () {
      final overview = report.sections[0].rows;
      expect(overview.first, ['Total reports', 20]);
      expect(overview.firstWhere((r) => r[0] == 'Resident reports')[1], 17);
      final perf = report.sections[1].rows;
      expect(perf.firstWhere((r) => r[0] == 'Average resolution time')[1], '152.5 hrs');
      expect(perf.firstWhere((r) => r[0] == 'Resolution rate')[1], '85.0%');
      final cats = report.sections[2].rows;
      expect(cats.first, ['Public Disturbance', 3, '15.0%']);
    });

    test('the seven days end today, in Philippine dates', () {
      final days = report.sections[3].rows;
      expect(days.length, 7);
      expect(days.last, ['2026-10-20', 3]);
      expect(days.first[0], '2026-10-14');
    });

    test('short resolution times read in minutes; none reads N/A', () {
      String avg(double h) => buildAnalyticsReport(
            appName: 'A', barangayName: 'B', periodLabel: 'p',
            generatedAt: DateTime.utc(2026), today: DateTime.utc(2026),
            total: 0, nonResident: 0, pending: 0, inProgress: 0, resolved: 0, flagged: 0, overdue: 0,
            resolutionRate: 0, avgResolutionHours: h, slaCompliance: 0,
            categories: const [], last7Days: List.filled(7, 0),
          ).sections[1].rows.firstWhere((r) => r[0] == 'Average resolution time')[1] as String;
      expect(avg(0.5), '30 min');
      expect(avg(0), 'N/A');
    });

    test('an empty period leaves out the empty category table instead of printing a blank one', () {
      final r = buildAnalyticsReport(
        appName: 'A', barangayName: 'B', periodLabel: 'p',
        generatedAt: DateTime.utc(2026), today: DateTime.utc(2026),
        total: 0, nonResident: 0, pending: 0, inProgress: 0, resolved: 0, flagged: 0, overdue: 0,
        resolutionRate: 0, avgResolutionHours: 0, slaCompliance: 0,
        categories: const [], last7Days: List.filled(7, 0),
      );
      expect(r.sections.map((s) => s.heading), isNot(contains('Top Categories')));
      // ... and the percentage column never divides by zero.
      expect(r.sections.length, 3);
    });

    test('aggregate only: nothing that identifies a person or a place', () {
      final all = jsonEncode([
        report.title,
        report.infoLines,
        for (final s in report.sections) [s.headings, s.headers, s.rows],
      ]);
      expect(RegExp(r'latitude|longitude|address|phone|email|photo', caseSensitive: false).hasMatch(all), isFalse);
    });

    test('Excel: an About sheet plus one sheet per table, numbers kept as numbers', () {
      final bytes = report.toXlsx();
      final workbook = _part(bytes, 'xl/workbook.xml');
      final names = RegExp(r'<sheet name="([^"]+)"').allMatches(workbook).map((m) => m.group(1)).toList();
      expect(names, ['About', 'Overview', 'Response Performance', 'Top Categories', 'Incidents - Last 7 Days']);
      final overview = _part(bytes, 'xl/worksheets/sheet2.xml');
      expect(overview, contains('<v>20</v>')); // a real number, sortable in Excel
      expect(overview, contains('Total reports'));
      expect(_part(bytes, 'xl/worksheets/sheet1.xml'), contains('Barangay: Barangay 3'));
    });

    test('Word: title, info lines, headings and tables, and the footer', () {
      final doc = _part(report.toDocx(), 'word/document.xml');
      expect(doc, contains('Barangay Safety - Analytics Report'));
      expect(doc, contains('Period: All time'));
      expect(doc, contains('Generated (Philippine time): 2026-10-20 09:05:09'));
      for (final h in ['Overview', 'Response Performance', 'Top Categories', 'Incidents - Last 7 Days']) {
        expect(doc, contains('>$h<'), reason: h);
      }
      expect(doc, contains('152.5 hrs'));
      expect(doc, contains('Lipa City, Batangas'));
      expect(RegExp('<w:tbl>').allMatches(doc).length, 4);
    });
  });

  group('the response-time Word summary', () {
    final t0 = DateTime.utc(2026, 10, 20, 1);
    ResponseMetricRow row(String id, {int? first, int? dispatch, int level = 0, String barangay = 'Barangay 3'}) => ResponseMetricRow(
          reportId: id,
          residentName: 'Resident $id',
          barangayId: 'b',
          barangayName: barangay,
          category: 'Fire',
          severity: 4,
          finalStatus: 'resolved',
          submittedAt: t0,
          firstActionAt: first == null ? null : t0.add(Duration(seconds: first)),
          escalationLevel: level,
          secsToFirstResponse: first,
          secsToDispatch: dispatch,
          answeredWithin5: first == null ? null : first <= 300,
          answeredWithin10: first == null ? null : first <= 600,
          answeredWithin15: first == null ? null : first <= 900,
        );

    final export = ResponseExport(
      rows: [row('a', first: 120, dispatch: 300), row('b', first: 700, dispatch: 900, level: 2), row('c')],
      statusLogs: const [],
      escalations: const [],
      filters: ExportFilters(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31), barangayName: 'Barangay 3'),
      generatedAt: t0,
    );

    test('file name follows the same pattern as the Excel one', () {
      expect(export.fileName('docx'), 'response_time_report_barangay_3_2026-10-01_2026-10-31.docx');
    });

    test('Word carries the same figures as the Excel summary', () {
      final doc = _part(export.buildDocx(), 'word/document.xml');
      expect(doc, contains('Response Time Report'));
      expect(doc, contains('Barangay: Barangay 3'));
      expect(doc, contains('Total reports'));
      // median first response of 120 s and 700 s = 410 s = 6:50
      expect(doc, contains('6:50'));
      expect(doc, contains('Level 2 (10 min, whole barangay alerted)'));
      expect(doc, contains('faster than 30 min'));
      expect(doc, contains('Per barangay'));
      expect(doc, contains('Per severity'));
      expect(doc, contains('Critical'));
    });

    test('Word never contains the row-by-row personal data (that stays in Excel)', () {
      final doc = _part(export.buildDocx(), 'word/document.xml');
      expect(doc.contains('Resident a'), isFalse);
    });

    test('a step that has not happened shows a dash, never an invented value', () {
      final empty = ResponseExport(
        rows: [row('c')], statusLogs: const [], escalations: const [],
        filters: ExportFilters(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31)),
        generatedAt: t0,
      );
      final doc = _part(empty.buildDocx(), 'word/document.xml');
      expect(doc, contains('No dispatches recorded yet'));
    });
  });

  group('formats on offer', () {
    test('Excel and Word — no PDF', () {
      expect(ExportFormat.values.map((f) => f.extension), ['xlsx', 'docx']);
      expect(ExportFormat.values.map((f) => f.mimeType).join(), isNot(contains('pdf')));
    });

    test('the Analytics screen no longer builds a PDF', () {
      final src = File('lib/screens/shared/analytics_screen.dart').readAsStringSync();
      expect(src, isNot(contains('Printing.sharePdf')));
      expect(src, isNot(contains('package:pdf/')));
      expect(src, isNot(contains('Export as PDF')));
    });
  });

  test('writes real files for an outside reader to open', () {
    final dir = Platform.environment['XLSX_OUT'];
    if (dir == null) return;
    File('$dir/analytics_report.xlsx').writeAsBytesSync(_sample().toXlsx());
    File('$dir/analytics_report.docx').writeAsBytesSync(_sample().toDocx());
  });
}

extension on ReportSection {
  // Test helper: the heading, for the "no personal data" scan.
  String get headings => heading;
}
