import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../widgets/app_text.dart';

/// Bell icon button with an animated unread-count badge.
/// The badge number pops in/out with a scale+fade when it changes.
class AnimatedNotifBell extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  final Color? iconColor;

  const AnimatedNotifBell({
    super.key,
    required this.count,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          color: iconColor ?? AppColors.textPrimary,
          onPressed: onTap,
        ),
        // Positioned must be a DIRECT child of the Stack. It was previously
        // nested inside the AnimatedSwitcher, so its parent render object was
        // the switcher rather than the stack, and `Positioned.applyParentData`
        // threw `type 'ParentData' is not a subtype of type 'StackParentData'`
        // on every build — but only once `count > 0`, i.e. the moment a user
        // had an unread notification.
        //
        // Because the throw happened during build, Flutter rebuilt, threw
        // again, and looped: the main thread sat at ~97% with ~80k page faults
        // a second and the app was killed with "isn't responding". The bell is
        // in all three role headers, which is why every dashboard froze.
        Positioned(
          right: 6,
          top: 6,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: count > 0
                ? _Badge(
                    key: ValueKey(count > 9 ? '9+' : '$count'),
                    count: count,
                  )
                : const SizedBox.shrink(key: ValueKey('empty')),
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final int count;
  const _Badge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        color: AppColors.error,
        shape: BoxShape.circle,
      ),
      child: AppText(
        count > 9 ? '9+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
