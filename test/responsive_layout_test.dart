import 'package:barangay_safety_app/widgets/responsive_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _box(String key, double height) => SizedBox(
      key: ValueKey(key),
      height: height,
      child: const SizedBox.expand(),
    );

Future<void> _pump(WidgetTester tester, double width, Widget child) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
  );
}

Offset _at(WidgetTester tester, String key) =>
    tester.getTopLeft(find.byKey(ValueKey(key)));

void main() {
  group('TwoColumnFlow', () {
    Widget flow() => TwoColumnFlow(
          children: [
            _box('a', 100),
            _box('b', 40),
            _box('c', 70),
            _box('d', 70),
          ],
        );

    testWidgets('a phone width stays a single column, in order', (tester) async {
      await _pump(tester, 400, flow());

      final a = _at(tester, 'a'), b = _at(tester, 'b'), c = _at(tester, 'c');
      expect(b.dx, a.dx, reason: 'same left edge — one column');
      expect(b.dy, greaterThan(a.dy));
      expect(c.dy, greaterThan(b.dy));
    });

    testWidgets('a desktop width splits into two columns', (tester) async {
      await _pump(tester, 1300, flow());

      final a = _at(tester, 'a'), b = _at(tester, 'b');
      expect(b.dx, greaterThan(a.dx), reason: 'b sits to the right of a');
      expect(b.dy, a.dy, reason: 'both columns start at the top');
    });

    testWidgets('columns pack independently, not row by row', (tester) async {
      // a is 100 tall, b is 40 tall. In a grid, c would wait for a's row to
      // finish. In independent columns, c goes under a (left) and d under b
      // (right), so d lands HIGHER than c — the reason for choosing this.
      await _pump(tester, 1300, flow());

      final c = _at(tester, 'c'), d = _at(tester, 'd');
      expect(d.dx, greaterThan(c.dx));
      expect(d.dy, lessThan(c.dy));
    });

    testWidgets('the breakpoint is on the width handed to it, not the window',
        (tester) async {
      // A wide window, but the widget is squeezed into 400px — as the phone
      // layout would be. It must stay a single column.
      await _pump(tester, 1300, SizedBox(width: 400, child: flow()));

      expect(_at(tester, 'b').dx, _at(tester, 'a').dx);
    });
  });

  group('SideBySide', () {
    Widget pair() => SideBySide(first: _box('x', 50), second: _box('y', 50));

    testWidgets('stacks on a phone', (tester) async {
      await _pump(tester, 400, pair());
      expect(_at(tester, 'y').dx, _at(tester, 'x').dx);
      expect(_at(tester, 'y').dy, greaterThan(_at(tester, 'x').dy));
    });

    testWidgets('sits side by side on a desktop', (tester) async {
      await _pump(tester, 1300, pair());
      expect(_at(tester, 'y').dx, greaterThan(_at(tester, 'x').dx));
      expect(_at(tester, 'y').dy, _at(tester, 'x').dy);
    });
  });
}
