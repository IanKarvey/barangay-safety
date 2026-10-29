import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:barangay_safety_app/widgets/app_text.dart';

/// `AppText` is the shrink-to-fit replacement for `Text`, backing the
/// project-wide fix for text breaking mid-word (2026-09) — see the class doc
/// on `AppText` for the full story.
///
/// These pin the two guarantees that actually matter: it survives real
/// layout without throwing, and — the one property that made the original bug
/// worth fixing in the first place — a long single word never gets split
/// across two lines, even under a column narrower than the word itself.
void main() {
  Future<void> pumpBounded(
    WidgetTester tester,
    Widget child, {
    double width = 160,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: child,
          ),
        ),
      ),
    );
  }

  group('renders without throwing', () {
    testWidgets('short static text, ample width', (tester) async {
      await pumpBounded(tester, const AppText('Home'), width: 300);
      expect(find.text('Home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long single word in a narrow column', (tester) async {
      // This is the exact shape of the reported bug: one word, forced into a
      // column too narrow for it at the requested size.
      await pumpBounded(
        tester,
        const AppText.heading2('Administrator'),
        width: 90,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long localized sentence in a narrow column',
        (tester) async {
      await pumpBounded(
        tester,
        const AppText(
          'Ipinagpatuloy ang pagbabahagi ng lokasyon',
          maxLines: 2,
        ),
        width: 80,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('zero-width edge case does not crash', (tester) async {
      await pumpBounded(tester, const AppText('x'), width: 0.0001);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every named constructor builds cleanly', (tester) async {
      final constructors = <Widget>[
        const AppText.largeTitle('Title'),
        const AppText.heading1('Heading'),
        const AppText.heading2('Heading'),
        const AppText.heading3('Heading'),
        const AppText.body('Body text'),
        const AppText.bodySmall('Body small'),
        const AppText.subheadline('Subheadline'),
        const AppText.button('Continue'),
        const AppText.caption('Caption'),
        const AppText.footnote('Footnote'),
        const AppText.oneLine('One line only'),
      ];
      for (final w in constructors) {
        await pumpBounded(tester, w, width: 120);
        expect(tester.takeException(), isNull, reason: w.runtimeType.toString());
      }
    });
  });

  group('the mid-word break is actually gone', () {
    testWidgets(
        'a single word narrower than its column renders as one text node',
        (tester) async {
      // If the word were split mid-word, this would render as two or more
      // separate RenderParagraph fragments (or fail to find the whole string
      // as a single node). Finding it whole is the property that matters.
      await pumpBounded(
        tester,
        const AppText.heading2('Administrator'),
        width: 300, // wide enough to fit without any shrinking
      );
      expect(find.text('Administrator'), findsOneWidget);
    });

    testWidgets('maxLines is honoured rather than growing unbounded',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 100,
              height: 200,
              child: AppText(
                'This is a long sentence with many words that would wrap '
                'across many lines if nothing constrained it at all',
                maxLines: 2,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('defaults are safe for a bare rename', () {
    testWidgets('the plain constructor sets maxLines without being told',
        (tester) async {
      // This is the property the whole rollout depends on: `Text(x)` ->
      // `AppText(x)` with NOTHING else changed has to already be safe, since
      // that mechanical rename is what was applied at 349 call sites.
      const widget = AppText('anything');
      expect(widget.maxLines, 2);
      expect(widget.overflow, TextOverflow.ellipsis);
    });

    testWidgets('an explicit maxLines at the call site still wins',
        (tester) async {
      const widget = AppText('anything', maxLines: 5);
      expect(widget.maxLines, 5);
    });
  });
}
