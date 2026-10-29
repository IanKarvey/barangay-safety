import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../models/incident_model.dart';
import '../utils/constants.dart';
import '../l10n/app_strings.dart';
import '../widgets/app_text.dart';

/// One step in the response journey.
class _Stage {
  final String label;
  final String doneText;
  final String waitingText;
  final IconData icon;

  const _Stage({
    required this.label,
    required this.doneText,
    required this.waitingText,
    required this.icon,
  });
}

/// Resident-facing response tracker.
///
/// Parcel-tracking style, because that is the mental model people already
/// have: a labelled journey with timestamps, where you can see exactly what
/// has happened and what comes next. A status chip alone tells a resident
/// almost nothing — "In Progress" doesn't say whether anyone has actually
/// left the barangay hall.
///
/// Every stage is always shown, including ones not yet reached, so the
/// resident knows what the process is rather than discovering it one step at
/// a time.
class IncidentTracker extends StatelessWidget {
  final IncidentModel incident;

  const IncidentTracker({super.key, required this.incident});

  // Built per-call rather than held as a const list: the labels change with
  // the selected language, so they cannot be baked in at compile time.
  static List<_Stage> _stagesFor(AppStrings t) => <_Stage>[
        _Stage(
          label: t.stageSubmitted,
          doneText: t.stageSubmittedDesc,
          waitingText: t.stageSubmittedWait,
          icon: Icons.assignment_turned_in_rounded,
        ),
        _Stage(
          label: t.stageVerified,
          doneText: t.stageVerifiedDesc,
          waitingText: t.stageVerifiedWait,
          icon: Icons.verified_rounded,
        ),
        _Stage(
          label: t.stageAssigned,
          doneText: t.stageAssignedDesc,
          waitingText: t.stageAssignedWait,
          icon: Icons.person_pin_rounded,
        ),
        _Stage(
          label: t.stageResponding,
          doneText: t.stageRespondingDesc,
          waitingText: t.stageRespondingWait,
          icon: Icons.local_shipping_rounded,
        ),
        _Stage(
          label: t.stageOnScene,
          doneText: t.stageOnSceneDesc,
          waitingText: t.stageOnSceneWait,
          icon: Icons.place_rounded,
        ),
        _Stage(
          label: t.stageResolved,
          doneText: t.stageResolvedDesc,
          waitingText: t.stageResolvedWait,
          icon: Icons.check_circle_rounded,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    // A flagged report isn't on the normal journey — showing a half-finished
    // progress bar would imply help is still coming when it isn't.
    if (incident.isFlagged) return const _FlaggedNotice();

    final current = incident.stageIndex;
    final stages = _stagesFor(context.s);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TrackerHeader(incident: incident, currentStage: current),
        const SizedBox(height: 18),
        for (int i = 0; i < stages.length; i++)
          _StageRow(
            stage: stages[i],
            index: i,
            currentStage: current,
            isLast: i == stages.length - 1,
            timestamp: incident.timestampForStage(i),
            // Naming who is handling it turns an anonymous process into an
            // accountable one.
            detail: i == 2 ? incident.assignedToName : null,
          ),
      ],
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────
class _TrackerHeader extends StatelessWidget {
  final IncidentModel incident;
  final int currentStage;

  const _TrackerHeader({required this.incident, required this.currentStage});

  @override
  Widget build(BuildContext context) {
    final done = currentStage >= 5;
    final progress = (currentStage + 1) / 6;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (done ? AppColors.success : AppColors.primary)
            .withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (done ? AppColors.success : AppColors.primary)
              .withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                done ? Icons.check_circle_rounded : Icons.timelapse_rounded,
                size: 19,
                color: done ? AppColors.success : AppColors.primary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  done
                      ? context.s.statusResolved
                      : context.s.stepOf(currentStage + 1, 6),
                  style: AppTextStyles.bodySmall
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                done
                    ? context.s.elapsedTook(_humanDuration(incident.elapsed))
                    : context.s.elapsedSoFar(_humanDuration(incident.elapsed)),
                style: AppTextStyles.caption,
              ),
            ],
          ),
          const SizedBox(height: 11),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, value, __) => LinearProgressIndicator(
                value: value,
                minHeight: 7,
                backgroundColor: AppColors.divider,
                valueColor: AlwaysStoppedAnimation(
                    done ? AppColors.success : AppColors.primary),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 320.ms).slideY(begin: -0.15, end: 0);
  }
}

