import 'dart:convert';
import 'dart:typed_data';

import '../models/response_metric.dart';
import 'manila_time.dart';
import 'report_document.dart';
import 'response_stats.dart';
import 'xlsx_writer.dart';

/// What the export was filtered by. Printed on the Summary sheet and stored in
/// the export log, so anyone can see exactly which slice of data a file holds.
class ExportFilters {
  const ExportFilters({
    required this.from,
    required this.to,
    this.barangayName,
    this.category,
    this.severity,
    this.status,
    this.escalationLevel,
    this.responder,
  });

  /// Inclusive Philippine calendar dates.
  final DateTime from;
  final DateTime to;

  /// Null = every barangay (a superadmin's view).
  final String? barangayName;
  final String? category;
  final int? severity;
  final String? status;
  final int? escalationLevel;
  final String? responder;

  String get fromText => manilaDate(DateTime.utc(from.year, from.month, from.day));
  String get toText => manilaDate(DateTime.utc(to.year, to.month, to.day));

  /// Human-readable lines for the Summary sheet.
  List<List<String>> describe() => [
        ['Date range (Philippine time)', '$fromText to $toText'],
        ['Barangay', barangayName ?? 'All barangays'],
        ['Category', category ?? 'All'],
        ['Severity', severity == null ? 'All' : severityName(severity!)],
        ['Status', status ?? 'All'],
        ['Escalation level',
          escalationLevel == null ? 'All' : 'Level $escalationLevel or higher'],
        ['Responder', responder ?? 'All'],
      ];

  Map<String, dynamic> toJson() => {
        'from': fromText,
        'to': toText,
        'barangay': barangayName,
        'category': category,
        'severity': severity,
        'status': status,
        'escalation_level_min': escalationLevel,
        'responder': responder,
      };
}

String severityName(int level) => switch (level) {
      4 => 'Critical',
      3 => 'High',
      2 => 'Medium',
      _ => 'Low',
    };

/// Everything one export needs, built from the SAME filtered rows the dashboard
/// shows, so the file and the screen cannot disagree.
class ResponseExport {
  ResponseExport({
    required this.rows,
    required this.statusLogs,
    required this.escalations,
    required this.filters,
    DateTime? generatedAt,
  }) : generatedAt = generatedAt ?? DateTime.now().toUtc();

  final List<ResponseMetricRow> rows;
  final List<StatusLogRow> statusLogs;
  final List<EscalationEventRow> escalations;
  final ExportFilters filters;
  final DateTime generatedAt;

  /// `response_time_report_[barangay]_[from]_[to].<ext>`
  String fileName(String extension) {
    final scope = (filters.barangayName ?? 'all_barangays')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'response_time_report_${scope}_${filters.fromText}_${filters.toText}.$extension';
  }

  // ── Report Log ────────────────────────────────────────────────────────────
  /// Column order of the Report Log sheet and of the CSV.
  static const List<String> reportLogHeaders = [
    'Report ID',
    'Resident',
    'Barangay',
    'Category',
    'Severity',
    'Severity Level',
    'Final Status',
    'Submitted',
    'First Seen',
    'First Action',
    'Acknowledged',
    'Assigned',
    'Dispatched',
    'On Scene',
    'Resolved',
    'Closed',
    'Escalation Level Reached',
    'Level 1 At',
    'Level 2 At',
    'Level 3 At',
    'Responder',
    'Responder Role',
    'Time to First Seen (min)',
    'Time to First Seen (mm:ss)',
    'Time to First Response (min)',
    'Time to First Response (mm:ss)',
    'Time to Dispatch (min)',
    'Time to Dispatch (mm:ss)',
    'Travel Time (min)',
    'Travel Time (mm:ss)',
    'Time to Resolve (min)',
    'Time to Resolve (mm:ss)',
    'Total Time Open (min)',
    'Total Time Open (mm:ss)',
    'Escalated',
    'Answered within 5 min',
    'Answered within 10 min',
    'Answered within 15 min',
  ];

