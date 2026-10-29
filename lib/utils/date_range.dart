import '../l10n/app_strings.dart';

/// Reporting window shared by the analytics export and the incidents list.
///
/// Lives here rather than in either screen because both must agree: an official
/// who filters the incidents tab to 30 days and then exports a PDF covering all
/// time has been handed two different answers to the same question.
enum ReportRange {
  last7('7 days', 7),
  last30('30 days', 30),
  last90('90 days', 90),
  allTime('All time', null);

  const ReportRange(this.label, this.days);

  final String label;

  /// Null means unbounded.
  final int? days;

  /// Oldest instant included, or null for everything.
  ///
  /// Anchored to midnight rather than "now minus N×24h" so "7 days" means seven
  /// calendar days. Counting back by the hour makes a report run at 9am and
  /// again at 5pm cover different sets, which is indefensible in a document
  /// someone signs.
  DateTime? get cutoff {
    if (days == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days! - 1));
  }

  bool includes(DateTime when) {
    final from = cutoff;
    return from == null || !when.isBefore(from);
  }
}

extension ReportRangeL10n on ReportRange {
  String labelFor(AppStrings t) => switch (this) {
        ReportRange.last7 => t.rangeLast7,
        ReportRange.last30 => t.rangeLast30,
        ReportRange.last90 => t.rangeLast90,
        ReportRange.allTime => t.rangeAllTime,
      };
}