// ── One stage row ───────────────────────────────────────────────────────────
class _StageRow extends StatelessWidget {
  final _Stage stage;
  final int index;
  final int currentStage;
  final bool isLast;
  final DateTime? timestamp;
  final String? detail;

  const _StageRow({
    required this.stage,
    required this.index,
    required this.currentStage,
    required this.isLast,
    this.timestamp,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = index < currentStage;
    final isCurrent = index == currentStage;
    final isFuture = index > currentStage;

    final color = isFuture
        ? AppColors.textTertiary
        : (currentStage >= 5 ? AppColors.success : AppColors.primary);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rail: dot + connector
          Column(
            children: [
              _StageDot(
                icon: stage.icon,
                color: color,
                isDone: isDone,
                isCurrent: isCurrent,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2.5,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: isDone ? color : AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 13),

          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20, top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppText(
                          stage.label,
                          style: AppTextStyles.body.copyWith(
                            fontWeight:
                                isCurrent ? FontWeight.w700 : FontWeight.w600,
                            color: isFuture
                                ? AppColors.textSecondary
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (isCurrent) const _NowChip(),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isFuture ? stage.waitingText : stage.doneText,
                    style: AppTextStyles.caption,
                  ),
                  if (detail != null && !isFuture) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.badge_rounded,
                            size: 12, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: AppText(
                            detail!,
                            style: AppTextStyles.caption
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (timestamp != null && !isFuture) ...[
                    const SizedBox(height: 5),
                    Text(
                      DateFormat('MMM d, h:mm a').format(timestamp!),
                      style: AppTextStyles.caption.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: 90 + index * 80))
        .fadeIn(duration: 320.ms)
        .slideX(begin: 0.06, end: 0, curve: Curves.easeOutCubic);
  }
}

class _StageDot extends StatefulWidget {
  final IconData icon;
  final Color color;
  final bool isDone;
  final bool isCurrent;

  const _StageDot({
    required this.icon,
    required this.color,
    required this.isDone,
    required this.isCurrent,
  });

  @override
  State<_StageDot> createState() => _StageDotState();
}

class _StageDotState extends State<_StageDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (widget.isCurrent) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(_StageDot old) {
    super.didUpdateWidget(old);
    if (widget.isCurrent && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.isCurrent && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filled = widget.isDone || widget.isCurrent;

    return SizedBox(
      width: 38,
      height: 38,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pulse only on the live stage, so the eye lands on "what's
          // happening now" without reading anything.
          if (widget.isCurrent)
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                final t = _ctrl.value;
                return Opacity(
                  opacity: (1 - t) * 0.45,
                  child: Container(
                    width: 26 + t * 12,
                    height: 26 + t * 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: widget.color, width: 2),
                    ),
                  ),
                );
              },
            ),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: filled ? widget.color : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color: filled ? widget.color : AppColors.divider,
                width: 2,
              ),
            ),
            child: Icon(
              widget.isDone ? Icons.check_rounded : widget.icon,
              size: 15,
              color: filled ? Colors.white : AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _NowChip extends StatelessWidget {
  const _NowChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        context.s.now,
        style: AppTextStyles.caption.copyWith(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _FlaggedNotice extends StatelessWidget {
  const _FlaggedNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.flag_rounded, color: AppColors.error, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This report was flagged by the barangay and is not being '
              'processed. Contact the barangay hall if you believe this is a '
              'mistake.',
              style: AppTextStyles.caption,
            ),
          ),
        ],
      ),
    );
  }
}

/// "2h 14m" / "3d 5h" — readable at a glance, unlike a raw duration.
String _humanDuration(Duration d) {
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) {
    final m = d.inMinutes % 60;
    return m == 0 ? '${d.inHours}h' : '${d.inHours}h ${m}m';
  }
  final h = d.inHours % 24;
  return h == 0 ? '${d.inDays}d' : '${d.inDays}d ${h}h';
}
