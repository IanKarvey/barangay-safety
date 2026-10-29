import 'package:flutter/foundation.dart';

import 'supabase_service.dart';

/// Where the covered-barangays card gets its incident counts. An interface so
/// the card can be rendered and tested without a database.
abstract class CoveredBarangaysSource {
  /// Barangay name → number of reports. Throws if the counts cannot be loaded;
  /// the card treats that as "show the barangays without numbers".
  Future<Map<String, int>> counts();
}

/// Reads `covered_barangay_stats()` — a database function that returns only a
/// name and a count (supabase/migration_2026_10_15_covered_barangays.sql). It
/// exists because a resident can read only their own reports, so ranking
/// barangays needs a function allowed to count everyone's.
class SupabaseCoveredBarangaysSource implements CoveredBarangaysSource {
  final _supabase = SupabaseService.instance;

  @override
  Future<Map<String, int>> counts() async {
    try {
      final rows = await _supabase.client.rpc('covered_barangay_stats');
      return {
        for (final r in rows as List)
          (r as Map)['name'] as String: ((r['incident_count']) as num).toInt(),
      };
    } catch (e) {
      // Includes "function does not exist" before the migration is run.
      debugPrint('CoveredBarangays: counts unavailable: $e');
      rethrow;
    }
  }
}
