import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/response_strings.dart';
import '../services/server_clock.dart';
import '../utils/escalation_clock.dart';

/// Colour for each [WaitBand]: green under 5 min, yellow 5–10, orange 10–15,
/// red after that.
Color waitBandColor(WaitBand band) => switch (band) {
      WaitBand.green => const Color(0xFF16A34A),
      WaitBand.yellow => const Color(0xFFCA8A04),
      WaitBand.orange => const Color(0xFFEA580C),
      WaitBand.red => const Color(0xFFDC2626),
    };

/// A live "this report has been waiting 3:42" pill that changes colour as the
/// wait grows.
///
/// It ticks once a second on its own, so a dashboard full of unanswered reports
/// keeps counting without the list being rebuilt. The count is measured from the
/// report's server timestamp using the server's clock ([ServerClock]).
///
/// Only meant for reports nobody has acted on — once an official responds the
/// timer's job is over and callers stop drawing it.
class WaitTimerChip extends StatefulWidget {
  const WaitTimerChip({
    super.key,
    required this.submittedAt,
    this.large = false,
    this.now,
  });

  final DateTime submittedAt;

  /// The bigger version used at the top of a report.
  final bool large;

  /// Test hook: the current time (otherwise the server clock).
  final DateTime Function()? now;

  @override
  State<WaitTimerChip> createState() => _WaitTimerChipState();
}

class _WaitTimerChipState extends State<WaitTimerChip> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    if (widget.now == null) {
      ServerClock.ensureSynced().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now?.call() ?? ServerClock.now;
    final waited = now.difference(widget.submittedAt);
    final elapsed = waited.isNegative ? Duration.zero : waited;
    final band = waitBandFor(elapsed, step: ServerClock.step);
    final color = waitBandColor(band);
    final size = widget.large ? 17.0 : 11.5;

    return Semantics(
      label: context.rs.waitedLabel(formatClock(elapsed)),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: widget.large ? 14 : 8,
          vertical: widget.large ? 8 : 3,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(widget.large ? 12 : 8),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: size + 2, color: color),
            SizedBox(width: widget.large ? 8 : 4),
            Text(
              context.rs.waitedLabel(formatClock(elapsed)),
              style: TextStyle(
                fontSize: size,
                fontWeight: FontWeight.w700,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
