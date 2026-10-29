import 'package:flutter/material.dart';

import '../l10n/response_strings.dart';
import '../utils/constants.dart';

/// The always-visible "Paano Mag-report? / How to Report" button that sits right
/// under the Report button on the resident home screen.
///
/// Made to be impossible to miss and easy to hit: high contrast (dark text on
/// white, a thick blue edge), 18 sp bold text that grows with the phone's font
/// setting, an icon AND words, and a tap area well over the 56 dp minimum.
class HowToReportButton extends StatelessWidget {
  const HowToReportButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = context.rs.tutorialButton;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 68),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: AppColors.primary, width: 2.5),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      height: 1.2,
                    ),
                  ),
                ),
                const Icon(Icons.help_outline_rounded, color: AppColors.primary, size: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
