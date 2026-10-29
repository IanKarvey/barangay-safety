import '../../utils/notification_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../models/notification_model.dart';
import '../../providers/notification_provider.dart';
import '../../utils/constants.dart';
import '../../l10n/app_strings.dart';
import '../../utils/helpers.dart';
import '../../widgets/widgets.dart';
import '../../widgets/app_text.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred to after the first frame — load() calls notifyListeners()
    // synchronously, which throws "setState() called during build" if fired
    // while this screen's own initial build is still in progress.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(context.s.notifications),
        actions: [
          Consumer<NotificationProvider>(
            builder: (context, provider, _) {
              if (provider.unreadCount == 0) return const SizedBox.shrink();
              return TextButton(
                onPressed: provider.markAllRead,
                child: Text(context.s.markAllRead),
              );
            },
          ),
        ],
      ),
      body: Consumer<NotificationProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const NotificationListShimmer();
          }

          if (provider.notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _BellSwayIcon()
                      .animate()
                      .fadeIn(duration: 400.ms)
                      .scale(
                          begin: const Offset(0.6, 0.6),
                          end: const Offset(1, 1),
                          duration: 500.ms,
                          curve: Curves.easeOutBack),
                  const SizedBox(height: 12),
                  AppText(
                    'No notifications yet',
                    style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                  ).animate(delay: 100.ms).fadeIn(duration: 300.ms).slideY(begin: 0.3),
                  const SizedBox(height: 4),
                  Text(
                    'You\'ll be notified about status updates\nand important activity here.',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
                    textAlign: TextAlign.center,
                  ).animate(delay: 180.ms).fadeIn(duration: 300.ms).slideY(begin: 0.2),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: provider.load,
            // Capped and centred: on a desktop the list otherwise runs 1300px
            // wide with small text at both ends of every row.
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: provider.notifications.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final n = provider.notifications[index];

                void dismiss() {
                  provider.dismiss(n.id);
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(context.s.notificationCleared),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );
                }

                return Dismissible(
                  key: ValueKey(n.id),
                  direction: DismissDirection.endToStart,
                  background: Container(color: Colors.transparent),
                  secondaryBackground: const _DismissBackground(),
                  onDismissed: (_) => dismiss(),
                  child: _NotificationTile(
                    notification: n,
                    onDismiss: dismiss,
                    onTap: () {
                      if (!n.isRead) provider.markRead(n.id);
                      // Every type now lands somewhere it can be acted on —
                      // an ID sent back for a retake opens the upload screen,
                      // not nothing. See notificationTargetFor.
                      final target = notificationTargetFor(context, n);
                      if (target != null) {
                        Navigator.pop(context);
                        Navigator.pushNamed(
                          context,
                          target.route,
                          arguments: target.arguments,
                        );
                      }
                    },
                  ),
                )
                    .animate(delay: Duration(milliseconds: 40 * index))
                    .fadeIn(duration: 300.ms)
                    .slideX(
                      begin: 0.07,
                      end: 0,
                      duration: 350.ms,
                      curve: Curves.easeOutCubic,
                    );
              },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Swipe-left dismiss background ───────────────────────────────────────────────
class _DismissBackground extends StatelessWidget {
  const _DismissBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            AppColors.error.withValues(alpha: 0.0),
            AppColors.error.withValues(alpha: 0.88),
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_rounded, color: Colors.white, size: 22),
          SizedBox(height: 3),
          Text(
            'Remove',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Notification tile ────────────────────────────────────────────────────────────
class _NotificationTile extends StatefulWidget {
  final NotificationModel notification;
  final VoidCallback onTap;

  /// Removes the notification. Shown as a button on wide screens, where there is
  /// no way to discover a swipe.
  final VoidCallback? onDismiss;

  const _NotificationTile({
    required this.notification,
    required this.onTap,
    this.onDismiss,
  });

  @override
  State<_NotificationTile> createState() => _NotificationTileState();
}

class _NotificationTileState extends State<_NotificationTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  static _NotifMeta _meta(String type) {
    switch (type) {
      case 'status_change':
        return _NotifMeta(icon: Icons.autorenew_rounded, color: AppColors.primary);
      case 'new_critical':
        return _NotifMeta(icon: Icons.warning_rounded, color: AppColors.error);
      case 'assigned':
        return _NotifMeta(
            icon: Icons.person_add_rounded, color: const Color(0xFF5856D6));
      case 'comment':
        return _NotifMeta(icon: Icons.chat_bubble_rounded, color: AppColors.success);
      // A report nobody has answered in time — see
      // supabase/migration_2026_10_15_escalation.sql.
      case 'escalation':
        return _NotifMeta(icon: Icons.trending_up_rounded, color: AppColors.warning);
      // The resident's side of the same escalation: "officials are busy",
      // "please call these numbers", "still waiting".
      case 'escalation_resident':
        return _NotifMeta(icon: Icons.hourglass_top_rounded, color: AppColors.warning);
      // "<role> <name> is now responding" — to the resident, and to the officials
      // who had been alerted.
      case 'responder_update':
      case 'responder_taken':
        return _NotifMeta(icon: Icons.directions_run_rounded, color: AppColors.success);
      default:
        return _NotifMeta(icon: Icons.notifications_rounded, color: AppColors.primary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _meta(widget.notification.type);
    final isUnread = !widget.notification.isRead;

    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isUnread
                ? AppColors.primary.withValues(alpha: 0.05)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: isUnread
                  ? AppColors.primary.withValues(alpha: 0.2)
                  : AppColors.divider,
              width: isUnread ? 1.2 : 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon bubble
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: m.color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(m.icon, color: m.color, size: 20),
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: AppText(
                            widget.notification.title,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              fontWeight:
                                  isUnread ? FontWeight.w700 : FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (isUnread)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.notification.body,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Text(
                          timeAgo(widget.notification.createdAt),
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textTertiary),
                        ),
                        const Spacer(),
                        // "Swipe to remove" means nothing to someone with a
                        // mouse, so on a desktop-width screen it is a button.
                        if (MediaQuery.sizeOf(context).width >= 700 &&
                            widget.onDismiss != null)
                          TextButton.icon(
                            onPressed: widget.onDismiss,
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              foregroundColor: AppColors.textSecondary,
                              // Family and weight restated: a ButtonStyle's textStyle
                              // replaces the theme's instead of merging with it.
                              textStyle: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            icon: const Icon(Icons.close_rounded, size: 14),
                            label: const Text('Remove'),
                          )
                        else ...[
                          Text(
                            'Swipe to remove',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 10,
                              color:
                                  AppColors.textTertiary.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.chevron_left_rounded,
                            size: 12,
                            color: AppColors.textTertiary.withValues(alpha: 0.5),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotifMeta {
  final IconData icon;
  final Color color;
  const _NotifMeta({required this.icon, required this.color});
}

// ── Swaying bell for empty state ─────────────────────────────────────────────
class _BellSwayIcon extends StatefulWidget {
  const _BellSwayIcon();

  @override
  State<_BellSwayIcon> createState() => _BellSwayIconState();
}

class _BellSwayIconState extends State<_BellSwayIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _sway;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _sway = Tween<double>(begin: -0.12, end: 0.12).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _sway,
      builder: (_, __) => Transform.rotate(
        angle: _sway.value,
        alignment: Alignment.topCenter,
        child: const Icon(
          Icons.notifications_none_rounded,
          size: 56,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}