  List<List<Object?>> reportLogRows() {
    List<Object?> dur(int? secs) => [secondsToMinutes(secs), formatMinSec(secs)];
    return [
      for (final r in rows)
        [
          r.reportId,
          r.residentName,
          r.barangayName,
          r.category,
          severityName(r.severity),
          r.severity,
          r.finalStatus,
          formatManila(r.submittedAt),
          formatManila(r.firstSeenAt),
          formatManila(r.firstActionAt),
          formatManila(r.acknowledgedAt),
          formatManila(r.assignedAt),
          formatManila(r.dispatchedAt),
          formatManila(r.onSceneAt),
          formatManila(r.resolvedAt),
          formatManila(r.closedAt),
          r.escalationLevel,
          formatManila(r.level1At),
          formatManila(r.level2At),
          formatManila(r.level3At),
          r.responderName,
          r.responderRole,
          ...dur(r.secsToFirstSeen),
          ...dur(r.secsToFirstResponse),
          ...dur(r.secsToDispatch),
          ...dur(r.secsTravel),
          ...dur(r.secsToResolve),
          ...dur(r.secsTotalOpen),
          r.wasEscalated ? 'Yes' : 'No',
          _yesNo(r.answeredWithin5),
          _yesNo(r.answeredWithin10),
          _yesNo(r.answeredWithin15),
        ],
    ];
  }

  static String _yesNo(bool? v) => v == null ? '' : (v ? 'Yes' : 'No');

