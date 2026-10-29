import 'dart:math' as math;

import '../models/response_metric.dart';
import 'manila_time.dart';

/// How a set of durations (in seconds) is summarised. All values are seconds;
/// null when there is nothing to summarise.
class DurationSummary {
  const DurationSummary({
    required this.count,
    this.average,
    this.median,
    this.min,
    this.max,
    this.p90,
  });

  static const empty = DurationSummary(count: 0);

  final int count;
  final double? average;
  final double? median;
  final double? min;
  final double? max;

  /// 90th percentile, nearest-rank: 9 in 10 reports were handled within this.
  final double? p90;
}

/// Median of an already-sorted list.
double _median(List<int> sorted) {
  final n = sorted.length;
  final mid = n ~/ 2;
  return n.isOdd ? sorted[mid].toDouble() : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Nearest-rank percentile of an already-sorted list: the smallest value with at
/// least [p] percent of the data at or below it. Chosen over interpolation
/// because it only ever reports a time that actually happened.
double percentileNearestRank(List<int> sorted, double p) {
  final rank = (p / 100 * sorted.length).ceil().clamp(1, sorted.length);
  return sorted[rank - 1].toDouble();
}

DurationSummary summarizeSeconds(Iterable<int?> values) {
  final v = values.whereType<int>().where((s) => s >= 0).toList()..sort();
  if (v.isEmpty) return DurationSummary.empty;
  final sum = v.fold<int>(0, (a, b) => a + b);
  return DurationSummary(
    count: v.length,
    average: sum / v.length,
    median: _median(v),
    min: v.first.toDouble(),
    max: v.last.toDouble(),
    p90: percentileNearestRank(v, 90),
  );
}

/// The manual process the system is compared against, from the brief: 30 to 60
/// minutes from report to dispatch.
const int kManualBaselineMinMinutes = 30;
const int kManualBaselineMaxMinutes = 60;

/// The headline numbers for a set of reports. One function builds them for the
/// dashboard AND the export, so the two cannot disagree.
class ResponseSummary {
  const ResponseSummary({
    required this.total,
    required this.answered,
    required this.unansweredNow,
    required this.firstSeen,
    required this.firstResponse,
    required this.dispatch,
    required this.travel,
    required this.resolve,
    required this.totalOpen,
    required this.within5,
    required this.within10,
    required this.within15,
    required this.reachedLevel1,
    required this.reachedLevel2,
    required this.reachedLevel3,
  });

  final int total;

  /// Reports with a recorded first action (the denominator for "answered within").
  final int answered;
  final int unansweredNow;

  final DurationSummary firstSeen;
  final DurationSummary firstResponse;
  final DurationSummary dispatch;
  final DurationSummary travel;
  final DurationSummary resolve;
  final DurationSummary totalOpen;

  /// How many ANSWERED reports were answered within 5 / 10 / 15 minutes.
  final int within5;
  final int within10;
  final int within15;

  /// Reports that reached AT LEAST that tier.
  final int reachedLevel1;
  final int reachedLevel2;
  final int reachedLevel3;

  int get escalated => reachedLevel1;

  /// Percent (0-100) of answered reports answered within the threshold; null
  /// when nothing has been answered yet, so the dashboard shows a dash instead
  /// of a misleading 0%.
  double? percentWithin(int count) =>
      answered == 0 ? null : count * 100 / answered;
  double? get percentWithin5 => percentWithin(within5);
  double? get percentWithin10 => percentWithin(within10);
  double? get percentWithin15 => percentWithin(within15);

  /// How much faster the system's median dispatch is than a manual baseline of
  /// [baselineMinutes], as a percent; null when no dispatches are recorded yet.
  /// Can be negative if the system is slower.
  double? dispatchImprovementVs(int baselineMinutes) {
    final m = dispatch.median;
    if (m == null) return null;
    return (1 - m / (baselineMinutes * 60)) * 100;
  }
}

ResponseSummary summarizeRows(Iterable<ResponseMetricRow> rows) {
  final list = rows.toList();
  int count(bool Function(ResponseMetricRow) f) => list.where(f).length;
  return ResponseSummary(
    total: list.length,
    answered: count((r) => r.isAnswered),
    unansweredNow: count((r) => r.isUnansweredNow),
    firstSeen: summarizeSeconds(list.map((r) => r.secsToFirstSeen)),
    firstResponse: summarizeSeconds(list.map((r) => r.secsToFirstResponse)),
    dispatch: summarizeSeconds(list.map((r) => r.secsToDispatch)),
    travel: summarizeSeconds(list.map((r) => r.secsTravel)),
    resolve: summarizeSeconds(list.map((r) => r.secsToResolve)),
    totalOpen: summarizeSeconds(list.map((r) => r.secsTotalOpen)),
    within5: count((r) => r.answeredWithin5 == true),
    within10: count((r) => r.answeredWithin10 == true),
    within15: count((r) => r.answeredWithin15 == true),
    reachedLevel1: count((r) => r.escalationLevel >= 1),
    reachedLevel2: count((r) => r.escalationLevel >= 2),
    reachedLevel3: count((r) => r.escalationLevel >= 3),
  );
}

/// Stats for one group (a barangay, a category, a severity).
class GroupStat {
  const GroupStat({
    required this.key,
    required this.summary,
  });

  final String key;
  final ResponseSummary summary;
}

/// Groups [rows] by [keyOf] and summarises each group. Sorted by key so the
/// dashboard and the export list groups in the same order.
List<GroupStat> groupSummaries(
  Iterable<ResponseMetricRow> rows,
  String Function(ResponseMetricRow) keyOf,
) {
  final groups = <String, List<ResponseMetricRow>>{};
  for (final r in rows) {
    groups.putIfAbsent(keyOf(r), () => []).add(r);
  }
  final keys = groups.keys.toList()..sort();
  return [
    for (final k in keys) GroupStat(key: k, summary: summarizeRows(groups[k]!)),
  ];
}

/// One point on the trend chart: a Manila calendar day and the median first
/// response (seconds) of reports submitted that day.
class TrendPoint {
  const TrendPoint(this.day, this.medianFirstResponseSecs, this.reports);

  /// `YYYY-MM-DD`, Philippine date.
  final String day;
  final double? medianFirstResponseSecs;
  final int reports;
}

List<TrendPoint> dailyTrend(Iterable<ResponseMetricRow> rows) {
  final byDay = <String, List<ResponseMetricRow>>{};
  for (final r in rows) {
    byDay.putIfAbsent(manilaDate(r.submittedAt), () => []).add(r);
  }
  final days = byDay.keys.toList()..sort();
  return [
    for (final d in days)
      TrendPoint(
        d,
        summarizeSeconds(byDay[d]!.map((r) => r.secsToFirstResponse)).median,
        byDay[d]!.length,
      ),
  ];
}

/// Largest value, for scaling a chart axis. Never zero.
double chartMax(Iterable<double?> values) {
  final m = values.whereType<double>().fold<double>(0, math.max);
  return m <= 0 ? 1 : m;
}
