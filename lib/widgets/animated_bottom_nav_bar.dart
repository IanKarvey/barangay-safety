import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/constants.dart';
import '../widgets/app_text.dart';

class AnimatedNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const AnimatedNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

class AnimatedBottomNavBar extends StatefulWidget {
  final int currentIndex;
  final void Function(int) onTap;
  final List<AnimatedNavItem> items;

  const AnimatedBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  State<AnimatedBottomNavBar> createState() => _AnimatedBottomNavBarState();
}

class _AnimatedBottomNavBarState extends State<AnimatedBottomNavBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late double _fromIndex;
  late double _toIndex;

  @override
  void initState() {
    super.initState();
    _fromIndex = widget.currentIndex.toDouble();
    _toIndex = widget.currentIndex.toDouble();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
  }

  @override
  void didUpdateWidget(covariant AnimatedBottomNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      // Start from wherever the pill currently is
      _fromIndex = _currentAnimatedIndex;
      _toIndex = widget.currentIndex.toDouble();
      _ctrl.forward(from: 0);
    }
  }

  double get _currentAnimatedIndex {
    final curve = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    return _fromIndex + (_toIndex - _fromIndex) * curve.value;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final totalWidth = constraints.maxWidth;
              final tabWidth = totalWidth / widget.items.length;
              final pillPadding = tabWidth * 0.14;
              final pillWidth = tabWidth - pillPadding * 2;

              return AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  final t = CurvedAnimation(
                    parent: _ctrl,
                    curve: Curves.easeOutBack,
                  ).value;
                  final animatedIndex = _fromIndex + (_toIndex - _fromIndex) * t;
                  final pillLeft = animatedIndex * tabWidth + pillPadding;

                  return Stack(
                    children: [
                      // ── Sliding pill ──────────────────────────────────────
                      Positioned(
                        left: pillLeft,
                        top: 8,
                        bottom: 8,
                        width: pillWidth,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),

                      // ── Tab buttons ───────────────────────────────────────
                      Row(
                        children: widget.items.asMap().entries.map((entry) {
                          final i = entry.key;
                          final item = entry.value;
                          final isActive = i == widget.currentIndex;

                          return Expanded(
                            child: GestureDetector(
                              onTap: () {
                                if (i != widget.currentIndex) {
                                  HapticFeedback.selectionClick();
                                }
                                widget.onTap(i);
                              },
                              behavior: HitTestBehavior.opaque,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 220),
                                    switchInCurve: Curves.easeOutBack,
                                    transitionBuilder: (child, anim) => ScaleTransition(
                                      scale: anim,
                                      child: FadeTransition(opacity: anim, child: child),
                                    ),
                                    child: Icon(
                                      isActive ? item.activeIcon : item.icon,
                                      key: ValueKey('${i}_$isActive'),
                                      color: isActive
                                          ? AppColors.primary
                                          : AppColors.textTertiary,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOutCubic,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 10,
                                      fontWeight: isActive
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: isActive
                                          ? AppColors.primary
                                          : AppColors.textTertiary,
                                    ),
                                    child: AppText(item.label),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
