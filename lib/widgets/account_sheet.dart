import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../providers/auth_provider.dart';
import '../providers/incident_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/responder_location_provider.dart';
import '../utils/constants.dart';
import '../widgets/app_text.dart';

/// The official's own account menu.
///
/// Officials and superadmins previously had no route to their own profile at
/// all — the dashboard header offered a heat map, analytics, an audit log and
/// a logout button, and nothing else. A captain who mistyped their phone
/// number on signup had no way to fix it from inside the app, while every
/// resident did.
///
/// Logout moved in here rather than staying a seventh icon in a header row
/// that was already overflowing on narrow phones.
Future<void> showAccountSheet(BuildContext context) {
  final user = context.read<AuthProvider>().user;

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetCtx) {
      final t = sheetCtx.s;

      // Every tile pops the sheet first, then navigates on the parent's
      // Navigator — pushing from a context that is about to be disposed
      // leaves the route stack pointing at a dead element.
      void go(String route) {
        Navigator.pop(sheetCtx);
        Navigator.pushNamed(context, route);
      }

      return Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
            0, 10, 0, MediaQuery.of(sheetCtx).padding.bottom + 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textTertiary.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: AppText(
                  user == null || user.fullName.isEmpty
                      ? '?'
                      : user.fullName.trim()[0].toUpperCase(),
                  style: AppTextStyles.heading3
                      .copyWith(color: AppColors.primary),
                ),
              ),
              title: AppText(
                user?.fullName ?? '—',
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
              ),
              subtitle: AppText(
                [
                  if (user?.position != null) UserPosition.label(user!.position),
                  if (user?.barangayName != null) user!.barangayName!,
                ].join(' · '),
                style: AppTextStyles.bodySmall,
              ),
            ),
            const Divider(height: 18),
            _tile(
              icon: Icons.person_rounded,
              color: AppColors.primary,
              label: t.editProfile,
              onTap: () => go('/edit-profile'),
            ),
            // §2 — superadmin only. Emergency routing depends on these points,
            // so the control sits with the one account responsible city-wide
            // rather than with each barangay editing its neighbours.
            if (user?.isSuperAdmin == true)
              _tile(
                icon: Icons.my_location_rounded,
                color: AppColors.warning,
                label: t.barangayCoordinates,
                onTap: () => go('/barangay-coordinates'),
              ),
            _tile(
              icon: Icons.help_rounded,
              color: AppColors.textSecondary,
              label: t.helpSupport,
              onTap: () => go('/help-support'),
            ),
            _tile(
              icon: Icons.info_rounded,
              color: AppColors.textSecondary,
              label: t.about,
              onTap: () => go('/about'),
            ),
            _tile(
              icon: Icons.privacy_tip_rounded,
              color: AppColors.textSecondary,
              label: t.privacyNotice,
              onTap: () => go('/privacy'),
            ),
            const Divider(height: 18),
            _tile(
              icon: Icons.logout_rounded,
              color: AppColors.error,
              label: t.logout,
              onTap: () async {
                Navigator.pop(sheetCtx);
                await _signOut(context);
              },
            ),
          ],
        ),
      );
    },
  );
}

Widget _tile({
  required IconData icon,
  required Color color,
  required String label,
  required VoidCallback onTap,
}) =>
    ListTile(
      leading: Icon(icon, color: color, size: 22),
      title: AppText(label, style: AppTextStyles.body),
      trailing: const Icon(Icons.chevron_right_rounded,
          size: 20, color: AppColors.textTertiary),
      onTap: onTap,
    );

/// Sign-out teardown, in one place.
///
/// The order matters: location sharing is cleared *before* the session goes,
/// because clearing it is a write that needs the session. A killed session
/// with `is_sharing_location = true` leaves a frozen pin that a reporter reads
/// as a responder still on the way.
Future<void> _signOut(BuildContext context) async {
  await context.read<ResponderLocationProvider>().resetForLogout();
  if (!context.mounted) return;
  context.read<IncidentProvider>().resetForLogout();
  context.read<NotificationProvider>().unsubscribe();
  await context.read<AuthProvider>().signOut();
  if (context.mounted) {
    Navigator.pushReplacementNamed(context, '/login');
  }
}
