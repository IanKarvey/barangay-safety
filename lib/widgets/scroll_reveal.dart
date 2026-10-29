import 'package:flutter/material.dart';

/// Animates its child into view (fade + slide from below) after [delay].
/// Wrap section headers, cards, or any key block with this for scroll-reveal feel.
///
/// Usage:
///   ScrollReveal(
///     delay: Duration(milliseconds: 120),
///     child: MyCard(),
///   )
class ScrollReveal extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final double slideY;
  final double slideX;
  final Duration duration;

  const ScrollReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.slideY = 0.07,
    this.slideX = 0.0,
    this.duration = const Duration(milliseconds: 420),
  });

  @override
  State<ScrollReveal> createState() => _ScrollRevealState();
}

class _ScrollRevealState extends State<ScrollReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: Offset(widget.slideX, widget.slideY),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
