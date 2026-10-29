import 'package:flutter/foundation.dart';
import 'supabase_service.dart';

/// §11 — SMS delivery for emergencies.
///
/// ## The API key is not in this app
///
/// Sending goes through the `send-sms` Supabase Edge Function, which holds the
/// Semaphore key as a server secret. Calling Semaphore directly from here would
/// ship a key that spends real money inside the APK, where anyone who unzips it
/// can drain the balance.
///
/// ## Emergencies only
///
/// SMS costs roughly ₱1 per recipient per message; push costs nothing. A
/// barangay with 20 personnel spends ₱20 every time this fires, so it is
/// reserved for full-blast critical alerts (§14). Routine status updates stay
/// push-only — that is a cost decision as much as a design one, and it is the
/// same reason §14 restricts automatic blasts to severity 1.
///
/// ## It reaches people push cannot
///
/// Push needs the app installed, granted notification permission, and a working
/// data connection. A tanod on a basic plan with mobile data off still receives
/// an SMS. That is the entire justification for the cost: it is the delivery
/// path that works when the others do not.
class SmsService {
  final _supabase = SupabaseService.instance;

  /// Sends [message] to every number in [phones].
  ///
  /// Returns how many were accepted by the provider, or 0 if SMS is not
  /// configured or the send failed. **Never throws** — callers pair this with a
  /// push notification that has already been delivered, so a missing or broken
  /// SMS provider is a lost enhancement, not a failed alert. Surfacing it as an
  /// error would tell an official the alert failed when it did not.
  Future<int> send({
    required List<String> phones,
    required String message,
  }) async {
    final numbers = phones.where((p) => p.trim().isNotEmpty).toList();
    if (numbers.isEmpty) return 0;

    try {
      final res = await _supabase.client.functions.invoke(
        'send-sms',
        body: {'numbers': numbers, 'message': message},
      );

      final data = res.data;
      if (data is Map && data['sent'] is num) {
        final sent = (data['sent'] as num).toInt();
        if (sent == 0 && data['reason'] != null) {
          // Logged rather than silent: "not configured" and "provider rejected
          // it" look identical from the outside, and only one of them is a
          // problem someone needs to fix.
          debugPrint('SmsService: nothing sent — ${data['reason']}');
        }
        return sent;
      }
      return 0;
    } catch (e) {
      debugPrint('SmsService: send failed: $e');
      return 0;
    }
  }
}
