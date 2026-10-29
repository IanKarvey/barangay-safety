import 'package:flutter/foundation.dart';

import '../utils/escalation_clock.dart';
import 'response_service.dart';

/// The server's idea of "now" and of the escalation interval, fetched once.
///
/// The tiers are decided by the database from ITS clock. A timer drawn from the
/// phone's clock would drift from that on any phone that is a few minutes off,
/// and then show "5:00, nothing yet" while the resident has already been told
/// help is delayed.
///
/// Until the first sync finishes (or when offline) this falls back to the phone
/// clock and the 5-minute default, which is right for nearly everyone.
class ServerClock {
  ServerClock._();

  static Duration offset = Duration.zero;
  static Duration step = kDefaultEscalationStep;
  static Future<void>? _inflight;

  /// Idempotent: the first caller starts the sync, everyone else waits on it.
  /// A failed sync is retried by the next caller.
  static Future<void> ensureSynced() {
    return _inflight ??= _sync();
  }

  static Future<void> _sync() async {
    try {
      final service = ResponseService();
      final off = await service.serverOffset();
      final st = await service.escalationStep();
      offset = off;
      step = st;
    } catch (e) {
      debugPrint('ServerClock: sync failed, using the phone clock — $e');
      _inflight = null; // let the next caller try again
    }
  }

  static DateTime get now => DateTime.now().add(offset);

  /// For tests.
  @visibleForTesting
  static void reset() {
    offset = Duration.zero;
    step = kDefaultEscalationStep;
    _inflight = null;
  }
}
