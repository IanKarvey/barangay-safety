import 'package:flutter_test/flutter_test.dart';
import 'package:barangay_safety_app/config/app_config.dart';
import 'package:barangay_safety_app/utils/severity.dart';

/// The severity scale was reversed on 2026-08-25: **4 is now the worst**.
///
/// It previously ran the other way, and the raw integer was compared against
/// literals in eleven files (`== 1`, `<= 2`, `!= 1`). Getting any one of those
/// backwards would have been silent and serious — `full_blast_service` fires
/// the barangay-wide alert off this number, so an inverted comparison means a
/// fire that never wakes anyone, or a noise complaint that wakes everyone.
///
/// These tests exist so the direction cannot drift back.
void main() {
  group('scale direction', () {
    test('critical outranks everything', () {
      expect(Severity.critical, greaterThan(Severity.high));
      expect(Severity.high, greaterThan(Severity.medium));
      expect(Severity.medium, greaterThan(Severity.low));
    });

    test('critical is 4 and low is 1, matching the owner decision', () {
      expect(Severity.critical, 4);
      expect(Severity.low, 1);
    });

    test('isCritical fires only at the top', () {
      expect(Severity.isCritical(Severity.critical), isTrue);
      expect(Severity.isCritical(Severity.high), isFalse);
      expect(Severity.isCritical(Severity.medium), isFalse);
      expect(Severity.isCritical(Severity.low), isFalse);
    });

    test('isUrgent covers critical and high, nothing below', () {
      expect(Severity.isUrgent(Severity.critical), isTrue);
      expect(Severity.isUrgent(Severity.high), isTrue);
      expect(Severity.isUrgent(Severity.medium), isFalse);
      expect(Severity.isUrgent(Severity.low), isFalse);
    });

    test('the meter fills toward critical, not away from it', () {
      expect(Severity.fraction(Severity.critical), 1.0);
      expect(Severity.fraction(Severity.low),
          lessThan(Severity.fraction(Severity.critical)));
    });
  });

  group('category decides the level', () {
    test('the two the owner named', () {
      // "fire ... automatically sets as [the top] threat"
      expect(Severity.forCategory('Fire'), Severity.critical);
      // "when it goes like noise complaint, it will be like [the lowest]"
      expect(Severity.forCategory('Noise Disturbance'), Severity.low);
    });

    test('a fire triggers the barangay-wide alert', () {
      expect(Severity.isCritical(Severity.forCategory('Fire')), isTrue);
    });

    test('a noise complaint never does', () {
      expect(
          Severity.isCritical(Severity.forCategory('Noise Disturbance')),
          isFalse);
      expect(Severity.isUrgent(Severity.forCategory('Noise Disturbance')),
          isFalse);
    });

    test('life-threatening categories are all critical', () {
      for (final c in [
        'Fire',
        'Medical Emergency',
        'Physical Assault',
        'Domestic Violence',
      ]) {
        expect(Severity.forCategory(c), Severity.critical,
            reason: '$c should wake the hall');
      }
    });

    test('a fender-bender does not wake the whole hall', () {
      // Deliberate: most vehicular accidents are damage-only, and an alert
      // people learn to ignore is the same as no alert.
      expect(Severity.forCategory('Vehicular Accident'), Severity.high);
      expect(Severity.isCritical(Severity.forCategory('Vehicular Accident')),
          isFalse);
    });
  });

  group('unknown input cannot cause harm', () {
    test('an unmapped category lands mid-scale, not at either extreme', () {
      final level = Severity.forCategory('Something Not In The List');
      expect(level, Severity.fallback);
      // Not critical — a typo must not blast the barangay.
      expect(Severity.isCritical(level), isFalse);
      // Not low either — a real report must not be buried.
      expect(level, greaterThan(Severity.low));
    });

    test('null is handled', () {
      expect(Severity.forCategory(null), Severity.fallback);
      expect(Severity.isCritical(Severity.forCategory(null)), isFalse);
    });

    test('out-of-range values are clamped', () {
      expect(Severity.clamp(99), Severity.critical);
      expect(Severity.clamp(0), Severity.fallback);
      expect(Severity.clamp(-5), Severity.fallback);
    });
  });

  test('every category the app offers has a triage level', () {
    // Guards the failure this cannot afford: someone adds a category to
    // AppConfig.incidentCategories, forgets to triage it here, and it silently
    // arrives as Medium forever.
    expect(Severity.uncoveredCategories, isEmpty,
        reason: 'these categories have no severity mapping: '
            '${Severity.uncoveredCategories}');
    expect(AppConfig.incidentCategories, isNotEmpty);
  });
}
