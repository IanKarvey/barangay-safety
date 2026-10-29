import 'package:barangay_safety_app/services/covered_barangays_service.dart';
import 'package:barangay_safety_app/widgets/covered_barangays_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/render.dart';

class _Counts implements CoveredBarangaysSource {
  _Counts(this._counts, {this.fail = false});
  final Map<String, int> _counts;
  final bool fail;

  @override
  Future<Map<String, int>> counts() async {
    if (fail) throw Exception('function does not exist');
    return _counts;
  }
}

void main() {
  setUpAll(loadRealFonts);

  final counts = {
    'Barangay 1': 14,
    'Barangay 2': 9,
    'Barangay 3': 31,
    'Barangay 7': 6,
    'Barangay 10': 21,
  };

  Future<void> pump(WidgetTester tester, Size size, CoveredBarangaysSource src,
      {String? me = 'Barangay 1'}) async {
    useSize(tester, size);
    await tester.pumpWidget(renderApp(
      Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: CoveredBarangaysCard(
            source: src,
            highlightName: me,
            showTiles: false,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(400, 760), const Size(1100, 560)]) {
    testWidgets('ranks the five barangays by incident count at '
        '${size.width.toInt()}px', (tester) async {
      await pump(tester, size, _Counts(counts));

      expect(find.text('Covered Barangays'), findsOneWidget);
      for (final n in counts.keys) {
        expect(find.text(n), findsOneWidget, reason: n);
      }
      // Busiest first: Barangay 3 (31) is rank 1, Barangay 7 (6) is last.
      final y3 = tester.getTopLeft(find.text('Barangay 3')).dy;
      final y10 = tester.getTopLeft(find.text('Barangay 10')).dy;
      final y7 = tester.getTopLeft(find.text('Barangay 7')).dy;
      expect(y3 < y10 && y10 < y7, isTrue, reason: 'ordered by count, descending');

      expect(find.text('31'), findsOneWidget);
      expect(find.text('You'), findsOneWidget, reason: 'own barangay is marked');
      expect(tester.takeException(), isNull);
      await snap(tester, 'covered_${size.width.toInt()}');
    });
  }

  testWidgets('still names all five when the counts cannot be loaded',
      (tester) async {
    await pump(tester, const Size(400, 760), _Counts({}, fail: true));

    // Numeric order, no numbers, and an honest note rather than a blank card.
    for (final n in ['Barangay 1', 'Barangay 2', 'Barangay 3', 'Barangay 7', 'Barangay 10']) {
      expect(find.text(n), findsOneWidget, reason: n);
    }
    expect(find.text('Incident counts are unavailable right now.'), findsOneWidget);
    expect(find.text('31'), findsNothing);
    expect(tester.takeException(), isNull);
    await snap(tester, 'covered_nocounts');
  });

  testWidgets('does not mark anyone "You" when the barangay is unknown',
      (tester) async {
    await pump(tester, const Size(400, 760), _Counts(counts), me: null);
    expect(find.text('You'), findsNothing);
  });
}
