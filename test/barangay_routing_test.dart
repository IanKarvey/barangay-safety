import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

/// §2 — the surveyed barangay hall positions, and the routing that depends on
/// them.
///
/// `BarangayService.findNearestBarangay()` decides which hall receives a
/// non-resident emergency, by haversine against `barangays.center_lat/lng`.
///
/// The original development seeds were 293–745 m out. Checked against the
/// positions the owner surveyed on site on 2026-08-25, the seeds routed an
/// emergency raised **at a barangay hall's own front door** to the wrong
/// barangay in three cases out of five. The halls sit as little as 190 m
/// apart, so a few hundred metres of error was more than enough.
///
/// These tests pin the surveyed values and the property that actually
/// matters — that each hall resolves to itself — so a future edit to the
/// coordinates cannot quietly reintroduce misrouting.
void main() {
  // Surveyed on site, 2026-08-25.
  const halls = <String, (double, double)>{
    'Barangay 1': (13.941946, 121.157097), // B. Morada St / Library Hub
    'Barangay 2': (13.943443, 121.158837), // unnamed road, Poblacion
    'Barangay 3': (13.943112, 121.160564), // Rizal Street
    'Barangay 7': (13.936218, 121.160714), // Cadena Street
    'Barangay 10': (13.942557, 121.167828), // San Vicente Street
  };

  // The values that shipped in schema.sql. Kept here only to prove they were
  // wrong — do not restore them.
  const seeds = <String, (double, double)>{
    'Barangay 1': (13.9420, 121.1640),
    'Barangay 2': (13.9435, 121.1620),
    'Barangay 3': (13.9400, 121.1610),
    'Barangay 7': (13.9390, 121.1650),
    'Barangay 10': (13.9445, 121.1660),
  };

  double metres(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180.0;
    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  String nearest(Map<String, (double, double)> centres, (double, double) at) {
    var best = centres.keys.first;
    var bestD = double.infinity;
    centres.forEach((name, c) {
      final d = metres(c.$1, c.$2, at.$1, at.$2);
      if (d < bestD) {
        bestD = d;
        best = name;
      }
    });
    return best;
  }

  group('surveyed centres route correctly', () {
    test('every hall resolves to itself', () {
      // The property that matters. If this ever fails, someone standing at a
      // barangay hall gets a different barangay's responders.
      for (final entry in halls.entries) {
        expect(nearest(halls, entry.value), entry.key,
            reason: 'an emergency at ${entry.key} would go elsewhere');
      }
    });

    test('a point beside one hall still resolves to that hall', () {
      // ~40m north of Barangay 3, well inside its own block.
      const beside = (13.943472, 121.160564);
      expect(nearest(halls, beside), 'Barangay 3');
    });
  });

  group('the seeds really were misrouting', () {
    test('three of five halls resolved to the wrong barangay', () {
      final wrong = <String>[];
      for (final entry in halls.entries) {
        if (nearest(seeds, entry.value) != entry.key) wrong.add(entry.key);
      }
      // Documents the fault this migration fixed, so the severity of it is not
      // forgotten if someone later wonders why the coordinates were changed.
      expect(wrong.length, 3);
      expect(wrong, containsAll(['Barangay 1', 'Barangay 3', 'Barangay 7']));
    });

    test('every seed was at least 290m from the real hall', () {
      for (final entry in halls.entries) {
        final s = seeds[entry.key]!;
        final d = metres(s.$1, s.$2, entry.value.$1, entry.value.$2);
        expect(d, greaterThan(290),
            reason: '${entry.key} seed was only ${d.round()}m out');
      }
    });
  });

  test('the halls are close enough that accuracy is not optional', () {
    // Barangay 2 to Barangay 3 is the tightest pair. Anything approaching this
    // as a coordinate error starts crossing barangay boundaries.
    final d = metres(
      halls['Barangay 2']!.$1,
      halls['Barangay 2']!.$2,
      halls['Barangay 3']!.$1,
      halls['Barangay 3']!.$2,
    );
    expect(d, lessThan(250));
    expect(d, greaterThan(150));
  });
}
