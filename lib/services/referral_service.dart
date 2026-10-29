import 'package:flutter/foundation.dart';

import 'supabase_service.dart';

/// Records that someone tried to report something the barangay cannot handle
/// and was sent to the right agency instead.
///
/// ## Why record it at all
///
/// The referral rule stops these from becoming incidents, which is right — the
/// hall must not be asked to dispatch to a fire. But it also means the barangay
/// would never learn that a fire or a serious accident happened inside its own
/// boundaries. A referral is the record that it did: category, time, rough
/// location, which agency the person was pointed to. It is **not** an incident:
/// nothing here is assigned, tracked or expected to be actioned.
///
/// ## It must never get in the way
///
/// This runs while a frightened person is looking at a "call this number"
/// screen. A slow or failing insert must not delay that screen or show an error
/// on top of it, so [log] swallows every failure and the caller does not await
/// it. The cost is that a failure is silent; the gain is that the one thing on
/// screen that matters is never blocked by bookkeeping.
class ReferralService {
  final _supabase = SupabaseService.instance;

  Future<void> log({
    required String category,
    required String agency,
    String? barangayId,
    double? latitude,
    double? longitude,
  }) async {
    try {
      await _supabase.client.from('incident_referrals').insert({
        'reporter_id': _supabase.currentUser?.id,
        'barangay_id': barangayId,
        'category': category,
        'agency': agency,
        'latitude': latitude,
        'longitude': longitude,
      });
    } catch (e) {
      // Includes "relation incident_referrals does not exist" before the
      // migration has been run — the pop-up still works without the log.
      debugPrint('ReferralService: could not log referral: $e');
    }
  }
}
