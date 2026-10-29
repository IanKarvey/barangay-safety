import 'manila_time.dart';
import 'report_document.dart';
import 'report_log.dart';

/// The Analytics & Reports document, as a [ReportDocument] that can be exported to
/// Excel or Word.
///
/// It has two halves:
///   * the SUMMARY (counts, rates, categories, last 7 days, per responder); and
///   * the REPORT LOG — one row for every report in the period: who reported it,
///     when, who responded, when they first responded, when it was finished, and
///     how long it took. This is the half officials asked for ("each and every
///     one of the reports ... very specific and detailed").
///
/// Privacy: a person's NAME appears (reporter and responder), as the brief allows.
/// Nothing else that identifies or locates anyone does — no phone, email, ID,
/// photo, address, landmark, coordinates or report description (a walk-in's
/// number is typed into that description, so it is never printed). See
/// [ReportLogEntry].
ReportDocument buildAnalyticsReport({
  required String appName,
  required String barangayName,
  required String periodLabel,
  required DateTime generatedAt,
  required DateTime today,
  required int total,
  required int nonResident,
  required int pending,
  required int inProgress,
  required int resolved,
  required int flagged,
  required int overdue,
  required double resolutionRate,
  required double avgResolutionHours,
  required double slaCompliance,
  required List<MapEntry<String, int>> categories,
  required List<int> last7Days,
  List<ReportLogEntry> log = const [],
  String overviewHeading = 'Overview',
  String performanceHeading = 'Response Performance',
  String categoriesHeading = 'Top Categories',
  String last7Heading = 'Incidents - Last 7 Days',
}) {
  assert(last7Days.length == 7, 'one count per day for seven days');

  final avgLabel = avgResolutionHours == 0
      ? 'N/A'
      : avgResolutionHours < 1
          ? '${(avgResolutionHours * 60).toStringAsFixed(0)} min'
          : '${avgResolutionHours.toStringAsFixed(1)} hrs';

  String pct(num part) => total > 0 ? (part / total * 100).toStringAsFixed(1) : '0.0';

  final stats = ReportLogStats.from(log);
  String dur(double? secs) =>
      secs == null ? '-' : humanDuration(Duration(seconds: secs.round()));
  String extreme(ReportLogEntry? e) => e == null
      ? '-'
      : '${humanDuration(e.timeToFinish!)} (${e.category}, ${e.shortId})';

  return ReportDocument(
    title: '$appName - Analytics Report',
    landscape: log.isNotEmpty, // the report list is wide
    infoLines: [
      'Barangay: $barangayName',
      'Period: $periodLabel',
      'Generated (Philippine time): ${formatManila(generatedAt)}',
      if (log.isNotEmpty)
        'Reports listed: ${stats.total}  (finished ${stats.finished}, '
            'still open ${stats.open}, flagged ${stats.flagged})',
    ],
    sections: [
      ReportSection(
        heading: overviewHeading,
        headers: const ['Metric', 'Count'],
        columnWeights: const [3, 1],
        rows: [
          ['Total reports', total],
          // Split out because the two are handled differently: a non-resident
          // report has no account behind it, so it cannot be followed up in-app.
          ['Resident reports', total - nonResident],
          ['Non-resident reports', nonResident],
          ['Pending', pending],
          ['In progress', inProgress],
          ['Resolved', resolved],
          ['Flagged', flagged],
          ['Currently overdue', overdue],
        ],
      ),
      ReportSection(
        heading: performanceHeading,
        headers: const ['Metric', 'Value'],
        columnWeights: const [3, 2],
        rows: [
          ['Resolution rate', '${resolutionRate.toStringAsFixed(1)}%'],
          ['Average resolution time', avgLabel],
          ['SLA compliance (within 48 h)', '${slaCompliance.toStringAsFixed(1)}%'],
          if (log.isNotEmpty) ...[
            ['Average time to first response', dur(stats.timeToFirstResponse.average)],
            ['Median time to first response', dur(stats.timeToFirstResponse.median)],
            ['Average time to finish', dur(stats.timeToFinish.average)],
            ['Median time to finish', dur(stats.timeToFinish.median)],
            ['Fastest finish', extreme(stats.fastest)],
            ['Slowest finish', extreme(stats.slowest)],
          ],
        ],
      ),
      if (categories.isNotEmpty)
        ReportSection(
          heading: categoriesHeading,
          headers: const ['Category', 'Reports', '% of total'],
          columnWeights: const [3, 1, 1],
          rows: [
            for (final e in categories) [e.key, e.value, '${pct(e.value)}%'],
          ],
        ),
      if (stats.byResponder.isNotEmpty)
        ReportSection(
          heading: 'Reports by Responder',
          headers: const [
            'Responder',
            'Reports taken',
            'Finished',
            'Still open',
            'Average time to finish',
            'Fastest',
            'Slowest',
          ],
          columnWeights: const [4, 2, 2, 2, 3, 3, 3],
          excelWidths: const [28, 14, 10, 10, 22, 14, 14],
          rows: [
            for (final r in stats.byResponder)
              [
                r.name,
                r.taken,
                r.finished,
                r.stillOpen,
                dur(r.timeToFinish.average),
                dur(r.timeToFinish.min),
                dur(r.timeToFinish.max),
              ],
          ],
        ),
      ReportSection(
        heading: last7Heading,
        headers: const ['Date', 'Reports'],
        columnWeights: const [3, 1],
        rows: [
          for (var i = 0; i < 7; i++)
            [manilaDate(today.subtract(Duration(days: 6 - i))), last7Days[i]],
        ],
      ),
      if (log.isNotEmpty) _reportLogSection(log),
    ],
    footer: '$appName Incident Reporting System - Lipa City, Batangas',
  );
}

