import 'package:flutter_test/flutter_test.dart';
import 'package:barangay_safety_app/utils/helpers.dart';

/// Bulk actions run a few at a time instead of one after another.
///
/// The behaviour worth pinning is not the speed — it is that partial failure
/// stays partial. An official marking twenty reports resolved needs the
/// nineteen that worked to stay worked, and needs the count they are shown to
/// be the truth.
void main() {
  group('runBulk', () {
    test('results line up with the input order, not completion order', () async {
      // Deliberately finishes in reverse, so anything that appends results as
      // they arrive will fail this.
      final results = await runBulk<int>(
        [0, 1, 2, 3, 4],
        (i) async {
          await Future.delayed(Duration(milliseconds: (5 - i) * 10));
          return i.isEven;
        },
        concurrency: 5,
      );

      expect(results, [true, false, true, false, true]);
    });

    test('one failure does not discard the successes', () async {
      final results = await runBulk<int>(
        [1, 2, 3, 4],
        (i) async {
          if (i == 3) throw StateError('server said no');
          return true;
        },
      );

      expect(results, [true, true, false, true]);
      expect(results.where((ok) => ok).length, 3);
    });

    test('a returned false is preserved, not treated as a throw', () async {
      final results = await runBulk<int>([1, 2], (i) async => i == 1);
      expect(results, [true, false]);
    });

    test('never exceeds the concurrency limit', () async {
      var inFlight = 0;
      var peak = 0;

      await runBulk<int>(
        List.generate(20, (i) => i),
        (_) async {
          inFlight++;
          peak = inFlight > peak ? inFlight : peak;
          await Future.delayed(const Duration(milliseconds: 5));
          inFlight--;
          return true;
        },
        concurrency: 4,
      );

      // The point of bounding it: fifty simultaneous writes would risk rate
      // limiting on Supabase and exhaust sockets on a phone.
      expect(peak, lessThanOrEqualTo(4));
      expect(peak, greaterThan(1), reason: 'should actually run in parallel');
    });

    test('every item runs exactly once', () async {
      final seen = <int>[];
      await runBulk<int>(
        List.generate(15, (i) => i),
        (i) async {
          seen.add(i);
          return true;
        },
        concurrency: 4,
      );

      expect(seen.length, 15);
      expect(seen.toSet().length, 15, reason: 'no item repeated');
      expect(seen.toSet(), List.generate(15, (i) => i).toSet());
    });

    test('an empty batch is a no-op, not a hang', () async {
      // `Future.wait` over zero lanes must still complete — an empty selection
      // reaching here would otherwise leave the spinner up forever.
      expect(await runBulk<int>([], (_) async => true), isEmpty);
    });

    test('a single item does not spin up idle workers', () async {
      expect(await runBulk<int>([7], (i) async => i == 7), [true]);
    });
  });
}
