import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../utils/constants.dart';
import '../widgets/app_text.dart';

class LoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final Widget child;
  final String? message;

  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Container(
            color: Colors.black.withValues(alpha: 0.3),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: AppColors.primary),
                    if (message != null) ...[
                      const SizedBox(height: 16),
                      AppText(message!, style: AppTextStyles.body),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon — bounces in with scale + fade
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 44,
                color: AppColors.textSecondary.withValues(alpha: 0.45),
              ),
            )
                .animate()
                .fadeIn(duration: 400.ms, curve: Curves.easeOut)
                .scale(
                  begin: const Offset(0.6, 0.6),
                  end: const Offset(1.0, 1.0),
                  duration: 500.ms,
                  curve: Curves.easeOutBack,
                ),

            const SizedBox(height: 20),

            // Title — slides up + fades in
            AppText(
              title,
              style: AppTextStyles.heading3.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            )
                .animate(delay: 120.ms)
                .fadeIn(duration: 350.ms, curve: Curves.easeOut)
                .slideY(begin: 0.3, end: 0, duration: 350.ms, curve: Curves.easeOutCubic),

            if (subtitle != null) ...[
              const SizedBox(height: 8),
              AppText(
                subtitle!,
                style: AppTextStyles.bodySmall,
                textAlign: TextAlign.center,
              )
                  .animate(delay: 200.ms)
                  .fadeIn(duration: 300.ms, curve: Curves.easeOut)
                  .slideY(begin: 0.2, end: 0, duration: 300.ms, curve: Curves.easeOutCubic),
            ],

            if (action != null) ...[
              const SizedBox(height: 24),
              action!
                  .animate(delay: 280.ms)
                  .fadeIn(duration: 300.ms, curve: Curves.easeOut)
                  .slideY(begin: 0.2, end: 0, duration: 300.ms, curve: Curves.easeOutCubic),
            ],
          ],
        ),
      ),
    );
  }
}
