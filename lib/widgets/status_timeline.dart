import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../utils/constants.dart';
import '../utils/helpers.dart';
import '../l10n/app_strings.dart';

/// Animated status timeline — dots bounce in, lines draw down, labels fade in.
class StatusTimeline extends StatelessWidget {
  final String currentStatus;

  const StatusTimeline({super.key, required this.currentStatus});

  static const _stages = ['pending', 'in_progress', 'resolved'];

  @override
  Widget build(BuildContext context) {
    final currentIdx = _stages.indexOf(currentStatus);

    return Column(
      children: _stages.asMap().entries.map((entry) {
        final idx = entry.key;
        final stage = entry.value;
        final isCompleted = idx < currentIdx;
        final isCurrent = idx == currentIdx;
        final isActive = idx <= currentIdx;
        final color = isActive ? statusColor(stage) : AppColors.divider;
        final isLast = idx == _stages.length - 1;

        // Stagger: each step's group starts 260ms after the previous
        final base = idx * 260;
        final dotDelay = Duration(milliseconds: base);
        final textDelay = Duration(milliseconds: base + 90);
        final lineDelay = Duration(milliseconds: base + 160);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Left column: dot + connector ──────────────────────────
            SizedBox(
              width: 28,
              child: Column(
                children: [
                  // Dot with optional pulse ring
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Pulsing glow ring for the current step
                        if (isCurrent)
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color.withValues(alpha: 0.22),
                            ),
                          )
                              .animate(onPlay: (c) => c.repeat(reverse: true))
                              .scale(
                                begin: const Offset(0.85, 0.85),
                                end: const Offset(1.3, 1.3),
                                duration: const Duration(milliseconds: 1100),
                                curve: Curves.easeInOut,
                              )
                              .fadeIn(duration: const Duration(milliseconds: 600)),

                        // Main dot
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: isActive ? color : Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(color: color, width: 2),
                            boxShadow: isCurrent
                                ? [
                                    BoxShadow(
                                      color: color.withValues(alpha: 0.4),
                                      blurRadius: 10,
                                      spreadRadius: 1,
                                    )
                                  ]
                                : [],
                          ),
                          child: isCompleted
                              ? const Icon(Icons.check_rounded,
                                  size: 13, color: Colors.white)
                              : isCurrent
                                  ? Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white
                                            .withValues(alpha: 0.9),
                                      ),
                                    )
                                  : null,
                        )
                            .animate(delay: dotDelay)
                            .scale(
                              begin: const Offset(0.0, 0.0),
                              end: const Offset(1.0, 1.0),
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOutBack,
                            )
                            .fadeIn(duration: const Duration(milliseconds: 280)),
                      ],
                    ),
                  ),

                  // Connector line — draws down from top
                  if (!isLast)
                    ClipRect(
                      child: Container(
                        width: 2,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isActive ? color : AppColors.divider,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      )
                          .animate(delay: lineDelay)
                          .slideY(
                            begin: -1.0,
                            end: 0.0,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          ),
                    ),
                ],
              ),
            ),

            const SizedBox(width: 14),

            // ── Right column: label + sub-label ───────────────────────
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: isLast ? 0 : 20,
                  top: 2,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusLabelFor(context.s, stage),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: isCurrent
                            ? FontWeight.w700
                            : isCompleted
                                ? FontWeight.w500
                                : FontWeight.w400,
                        color: isActive
                            ? AppColors.textPrimary
                            : AppColors.textTertiary,
                      ),
                    )
                        .animate(delay: textDelay)
                        .fadeIn(duration: const Duration(milliseconds: 300))
                        .slideX(
                          begin: 0.12,
                          end: 0,
                          duration: const Duration(milliseconds: 360),
                          curve: Curves.easeOutCubic,
                        ),

                    if (isCurrent)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: color,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Current status',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: color,
                              ),
                            ),
                          ],
                        ),
                      )
                          .animate(
                              delay: Duration(
                                  milliseconds: textDelay.inMilliseconds + 100))
                          .fadeIn(duration: const Duration(milliseconds: 280)),

                    if (isCompleted)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          'Completed',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: color.withValues(alpha: 0.7),
                          ),
                        ),
                      )
                          .animate(
                              delay: Duration(
                                  milliseconds: textDelay.inMilliseconds + 60))
                          .fadeIn(duration: const Duration(milliseconds: 250)),
                  ],
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}
