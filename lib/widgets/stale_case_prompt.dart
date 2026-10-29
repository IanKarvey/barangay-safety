import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../l10n/app_strings.dart';
import '../models/incident_model.dart';
import '../providers/auth_provider.dart';
import '../providers/incident_provider.dart';
import '../utils/constants.dart';
import '../utils/helpers.dart';
import '../utils/stale_cases.dart';
import '../widgets/app_text.dart';

/// §6 — asks about cases that have gone quiet.
///
/// Deliberately a prompt on the dashboard rather than a push notification.
/// The spec offered either; a card wins here because the answer requires
/// judgement ("is this actually finished?") and the person is already in the
/// app with the case in front of them. A notification fired at a tanod mid-shift
/// gets swiped away, and swiping away is indistinguishable from "still active".
///
/// Shows one case at a time — the longest-forgotten. A list of six stale cases
/// is a chore to be closed; one question is a thing to be answered.
class StaleCasePrompt extends StatelessWidget {
  final VoidCallback onResolved;

  const StaleCasePrompt({super.key, required this.onResolved});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final incidents = context.watch<IncidentProvider>().incidents;
    final stale = StaleCases.forUser(user, incidents);

    if (stale.isEmpty) return const SizedBox.shrink();

    final incident = stale.first;
    final days = StaleCases.daysSince(incident);
    final t = context.s;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.help_outline_rounded,
                  size: 18, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: AppText(
                  t.staleCaseTitle,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.warning,
                  ),
                ),
              ),
              if (stale.length > 1)
                Text('+${stale.length - 1}', style: AppTextStyles.caption),
            ],
          ),
          const SizedBox(height: 8),
          AppText(
            '${categoryLabel(t, incident.category)} — ${t.staleCaseBody(days)}',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Action(
                  label: t.markResolved,
                  icon: Icons.check_circle_rounded,
                  color: AppColors.success,
                  onTap: () => _resolve(context, incident),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Action(
                  label: t.stillActive,
                  icon: Icons.schedule_rounded,
                  color: AppColors.textSecondary,
                  onTap: () => _stillActive(context, incident),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _resolve(BuildContext context, IncidentModel incident) async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;

    HapticFeedback.mediumImpact();
    final ok = await context.read<IncidentProvider>().updateStatus(
          incident.id,
          'resolved',
          officialId: user.id,
          // Marked from the prompt rather than the manage screen, so the notes
          // say where it came from — otherwise the audit trail shows a
          // resolution with no explanation attached.
          resolutionNotes: 'Confirmed resolved from the stale-case check.',
        );
    if (!context.mounted) return;
    if (ok) {
      showSuccessSnackbar(context, context.s.caseMarkedResolved);
      onResolved();
    }
  }

  Future<void> _stillActive(BuildContext context, IncidentModel incident) async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;

    HapticFeedback.selectionClick();
    await context.read<IncidentProvider>().confirmStillActive(
          incident.id,
          officialId: user.id,
        );
    if (!context.mounted) return;
    showSuccessSnackbar(context, context.s.staleCaseSnoozed);
  }
}

class _Action extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _Action({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: AppText(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
