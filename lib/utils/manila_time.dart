/// Philippine time for reports and exports.
///
/// The Philippines is UTC+8 all year with no daylight saving, so a fixed offset
/// is exact; there is no time-zone database to ship or to get out of date. The
/// device's own zone is deliberately NOT used: an export made from a laptop set
/// to another zone must still read in the time the barangay actually lived.
const Duration kManilaOffset = Duration(hours: 8);

DateTime _manila(DateTime t) => t.toUtc().add(kManilaOffset);

String _two(int n) => n.toString().padLeft(2, '0');

/// `YYYY-MM-DD HH:mm:ss` in Philippine time; empty for a missing time so a
/// blank stays blank in the export instead of becoming a made-up value.
String formatManila(DateTime? t) {
  if (t == null) return '';
  final m = _manila(t);
  return '${m.year.toString().padLeft(4, '0')}-${_two(m.month)}-${_two(m.day)} '
      '${_two(m.hour)}:${_two(m.minute)}:${_two(m.second)}';
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `Oct 19, 2026 · 9:38 AM` in Philippine time — the way a person reads a time,
/// for the screen. Exports use [formatManila] so every cell sorts and parses.
String formatManilaFriendly(DateTime? t) {
  if (t == null) return '';
  final m = _manila(t);
  final hour12 = m.hour % 12 == 0 ? 12 : m.hour % 12;
  final ampm = m.hour < 12 ? 'AM' : 'PM';
  return '${_months[m.month - 1]} ${m.day}, ${m.year} · $hour12:${_two(m.minute)} $ampm';
}

/// `YYYY-MM-DD`, Philippine date.
String manilaDate(DateTime t) {
  final m = _manila(t);
  return '${m.year.toString().padLeft(4, '0')}-${_two(m.month)}-${_two(m.day)}';
}

/// The UTC instant at which a Philippine calendar day starts — what a date
/// filter must send to the database so "20 October" means 20 October in Manila.
DateTime manilaDayStartUtc(int year, int month, int day) =>
    DateTime.utc(year, month, day).subtract(kManilaOffset);

/// `m:ss` (minutes may exceed 59); empty when unknown. "75:30" is 75 minutes
/// 30 seconds — easier to scan in a column than "1:15:30".
String formatMinSec(num? seconds) {
  if (seconds == null) return '';
  final total = seconds.round();
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${_two(s)}';
}

/// Minutes as a number with two decimals, for spreadsheets that sort and chart.
double? secondsToMinutes(num? seconds) =>
    seconds == null ? null : double.parse((seconds / 60).toStringAsFixed(2));
