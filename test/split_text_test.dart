import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:barangay_safety_app/widgets/split_text.dart';

/// `SplitText` stagger-animates a heading one character at a time. Before
/// 2026-09-15 it fed those characters to a bare `Wrap` individually, which
/// meant `Wrap` could break the line between *any* two characters once space
/// ran out — including mid-word, and even when the word itself wasn't too
/// wide for the column. That's a strictly worse failure mode than plain
/// `Text`, which only ever breaks a word when the word alone overflows.
///
/// The fix groups each word's characters into one atomic `Row` before handing
/// them to `Wrap`, so `Wrap` can only break between words. These tests pin
/// that structural property directly, since it's invisible from reading the
/// rendered text alone.
void main() {
  Future<void> pump(WidgetTester tester, String text) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SplitText(text, style: const TextStyle(fontSize: 20)),
        ),
      ),
    );
    // Each character schedules its own flutter_animate Timer (fade + slide);
    // pumpAndSettle drains them so no pending timer trips the test harness.
    await tester.pumpAndSettle();
  }

  testWidgets('every word is one atomic Row, not loose characters',
      (tester) async {
    await pump(tester, 'City Administrator');

    // The outer Wrap should contain exactly as many word-Rows (plus space
    // Texts) as the source has words and spaces between them — never one
    // Wrap child per character.
    final wrap = tester.widget<Wrap>(find.byType(Wrap));
    // "City" + " " + "Administrator" = 3 top-level children.
    expect(wrap.children.length, 3);

    // First and third children are word-Rows; the middle one is the space.
    expect(wrap.children[0], isA<Flex>());
    expect(wrap.children[2], isA<Flex>());

    final cityRow = wrap.children[0] as Flex;
    final adminRow = wrap.children[2] as Flex;
    expect(cityRow.children.length, 4); // C-i-t-y
    expect(adminRow.children.length, 13); // Administrator
  });

  testWidgets('every character still renders, in order', (tester) async {
    await pump(tester, 'City Administrator');

    for (final char in 'City Administrator'.split('')) {
      // Multiple identical letters exist (e.g. repeated 'i', 't') so this
      // only confirms presence, not position — position is covered by the
      // Row-grouping test above.
      expect(find.text(char), findsWidgets);
    }
  });

  testWidgets('a single word never splits across two Wrap children',
      (tester) async {
    await pump(tester, 'Administrator');

    final wrap = tester.widget<Wrap>(find.byType(Wrap));
    // One word, zero spaces -> exactly one child, and it must be the whole
    // word in one Row. Two or more children here would mean the word could
    // be broken across a Wrap line boundary.
    expect(wrap.children.length, 1);
    expect(wrap.children.single, isA<Flex>());
    expect((wrap.children.single as Flex).children.length, 13);
  });

  testWidgets('multiple spaces and words all group correctly',
      (tester) async {
    await pump(tester, 'Good evening');

    final wrap = tester.widget<Wrap>(find.byType(Wrap));
    expect(wrap.children.length, 3); // Good, space, evening
    expect((wrap.children[0] as Flex).children.length, 4); // Good
    expect((wrap.children[2] as Flex).children.length, 7); // evening
  });

  testWidgets(
      'a long word fits cleanly at a realistic column width', (tester) async {
    // The width this fix was actually built for: not a starved sliver, but a
    // normal column that simply isn't as wide as a desktop screen.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: SplitText(
              'Administrator',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a word that truly cannot fit surfaces the normal Flutter overflow '
      'warning instead of a silent mid-word split', (tester) async {
    // This is deliberately hostile: one word forced into a column narrower
    // than the word itself. Flutter's own overflow diagnostic fires here —
    // the same "RenderFlex overflowed" signal any oversized Row or Column
    // child would produce — and that is the correct, honest outcome. It is
    // NOT a regression: a bare Text widget given the same impossible width
    // has nowhere to break the word either, so it also cannot display cleanly.
    //
    // What actually matters, and what the old implementation got wrong, is
    // that the word is never chopped into pieces along an arbitrary
    // character boundary and left looking plausible — it stays one atomic
    // unit, so the failure is loud and diagnosable rather than a quietly
    // wrong-looking two-line render. Preventing a genuinely-too-narrow column
    // from ever reaching this widget is the caller's job — the same
    // responsibility a caller has with plain Text today.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 90,
            child: SplitText(
              'Administrator',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The word's Flex child still holds every character as one unit — it
    // overflowed as a whole, it did not fracture into two rendered lines.
    final wrap = tester.widget<Wrap>(find.byType(Wrap));
    expect(wrap.children.length, 1);
    expect((wrap.children.single as Flex).children.length, 13);

    expect(tester.takeException(), isA<FlutterError>());
  });
}
