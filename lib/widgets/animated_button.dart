import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../widgets/app_text.dart';

class AnimatedButton extends StatefulWidget {
  final bool isLoading;
  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double height;

  const AnimatedButton({
    super.key,
    required this.label,
    this.isLoading = false,
    this.onPressed,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
    this.height = 52,
  });

  @override
  State<AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<AnimatedButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    if (widget.isLoading) _ctrl.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant AnimatedButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLoading != oldWidget.isLoading) {
      widget.isLoading ? _ctrl.forward() : _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.backgroundColor ?? AppColors.primary;
    final fg = widget.foregroundColor ?? Colors.white;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width - 48;

        return AnimatedBuilder(
          animation: _anim,
          builder: (context, _) {
            final t = _anim.value;
            final pillSize = widget.height;
            final currentWidth = maxWidth - (maxWidth - pillSize) * t;
            final radius = 14.0 + (pillSize / 2 - 14.0) * t;

            return Center(
              child: SizedBox(
                width: currentWidth,
                height: widget.height,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.isLoading ? null : widget.onPressed,
                    borderRadius: BorderRadius.circular(radius),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: widget.onPressed == null && !widget.isLoading
                            ? bg.withValues(alpha: 0.5)
                            : bg,
                        borderRadius: BorderRadius.circular(radius),
                        boxShadow: [
                          BoxShadow(
                            color: bg.withValues(alpha: 0.35 * (1 - t * 0.4)),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: ScaleTransition(scale: anim, child: child),
                          ),
                          child: widget.isLoading
                              ? SizedBox(
                                  key: const ValueKey('loader'),
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: fg,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Row(
                                  key: ValueKey(widget.label),
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (widget.icon != null) ...[
                                      Icon(widget.icon, color: fg, size: 18),
                                      const SizedBox(width: 8),
                                    ],
                                    AppText(
                                      widget.label,
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: fg,
                                        letterSpacing: 0.1,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