/// The one-row-per-report table. Excel keeps every column; Word shows the nine a
/// reader needs on a page (listed in [ReportSection.wordColumns]).
ReportSection _reportLogSection(List<ReportLogEntry> log) {
  double? minutes(Duration? d) =>
      d == null ? null : double.parse((d.inSeconds / 60).toStringAsFixed(2));
  String human(Duration? d) => d == null ? '' : humanDuration(d);

  return ReportSection(
    heading: 'All Reports',
    headers: const [
      'No.', //                           0
      'Report ID', //                     1
      'Reported by', //                   2
      'Reporter type', //                 3
      'Barangay', //                      4
      'Category', //                      5
      'Severity', //                      6
      'Status', //                        7
      'Reported (Philippine time)', //    8
      'First response at', //             9
      'Time to first response', //        10
      'Responder', //                     11
      'Dispatched at', //                 12
      'On scene at', //                   13
      'Finished at', //                   14
      'Time to finish', //                15
      'Outcome', //                       16
      'Minutes to first response', //     17
      'Minutes to finish', //             18
      'Still open for', //                19
      'Overdue', //                       20
      'Escalation level', //              21
    ],
    rows: [
      for (var i = 0; i < log.length; i++)
        [
          i + 1,
          log[i].shortId,
          log[i].reporterName,
          log[i].reporterIsResident ? 'Resident' : 'Walk-in',
          log[i].barangay,
          log[i].category,
          log[i].severityWord,
          log[i].statusLabel,
          formatManila(log[i].reportedAt),
          formatManila(log[i].firstResponseAt),
          human(log[i].timeToFirstResponse),
          log[i].responderName ?? '',
          formatManila(log[i].dispatchedAt),
          formatManila(log[i].onSceneAt),
          formatManila(log[i].finishedAt),
          human(log[i].timeToFinish),
          log[i].outcome,
          minutes(log[i].timeToFirstResponse),
          minutes(log[i].timeToFinish),
          human(log[i].openFor),
          log[i].overdue ? 'Yes' : 'No',
          log[i].escalationLevel,
        ],
    ],
    excelWidths: const [
      6, 12, 28, 13, 14, 24, 10, 12, 22, 22, 16, 28, 22, 22, 22, 16, 32, 14, 12, 16, 9, 10,
    ],
    wordColumns: const [0, 1, 2, 5, 6, 8, 11, 10, 16],
    columnWeights: const [1, 2, 4, 4, 2, 4, 4, 3, 5],
    wordFontSize: 16,
    note: 'Times are Philippine time. "Finished" means resolved or closed. '
        '"Time to first response" is from the report to the first time an official '
        'verified, assigned or dispatched it. A blank means that step has not '
        'happened, or happened before it was being recorded - nothing is estimated. '
        'Phone numbers, addresses, locations and report descriptions are not '
        'included.',
  );
}
