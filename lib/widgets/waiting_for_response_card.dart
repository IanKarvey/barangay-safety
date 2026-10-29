import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/response_strings.dart';
import '../models/incident_model.dart';
import '../services/server_clock.dart';
import '../utils/constants.dart';
import '../utils/escalation_clock.dart';
import 'emergency_numbers_sheet.dart';
import 'wait_timer.dart';

/// What a resident sees on their report while nobody has responded yet:
/// "Report sent. Waiting for barangay response." with a live count of the wait,
/// the time to the next update, and — once the barangay has had the full three
/// steps — a big button to call for help.
///
/// Disappears the moment an official acts ([IncidentModel.isUnanswered] turns
/// false), because from then on the normal progress tracker tells the story.
class WaitingForResponseCard extends StatefulWidget {
  const WaitingForResponseCard({
    super.key,
    required this.incident,
    this.now,
    this.onCallForHelp,
  });

  final IncidentModel incident;

  /// Test hook: the current time (otherwise the server clock).
  final DateTime Function()? now;

  /// Test hook: replaces opening the numbers dialog.
  final VoidCallback? onCallForHelp;

  @override
  State<WaitingForResponseCard> createState() => _WaitingForResponseCardState();
}

class _WaitingForResponseCardState extends State<WaitingForResponseCard> {
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
    final step = ServerClock.step;
    final now = widget.now?.call() ?? ServerClock.now;
    final raw = now.difference(widget.incident.createdAt);
    final elapsed = raw.isNegative ? Duration.zero : raw;

    final band = waitBandFor(elapsed, step: step);
    final color = waitBandColor(band);

    // The server decides the tier; the clock only fills the gap before the next
    // realtime update arrives.
    final clockLevel = escalationLevelFor(elapsed, step: step);
    final level = widget.incident.escalationLevel > clockLevel
        ? widget.incident.escalationLevel
        : clockLevel;
    final next = untilNextTier(elapsed, step: step);
    final progress = next == null
        ? 1.0
        : 1 - (next.inMilliseconds / step.inMilliseconds).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.hourglass_top_rounded, color: color, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  rs.waitingTitle,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              WaitTimerChip(
                submittedAt: widget.incident.createdAt,
                large: true,
                now: widget.now,
              ),
              if (next != null)
                Text(
                  rs.nextUpdateIn(formatClock(next)),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          if (level >= 1) ...[
            const SizedBox(height: 12),
            Text(
              rs.escalationMessage(level),
              style: const TextStyle(
                  fontSize: 15, height: 1.35, color: AppColors.textPrimary),
            ),
          ],
          if (level >= 3) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                ),
                onPressed: widget.onCallForHelp ??
                    () => showEmergencyNumbers(
                          context,
                          barangayId: widget.incident.barangayId,
                        ),
                icon: const Icon(Icons.call_rounded, size: 26),
                label: Text(
                  rs.callForHelpNow,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