  // ── CSV ───────────────────────────────────────────────────────────────────
  /// The Report Log as CSV: UTF-8 with a byte-order mark (so Excel reads the
  /// accents in Filipino names correctly), CRLF line ends, RFC 4180 quoting.
  Uint8List buildCsv() {
    final b = StringBuffer()
      ..write(reportLogHeaders.map(_csvCell).join(','))
      ..write('\r\n');
    for (final row in reportLogRows()) {
      b
        ..write(row.map(_csvCell).join(','))
        ..write('\r\n');
    }
    return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(b.toString())]);
  }

  static String _csvCell(Object? v) {
    if (v == null) return '';
    var s = v is double ? _trimNumber(v) : v.toString();
    // A resident chooses their own name. One that begins with "=" would run as
    // a formula the moment an official opened the CSV in Excel, so any text that
    // could start one is defanged with a leading apostrophe.
    if (v is String && s.isNotEmpty && '=+-@\t\r'.contains(s[0])) {
      s = "'$s";
    }
    if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static String _trimNumber(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  // ── Word ──────────────────────────────────────────────────────────────────
  /// A readable summary for a Word document: the same figures as the Excel
  /// Summary / Per-barangay / Per-category sheets, as tables to edit and quote.
  /// The row-by-row log stays in Excel and CSV, where it belongs.
  Uint8List buildDocx() => summaryDocument().toDocx();

  ReportDocument summaryDocument() {
    final s = summarizeRows(rows);
    String pct(double? v) => v == null ? '-' : '${v.toStringAsFixed(1)}%';
    List<Object?> dur(String label, DurationSummary d) => [
          label,
          d.count,
          formatMinSec(d.average),
          formatMinSec(d.median),
          formatMinSec(d.min),
          formatMinSec(d.max),
          formatMinSec(d.p90),
        ];
    String faster(int baseline) {
      final v = s.dispatchImprovementVs(baseline);
      if (v == null) return 'No dispatches recorded yet';
      return v >= 0
          ? '${v.toStringAsFixed(0)}% faster than $baseline min'
          : '${(-v).toStringAsFixed(0)}% slower than $baseline min';
    }

    ReportSection group(String heading, String first, List<GroupStat> groups) => ReportSection(
          heading: heading,
          headers: [first, 'Reports', 'Answered', 'Median first response', 'Median dispatch', 'Escalated', 'Level 3'],
          columnWeights: const [3, 1, 1, 2, 2, 1, 1],
          rows: [
            for (final g in groups)
              [
                g.key,
                g.summary.total,
                g.summary.answered,
                formatMinSec(g.summary.firstResponse.median),
                formatMinSec(g.summary.dispatch.median),
                g.summary.escalated,
                g.summary.reachedLevel3,
              ],
          ],
        );

    return ReportDocument(
      title: 'Response Time Report',
      infoLines: [
        for (final line in filters.describe()) '${line[0]}: ${line[1]}',
        'Generated (Philippine time): ${formatManila(generatedAt)}',
      ],
      sections: [
        ReportSection(
          heading: 'Reports',
          headers: const ['Measure', 'Count'],
          columnWeights: const [3, 1],
          rows: [
            ['Total reports', s.total],
            ['Answered (a first action is recorded)', s.answered],
            ['Still unanswered', s.unansweredNow],
          ],
        ),
        ReportSection(
          heading: 'Durations (minutes:seconds)',
          headers: const ['Measure', 'Counted', 'Average', 'Median', 'Min', 'Max', '90th pct'],
          columnWeights: const [4, 1, 1, 1, 1, 1, 1],
          rows: [
            dur('Time to first seen', s.firstSeen),
            dur('Time to first response', s.firstResponse),
            dur('Time to dispatch', s.dispatch),
            dur('Travel time', s.travel),
            dur('Time to resolve', s.resolve),
            dur('Total time open', s.totalOpen),
          ],
        ),
        ReportSection(
          heading: 'Answered within (of answered reports)',
          headers: const ['Within', 'Reports', 'Share'],
          columnWeights: const [3, 1, 1],
          rows: [
            ['5 minutes', s.within5, pct(s.percentWithin5)],
            ['10 minutes', s.within10, pct(s.percentWithin10)],
            ['15 minutes', s.within15, pct(s.percentWithin15)],
          ],
        ),
        ReportSection(
          heading: 'Escalations (reports that reached at least)',
          headers: const ['Level', 'Reports'],
          columnWeights: const [4, 1],
          rows: [
            ['Level 1 (5 min, no response)', s.reachedLevel1],
            ['Level 2 (10 min, whole barangay alerted)', s.reachedLevel2],
            ['Level 3 (15 min, Unattended / Last Resort)', s.reachedLevel3],
          ],
        ),
        ReportSection(
          heading: 'Comparison with the manual process',
          headers: const ['Measure', 'Value'],
          columnWeights: const [3, 2],
          rows: [
            ['Manual baseline, report to dispatch',
              '$kManualBaselineMinMinutes to $kManualBaselineMaxMinutes minutes'],
            ['System median time to dispatch', formatMinSec(s.dispatch.median)],
            ['Against the faster baseline', faster(kManualBaselineMinMinutes)],
            ['Against the slower baseline', faster(kManualBaselineMaxMinutes)],
          ],
          note: 'Blank or dashed values mean the step has not happened, or happened '
              'before response tracking began. Nothing is estimated.',
        ),
        group('Per barangay', 'Barangay',
            groupSummaries(rows, (r) => r.barangayName ?? '(unknown)')),
        group('Per category', 'Category', groupSummaries(rows, (r) => r.category)),
        group('Per severity', 'Severity',
            [
              for (final g in groupSummaries(rows, (r) => '${4 - r.severity} ${severityName(r.severity)}'))
                GroupStat(key: g.key.substring(2), summary: g.summary),
            ]),
      ],
      footer: 'Barangay Safety Incident Reporting System - Lipa City, Batangas',
    );
  }

  // ── Excel ─────────────────────────────────────────────────────────────────
  Uint8List buildXlsx() => writeXlsx([
        _summarySheet(),
        _reportLogSheet(),
        _timelineSheet(),
        _escalationsSheet(),
        _perBarangaySheet(),
        _perCategorySeveritySheet(),
      ]);

  XlsxSheet _summarySheet() {
    final s = summarizeRows(rows);
    List<Object?> durationRow(String label, DurationSummary d) => [
          label,
          d.count,
          formatMinSec(d.average),
          formatMinSec(d.median),
          formatMinSec(d.min),
          formatMinSec(d.max),
          formatMinSec(d.p90),
        ];
    String pct(double? v) => v == null ? '' : '${v.toStringAsFixed(1)}%';
    String faster(int baseline) {
      final v = s.dispatchImprovementVs(baseline);
      if (v == null) return 'No dispatches recorded yet';
      return v >= 0
          ? '${v.toStringAsFixed(0)}% faster than $baseline min'
          : '${(-v).toStringAsFixed(0)}% slower than $baseline min';
    }

    return XlsxSheet(
      'Summary',
      [
        [const XlsxCell('Response Time Report', bold: true)],
        ['Generated (Philippine time)', formatManila(generatedAt)],
        [],
        [const XlsxCell('Filters used', bold: true)],
        ...filters.describe(),
        [],
        [const XlsxCell('Reports', bold: true)],
        ['Total reports', s.total],
        ['Answered (a first action is recorded)', s.answered],
        ['Still unanswered', s.unansweredNow],
        [],
        [const XlsxCell('Durations (mm:ss)', bold: true)],
        [
          const XlsxCell('Measure', header: true),
          const XlsxCell('Reports counted', header: true),
          const XlsxCell('Average', header: true),
          const XlsxCell('Median', header: true),
          const XlsxCell('Minimum', header: true),
          const XlsxCell('Maximum', header: true),
          const XlsxCell('90th percentile', header: true),
        ],
        durationRow('Time to first seen', s.firstSeen),
        durationRow('Time to first response', s.firstResponse),
        durationRow('Time to dispatch', s.dispatch),
        durationRow('Travel time (dispatched to on scene)', s.travel),
        durationRow('Time to resolve', s.resolve),
        durationRow('Total time open (to closed)', s.totalOpen),
        [],
        [const XlsxCell('Answered within (of answered reports)', bold: true)],
        ['Within 5 minutes', s.within5, pct(s.percentWithin5)],
        ['Within 10 minutes', s.within10, pct(s.percentWithin10)],
        ['Within 15 minutes', s.within15, pct(s.percentWithin15)],
        [],
        [const XlsxCell('Escalations (reports that reached at least)', bold: true)],
        ['Level 1 (5 min, no response)', s.reachedLevel1],
        ['Level 2 (10 min, whole barangay alerted)', s.reachedLevel2],
        ['Level 3 (15 min, Unattended / Last Resort)', s.reachedLevel3],
        [],
        [const XlsxCell('Comparison with the manual process', bold: true)],
        ['Manual baseline, report to dispatch',
          '$kManualBaselineMinMinutes to $kManualBaselineMaxMinutes minutes'],
        ['System median time to dispatch', formatMinSec(s.dispatch.median)],
        ['Against the faster baseline', faster(kManualBaselineMinMinutes)],
        ['Against the slower baseline', faster(kManualBaselineMaxMinutes)],
        [],
        [
          'Blank cells mean the step has not happened, or happened before response '
              'tracking began. Nothing is estimated.'
        ],
      ],
      columnWidths: const [44, 18, 12, 12, 12, 12, 16],
    );
  }

  XlsxSheet _reportLogSheet() => XlsxSheet(
        'Report Log',
        [
          [for (final h in reportLogHeaders) XlsxCell(h, header: true)],
          ...reportLogRows(),
        ],
        columnWidths: [
          38, 24, 14, 22, 10, 9, 13, //
          for (var i = 0; i < 13; i++) 19, // 13 timestamp / level columns
          22, 14,
          for (var i = 0; i < 12; i++) 13, // six durations x two columns
          10, 12, 12, 12,
        ],
        freezeHeaderRow: true,
      );

  XlsxSheet _timelineSheet() {
    final byId = {for (final r in rows) r.reportId: r};
    final timeline = statusLogs.where((l) => byId.containsKey(l.reportId)).toList()
      ..sort((a, b) {
        final c = a.reportId.compareTo(b.reportId);
        return c != 0 ? c : a.changedAt.compareTo(b.changedAt);
      });
    return XlsxSheet(
      'Status Timeline',
      [
        [
          for (final h in const [
            'Report ID', 'Resident', 'Barangay', 'From', 'To', 'Changed By',
            'Role', 'Changed At', 'Minutes Since Submission', 'Remarks',
          ])
            XlsxCell(h, header: true),
        ],
        for (final l in timeline)
          [
            l.reportId,
            byId[l.reportId]!.residentName,
            byId[l.reportId]!.barangayName,
            l.fromStatus ?? '(new report)',
            l.toStatus,
            l.changedByName,
            l.changedByRole,
            formatManila(l.changedAt),
            secondsToMinutes(
                l.changedAt.difference(byId[l.reportId]!.submittedAt).inSeconds),
            l.remarks,
          ],
      ],
      columnWidths: const [38, 24, 14, 14, 14, 24, 14, 19, 14, 30],
      freezeHeaderRow: true,
    );
  }

  XlsxSheet _escalationsSheet() {
    final byId = {for (final r in rows) r.reportId: r};
    final events = escalations.where((e) => byId.containsKey(e.reportId)).toList()
      ..sort((a, b) {
        final c = a.reportId.compareTo(b.reportId);
        return c != 0 ? c : a.level.compareTo(b.level);
      });
    return XlsxSheet(
      'Escalations',
      [
        [
          for (final h in const [
            'Report ID', 'Resident', 'Barangay', 'Category', 'Level',
            'Triggered At', 'Minutes Since Submission', 'People Notified',
            'Roles Notified', 'Resident Notified At',
          ])
            XlsxCell(h, header: true),
        ],
        for (final e in events)
          [
            e.reportId,
            byId[e.reportId]!.residentName,
            byId[e.reportId]!.barangayName,
            byId[e.reportId]!.category,
            e.level,
            formatManila(e.triggeredAt),
            secondsToMinutes(
                e.triggeredAt.difference(byId[e.reportId]!.submittedAt).inSeconds),
            e.notifiedCount,
            e.notifiedRoles.join(', '),
            formatManila(e.residentNotifiedAt),
          ],
      ],
      columnWidths: const [38, 24, 14, 22, 7, 19, 14, 11, 36, 19],
      freezeHeaderRow: true,
    );
  }

  static List<Object?> _groupHeader(String firstColumn) => [
        for (final h in [
          firstColumn, 'Reports', 'Answered', 'Median First Response (mm:ss)',
          'Average First Response (mm:ss)', '90th Percentile First Response (mm:ss)',
          'Median Dispatch (mm:ss)', 'Average Dispatch (mm:ss)',
          'Answered within 5 min (%)', 'Answered within 10 min (%)',
          'Answered within 15 min (%)', 'Escalated', 'Reached Level 3',
        ])
          XlsxCell(h, header: true),
      ];

  static List<Object?> _groupRow(String key, ResponseSummary s) {
    double? r1(double? v) => v == null ? null : double.parse(v.toStringAsFixed(1));
    return [
      key,
      s.total,
      s.answered,
      formatMinSec(s.firstResponse.median),
      formatMinSec(s.firstResponse.average),
      formatMinSec(s.firstResponse.p90),
      formatMinSec(s.dispatch.median),
      formatMinSec(s.dispatch.average),
      r1(s.percentWithin5),
      r1(s.percentWithin10),
      r1(s.percentWithin15),
      s.escalated,
      s.reachedLevel3,
    ];
  }

  XlsxSheet _perBarangaySheet() => XlsxSheet(
        'Per Barangay',
        [
          _groupHeader('Barangay'),
          for (final g in groupSummaries(rows, (r) => r.barangayName ?? '(unknown)'))
            _groupRow(g.key, g.summary),
        ],
        columnWidths: const [22, 9, 10, 16, 16, 18, 16, 16, 14, 14, 14, 10, 12],
        freezeHeaderRow: true,
      );

  XlsxSheet _perCategorySeveritySheet() => XlsxSheet(
        'Per Category & Severity',
        [
          _groupHeader('Category'),
          for (final g in groupSummaries(rows, (r) => r.category))
            _groupRow(g.key, g.summary),
          [],
          _groupHeader('Severity'),
          for (final g in groupSummaries(rows, (r) => '${4 - r.severity} ${severityName(r.severity)}'))
            _groupRow(g.key.substring(2), g.summary),
        ],
        columnWidths: const [24, 9, 10, 16, 16, 18, 16, 16, 14, 14, 14, 10, 12],
      );
}
