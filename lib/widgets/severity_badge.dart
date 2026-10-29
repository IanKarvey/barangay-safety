import 'package:flutter/material.dart';
import '../utils/helpers.dart';
import '../widgets/app_text.dart';

class SeverityBadge extends StatelessWidget {
  final int level;
  final bool compact;

  const SeverityBadge({super.key, required this.level, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final color = severityColor(level);
    final label = severityLabel(level);

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(100),
        ),
        child: AppText(
          'L$level',
          style: TextStyle(
            fontFamily: 'Poppins',
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(100),
      ),
      child: AppText(
        label,
        style: TextStyle(
          fontFamily: 'Poppins',
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}
