import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../l10n/app_strings.dart';
import '../providers/language_provider.dart';
import '../utils/constants.dart';
import '../widgets/app_text.dart';

/// EN / TL switch.
///
/// Shows both options at once rather than a single "change language" button:
/// someone who cannot read the current language should be able to see the one
/// they want and tap it, without first understanding a menu label.
///
/// [onDark] adapts it for the coloured gradient headers.
class LanguageToggle extends StatelessWidget {
  final bool onDark;

  const LanguageToggle({super.key, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LanguageProvider>();
    final current = provider.language;

    final bg = onDark
        ? Colors.white.withValues(alpha: 0.14)
        : AppColors.background;
    final border = onDark
        ? Colors.white.withValues(alpha: 0.22)
        : AppColors.divider;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final lang in AppLanguage.values)
            _Segment(
              // "EN" / "TL" rather than full names — these read the same in
              // both languages and fit a header without truncating.
              label: lang.code.toUpperCase(),
              selected: current == lang,
              onDark: onDark,
              onTap: () {
                HapticFeedback.selectionClick();
                context.read<LanguageProvider>().setLanguage(lang);
              },
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final bool onDark;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.selected,
    required this.onDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? (onDark ? Colors.white : AppColors.primary)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 240),
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? (onDark ? AppColors.primary : Colors.white)
                : (onDark ? Colors.white70 : AppColors.textSecondary),
          ),
          child: AppText(label),
        ),
      ),
    );
  }
}
