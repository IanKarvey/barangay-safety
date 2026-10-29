import 'package:flutter/material.dart';
import '../models/incident_model.dart';
import '../utils/constants.dart';
import '../l10n/app_strings.dart';
import '../utils/helpers.dart';
import 'severity_badge.dart';
import 'status_chip.dart';
import 'wait_timer.dart';
import '../widgets/app_text.dart';

class IncidentCard extends StatefulWidget {
  final IncidentModel incident;
  final VoidCallback? onTap;
  final bool showReporter;

  const IncidentCard({
    super.key,
    required this.incident,
    this.onTap,
    this.showReporter = false,
  });

  @override
  State<IncidentCard> createState() => _IncidentCardState();
}

class _IncidentCardState extends State<IncidentCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.975).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  Color get _severityAccent {
    switch (widget.incident.severityLevel) {
      case 1: return AppColors.severityCritical;
      case 2: return AppColors.severityHigh;
      case 3: return AppColors.severityMedium;
      default: return AppColors.severityLow;
    }
  }

  // Tint intensity scales with urgency: critical=6%, high=4.5%, medium=3%, low=2%
  double get _tintOpacity {
    switch (widget.incident.severityLevel) {
      case 1: return 0.060;
      case 2: return 0.045;
      case 3: return 0.030;
      default: return 0.018;
    }
  }

  // Shadow color opacity scales with urgency
  double get _shadowOpacity {
    switch (widget.incident.severityLevel) {
      case 1: return 0.18;
      case 2: return 0.12;
      case 3: return 0.07;
      default: return 0.04;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressController.forward(),
      onTapUp: (_) {
        _pressController.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _pressController.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Color.lerp(AppColors.surface, _severityAccent, _tintOpacity),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: [
              // Severity-colored ambient glow
              BoxShadow(
                color: _severityAccent.withValues(alpha: _shadowOpacity),
                blurRadius: 20,
                spreadRadius: -4,
                offset: const Offset(0, 6),
              ),
              // Base neutral shadow
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            // A Stack, not IntrinsicHeight + Row. The old layout asked the content
            // how tall it wanted to be BEFORE laying it out, and the text widgets
            // here (AppText -> AutoSizeText -> LayoutBuilder) cannot answer that
            // question: LayoutBuilder reports zero. So the card was measured as if
            // its text had no height, and everything past that — the location
            // line, the OVERDUE badge — was clipped off the bottom of every card.
            //
            // In a Stack the content lays out normally and sets the card's height;
            // the severity bar is pinned to the left edge and stretches to match.
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Top row: category + severity badge
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Hero(
                                  tag: 'incident_title_${widget.incident.id}',
                                  flightShuttleBuilder: (_, animation, __, ___, ____) =>
                                      FadeTransition(
                                        opacity: animation,
                                        child: Material(
                                          type: MaterialType.transparency,
                                          child: AppText(
                                            categoryLabel(context.s, widget.incident.category),
                                            style: const TextStyle(
                                              fontFamily: 'Poppins',
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.textPrimary,
                                              letterSpacing: -0.3,
                                              height: 1.2,
                                            ),
                                          ),
                                        ),
                                      ),
                                  child: Material(
                                    type: MaterialType.transparency,
                                    child: Text(
                                      categoryLabel(context.s, widget.incident.category),
                                      style: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                        letterSpacing: -0.3,
                                        height: 1.2,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Hero(
                                tag: 'incident_severity_${widget.incident.id}',
                                child: SeverityBadge(level: widget.incident.severityLevel),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),

                          // Description
                          Text(
                            widget.incident.description,
                            style: AppTextStyles.footnote.copyWith(height: 1.4),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 12),

                          // Status + time row
                          Row(
                            children: [
                              // Flagged on the card, not just inside the case:
                              // an official triaging a list needs to know there
                              // is no account behind this one — no notification
                              // will reach them, only a phone call.
                              if (widget.incident.isNonResidentReport) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    context.s.walkUpReport,
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.4,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                transitionBuilder: (child, anim) => FadeTransition(
                                  opacity: anim,
                                  child: ScaleTransition(
                                    scale: Tween<double>(begin: 0.82, end: 1.0)
                                        .animate(CurvedAnimation(
                                            parent: anim,
                                            curve: Curves.easeOutBack)),
                                    child: child,
                                  ),
                                ),
                                child: StatusChip(
                                  key: ValueKey(widget.incident.status),
                                  status: widget.incident.status,
                                ),
                              ),
                              const Spacer(),
                              Icon(Icons.access_time_rounded,
                                  size: 11, color: AppColors.textTertiary),
                              const SizedBox(width: 3),
                              Text(
                                timeAgo(widget.incident.createdAt),
                                style: AppTextStyles.caption.copyWith(
                                    color: AppColors.textTertiary),
                              ),
                            ],
                          ),

                          // Location
                          if (widget.incident.barangayName != null ||
                              widget.incident.address != null) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.location_on_rounded,
                                    size: 11, color: AppColors.textTertiary),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    widget.incident.barangayName ??
                                        widget.incident.address ??
                                        '',
                                    style: AppTextStyles.caption.copyWith(
                                        color: AppColors.textTertiary),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          // Reporter (officials view)
                          if (widget.showReporter &&
                              widget.incident.reporterName != null) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.person_outline_rounded,
                                    size: 11, color: AppColors.textTertiary),
                                const SizedBox(width: 4),
                                AppText(
                                  widget.incident.reporterName!,
                                  style: AppTextStyles.caption.copyWith(
                                      color: AppColors.textTertiary),
                                ),
                              ],
                            ),
                          ],

                          // SLA badge — pulsing overdue indicator
                          if (!widget.incident.isResolved &&
                              !widget.incident.isFlagged) ...[
                            const SizedBox(height: 8),
                            Builder(builder: (context) {
                              // Nobody has acted yet: a live, colour-coded
                              // timer from the first second, instead of a badge
                              // that appears once it is already late.
                              if (widget.incident.isUnanswered) {
                                return Align(
                                  alignment: Alignment.centerLeft,
                                  child: WaitTimerChip(
                                    submittedAt: widget.incident.createdAt,
                                  ),
                                );
                              }
                              final sla = slaStatus(widget.incident);
                              if (sla == 'ok') return const SizedBox.shrink();
                              final color = slaColor(sla);
                              return _SlaIndicator(
                                label: sla == 'overdue' ? 'OVERDUE' : 'SLOW',
                                elapsed: slaElapsedLabel(widget.incident),
                                color: color,
                                pulse: sla == 'overdue',
                              );
                            }),
                          ],

                          // Media indicators — no divider, just spacing
                          if (widget.incident.photoUrls.isNotEmpty ||
                              widget.incident.videoUrls.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                if (widget.incident.photoUrls.isNotEmpty) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.photo_rounded,
                                            size: 11,
                                            color: AppColors.primary),
                                        const SizedBox(width: 3),
                                        AppText(
                                          '${widget.incident.photoUrls.length}',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                if (widget.incident.videoUrls.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.play_circle_rounded,
                                            size: 11,
                                            color: AppColors.primary),
                                        const SizedBox(width: 3),
                                        AppText(
                                          '${widget.incident.videoUrls.length}',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 6,
                  child: Container(
                    width: 6,
                    decoration: BoxDecoration(
                      color: _severityAccent,
                      // Subtle gradient on the bar for depth
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          _severityAccent,
                          _severityAccent.withValues(alpha: 0.7),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── SLA pulsing badge ────────────────────────────────────────────────────────
class _SlaIndicator extends StatefulWidget {
  final String label;
  final String elapsed;
  final Color color;
  final bool pulse;

  const _SlaIndicator({
    required this.label,
    required this.elapsed,
    required this.color,
    required this.pulse,
  });

  @override
  State<_SlaIndicator> createState() => _SlaIndicatorState();
}

class _SlaIndicatorState extends State<_SlaIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 0.6).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    if (widget.pulse) _pulseCtrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: widget.pulse ? _pulseAnim : const AlwaysStoppedAnimation(1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.circular),
              border: Border.all(
                  color: widget.color.withValues(alpha: 0.3), width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timer_outlined, size: 10, color: widget.color),
                const SizedBox(width: 4),
                AppText(
                  widget.label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: widget.color,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 4),
                AppText(
                  '· ${widget.elapsed}',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color: widget.color.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
