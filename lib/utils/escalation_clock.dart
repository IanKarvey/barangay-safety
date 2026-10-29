/// The clock behind "this report has been waiting N minutes".
///
/// Everything here is a pure function of a duration, so the colours, the
/// countdown and the tier a report is in can be tested without a screen — and so
/// the dashboard, the resident's waiting card and the alert pop-up cannot drift
/// apart on what "yellow" means.
///
/// The database job (`escalate_unanswered_reports`, supabase/migration_2026_10_20
/// _three_features.sql) decides when a report is actually escalated, from the
/// server's clock. These helpers only DISPLAY the same rule: tier N is reached
/// at `step * N`, with [kDefaultEscalationStep] = 5 minutes in production.
library;

/// Production interval between tiers. The live value is the `step_seconds` row
/// in `escalation_settings` (changed to 30 s for a demo); the app reads it and
/// falls back to this when it cannot.
const Duration kDefaultEscalationStep = Duration(minutes: 5);

/// Tiers: 0 normal, 1 / 2 / 3 escalated. Level 3 is "Unattended / Last Resort".
const int kMaxEscalationLevel = 3;

/// Traffic-light colour for how long a report has waited.
///   green   under one step      (< 5 min)
///   yellow  one to two steps    (5 – 10 min)
///   orange  two to three steps  (10 – 15 min)
///   red     three steps or more (15 min and over)
enum WaitBand { green, yellow, orange, red }

WaitBand waitBandFor(
  Duration elapsed, {
  Duration step = kDefaultEscalationStep,
}) {
  if (elapsed < step) return WaitBand.green;
  if (elapsed < step * 2) return WaitBand.yellow;
  if (elapsed < step * 3) return WaitBand.orange;
  return WaitBand.red;
}

/// The tier a report SHOULD be in after waiting [elapsed] with no response.
/// Mirrors the SQL: `LEAST(3, floor(elapsed / step))`.
int escalationLevelFor(
  Duration elapsed, {
  Duration step = kDefaultEscalationStep,
}) {
  if (elapsed.isNegative || step <= Duration.zero) return 0;
  final level = elapsed.inMilliseconds ~/ step.inMilliseconds;
  return level > kMaxEscalationLevel ? kMaxEscalationLevel : level;
}

/// Time until the next tier, or null once the last one has been reached.
Duration? untilNextTier(
  Duration elapsed, {
  Duration step = kDefaultEscalationStep,
}) {
  if (step <= Duration.zero) return null;
  final level = escalationLevelFor(elapsed, step: step);
  if (level >= kMaxEscalationLevel) return null;
  final remaining = step * (level + 1) - elapsed;
  return remaining.isNegative ? Duration.zero : remaining;
}

/// `3:42`, or `1:02:09` once past the hour. Never negative: a phone whose clock
/// is a few seconds ahead of the server must not show "-0:03".
String formatClock(Duration d) {
  final total = d.isNegative ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

/// How much longer a tanod must wait before the volunteer button opens, or null
/// when it is open.
///
/// The hall staff get the first step (5 minutes) to answer a report nobody has
/// touched; only a TANOD is held back, and only while the report is untouched —
/// once someone at the hall has acted, a responder is what it needs. The
/// database enforces the same rule (`claim_incident`); this is what lets the
/// screen show the countdown instead of letting a tanod press and be refused.
Duration? volunteerLockRemaining({
  required bool tanod,
  required bool untouched,
  required Duration waited,
  Duration step = kDefaultEscalationStep,
}) {
  if (!tanod || !untouched) return null;
  final left = step - waited;
  return left > Duration.zero ? left : null;
}

/// How long a report has waited, by the SERVER's clock.
///
/// [serverOffset] is `serverNow - deviceNow`, measured once from the database
/// (`server_time()`); adding it to the device clock gives server time even on a
/// phone whose clock is minutes wrong, which matters because the tiers are
/// decided by the server and a timer that disagrees looks like a bug.
Duration waitedSince(
  DateTime submittedAt, {
  Duration serverOffset = Duration.zero,
  DateTime? deviceNow,
}) {
  final now = (deviceNow ?? DateTime.now()).add(serverOffset);
  final d = now.difference(submittedAt);
  return d.isNegative ? Duration.zero : d;
}
