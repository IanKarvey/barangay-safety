import 'package:flutter/material.dart';

/// Width at which the dashboard layouts stop being a phone column and become a
/// desktop grid.
///
/// Every widget here decides from the width it is *handed* (a `LayoutBuilder`),
/// never from the window, so a phone can never reach the wide branch and keeps
/// the exact layout it always had. That is the whole safety argument for using
/// these in screens shared with the mobile app.
const double kWideBreakpoint = 760;

/// Items flowed into two independent columns on a wide screen, one column on a
/// narrow one.
///
/// Two columns rather than a grid because the items are cards of different
/// heights (an overdue badge adds a row, a description wraps). A grid row is as
/// tall as its tallest cell, which leaves a hole beside every short card; two
/// independent columns pack tight. Items alternate left/right, so reading order
/// still runs top to bottom, newest first.
class TwoColumnFlow extends StatelessWidget {
  const TwoColumnFlow({
    super.key,
    required this.children,
    this.breakpoint = kWideBreakpoint,
    this.gap = 0,
  });

  final List<Widget> children;
  final double breakpoint;

  /// Horizontal space between the columns. Cards in this app carry their own
  /// 16px side margin, so the default of 0 already yields a 32px gutter.
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(children: children);
        }
        final left = <Widget>[];
        final right = <Widget>[];
        for (var i = 0; i < children.length; i++) {
          (i.isEven ? left : right).add(children[i]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Column(children: left)),
            if (gap > 0) SizedBox(width: gap),
            Expanded(child: Column(children: right)),
          ],
        );
      },
    );
  }
}

/// Two widgets side by side on a wide screen, stacked on a narrow one.
class SideBySide extends StatelessWidget {
  const SideBySide({
    super.key,
    required this.first,
    required this.second,
    this.breakpoint = kWideBreakpoint,
    this.gap = 16,
    this.firstFlex = 1,
    this.secondFlex = 1,
  });

  final Widget first;
  final Widget second;
  final double breakpoint;
  final double gap;
  final int firstFlex;
  final int secondFlex;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(children: [first, second]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: firstFlex, child: first),
            SizedBox(width: gap),
            Expanded(flex: secondFlex, child: second),
          ],
        );
      },
    );
  }
}
