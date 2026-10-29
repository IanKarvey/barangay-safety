import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/response_strings.dart';
import '../models/incident_model.dart';
import '../models/user_model.dart';
import '../services/server_clock.dart';
import '../utils/constants.dart';
import '../utils/escalation_clock.dart';

/// "I'm responding" — the button an official presses to take a report.
///
/// For a TANOD it starts out grey with a countdown, because the barangay hall
/// gets the first few minutes (5 in production) to answer a report nobody has
/// touched. When the countdown ends it turns red and can be pressed. Everyone
/// else — Secretary, Captain — can press it at once, and it is red from the
/// start. The database enforces the same rule, so a tanod cannot get around it
/// with a stale screen or a modified app.
class VolunteerButton extends StatefulWidget {
  const VolunteerButton({
    super.key,
    required this.incident,
    required this.user,
    required this.onPressed,
    this.busy = false,
    this.now,
  });

  final IncidentModel incident;
  final UserModel? user;
  final VoidCallback onPressed;
  final bool busy;

  /// Test hook: the current time (otherwise the server clock).
  final DateTime Function()? now;

  @override
  State<VolunteerButton> createState() => _VolunteerButtonState();
}

class _VolunteerButtonState extends State<VolunteerButton> {
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
    final rs = context.rs;
    final now = widget.now?.call() ?? ServerClock.now;
    final raw = now.difference(widget.incident.createdAt);
    final step = ServerClock.step;
    final left = volunteerLockRemaining(
      tanod: widget.user?.isTanod ?? false,
      untouched: widget.incident.isUnanswered,
      waited: raw.isNegative ? Duration.zero : raw,
      step: step,
    );
    final locked = left != null;

    const red = AppColors.error;
    final color = locked ? AppColors.textTertiary : red;
    final label = locked ? rs.volunteerOpensIn(formatClock(left)) : rs.imResponding;
    final hint = locked
        ? rs.volunteerLockedHint(rs.span(step))
        : (widget.user?.isTanod ?? false)
            ? rs.volunteerOpenHint
            : null;

    return Semantics(
      button: true,
      enabled: !locked && !widget.busy,
      label: hint == null ? label : '$label. $hint',
      child: GestureDetector(
        onTap: widget.busy
            ? null
            : locked
                ? () {
                    HapticFeedback.heavyImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(rs.claimTooEarly(formatClock(left)))),
                    );
                  }
                : widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: locked ? 0.10 : 0.12),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: color.withValues(alpha: locked ? 0.35 : 0.5)),
          ),
          child: Column(
            children: [
              if (widget.busy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              else
                Icon(
                  locked ? Icons.lock_clock_rounded : Icons.directions_run_rounded,
                  color: locked ? AppColors.textSecondary : red,
                  size: 26,
                ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: locked ? AppColors.textSecondary : red,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (hint != null) ...[
                const SizedBox(height: 4),
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
