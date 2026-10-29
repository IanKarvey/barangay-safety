import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../services/responder_location_service.dart';
import '../services/location_service.dart';

/// Drives an official's live-location broadcast.
///
/// Opt-in by design: nothing is published until [startSharing] is called, and
/// [stopSharing] erases the last position rather than leaving a stale pin that
/// could make a reporter think help is nearby.
class ResponderLocationProvider with ChangeNotifier {
  final ResponderLocationService _service = ResponderLocationService();
  final LocationService _locationService = LocationService();

  bool _isSharing = false;
  bool _isBusy = false;
  String? _error;
  String? _userId;

  StreamSubscription<Position>? _positionSub;
  Timer? _heartbeatTimer;

  /// Backstop for when the GPS stream stalls or the official stands still —
  /// without it their pin would look "lost" to the reporter watching.
  static const _heartbeatInterval = Duration(seconds: 10);

  /// Write ceiling. Officials move by vehicle, so 2s is plenty and keeps the
  /// database write rate sane when several are responding at once.
  static const _minWriteGap = Duration(seconds: 2);
  DateTime? _lastWriteAt;

  bool get isSharing => _isSharing;
  bool get isBusy => _isBusy;
  String? get error => _error;

  /// True when this launch resumed a broadcast the official had left on.
  ///
  /// Surfaced so resuming is never silent — the officials' home screen shows a
  /// notice. Cleared once shown.
  bool _resumedOnStartup = false;
  bool get resumedOnStartup => _resumedOnStartup;
  void consumeResumeNotice() => _resumedOnStartup = false;

  /// True when a broadcast could not be resumed and was switched off instead.
  bool _resumeFailed = false;
  bool get resumeFailed => _resumeFailed;
  void consumeResumeFailure() => _resumeFailed = false;

  /// Reconcile the stored flag with reality at startup.
  ///
  /// ## The problem on both sides
  ///
  /// A killed or restarted app leaves `is_sharing_location = true` and the
  /// last coordinates published while nothing is actually tracking — a frozen
  /// pin the reporter reads as live help on the way. Worse than no pin.
  ///
  /// The first fix for that switched sharing OFF on every launch. It removed
  /// the stale pin and removed the feature with it: officials open the app
  /// several times a day, so live tracking silently stopped working for
  /// anyone who had not re-toggled it since their last launch. That is the
  /// reported "some officials show, some don't" (2026-08-25).
  ///
  /// ## What it does now
  ///
  /// **Resumes** the broadcast instead of clearing it. That answers the
  /// original danger better than switching off did — a resumed broadcast
  /// publishes a fresh fix immediately, so there is no frozen pin at all.
  ///
  /// If the resume fails — permission revoked, GPS off, no fix — it falls back
  /// to clearing, because a pin that cannot be refreshed is exactly the stale
  /// pin the original fix existed to prevent.
  ///
  /// Consent is not being assumed here: the official turned this on and never
  /// turned it off. What was missing was visibility, so both outcomes set a
  /// flag the home screen announces rather than resuming quietly.
  Future<void> reconcileOnStartup({
    required String userId,
    required bool wasSharing,
  }) async {
    _userId = userId;
    if (!wasSharing) return;

    final resumed = await startSharing(userId);

    if (resumed) {
      _resumedOnStartup = true;
      debugPrint('ResponderLocationProvider: resumed sharing on startup');
    } else {
      // Could not resume — clear, so nothing stale is left published.
      _resumeFailed = true;
      _isSharing = false;
      try {
        await _service.stopSharing(userId);
        debugPrint(
            'ResponderLocationProvider: could not resume, cleared stale flag');
      } catch (e) {
        debugPrint('ResponderLocationProvider: could not clear stale flag: $e');
      }
    }
    _safeNotify();
  }

  Future<bool> startSharing(String userId) async {
    _userId = userId;
    _isBusy = true;
    _error = null;
    _safeNotify();

    try {
      final pos = await _locationService.getCurrentPosition();
      await _service.startSharing(userId, pos.latitude, pos.longitude);
      _isSharing = true;
      _isBusy = false;
      _beginTracking();
      _safeNotify();
      return true;
    } on LocationException catch (e) {
      _error = e.message;
      _isBusy = false;
      _safeNotify();
      return false;
    } catch (e) {
      debugPrint('ResponderLocationProvider: startSharing failed: $e');
      _error = 'Could not start sharing your location.';
      _isBusy = false;
      _safeNotify();
      return false;
    }
  }

  Future<void> stopSharing() async {
    final userId = _userId;
    _stopTracking();
    _isSharing = false;
    _safeNotify();

    if (userId == null) return;
    try {
      await _service.stopSharing(userId);
    } catch (e) {
      debugPrint('ResponderLocationProvider: stopSharing failed: $e');
    }
  }

  Future<bool> toggle(String userId) async {
    if (_isSharing) {
      await stopSharing();
      return false;
    }
    return startSharing(userId);
  }

  // ── Internals ─────────────────────────────────────────────────────────
  void _beginTracking() {
    if (_positionSub != null) return;

    _positionSub = _locationService.getLiveTrackingStream().listen(
      (pos) => _push(pos.latitude, pos.longitude),
      onError: (e) =>
          debugPrint('ResponderLocationProvider: stream error: $e'),
    );

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) async {
      try {
        final pos = await _locationService.getCurrentPosition();
        await _push(pos.latitude, pos.longitude, force: true);
      } catch (e) {
        debugPrint('ResponderLocationProvider: heartbeat failed: $e');
      }
    });
  }

  void _stopTracking() {
    _positionSub?.cancel();
    _positionSub = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _lastWriteAt = null;
  }

  Future<void> _push(double lat, double lng, {bool force = false}) async {
    final userId = _userId;
    if (userId == null || !_isSharing) return;

    final now = DateTime.now();
    if (!force &&
        _lastWriteAt != null &&
        now.difference(_lastWriteAt!) < _minWriteGap) {
      return;
    }
    _lastWriteAt = now;

    try {
      await _service.updateLocation(userId, lat, lng);
    } catch (e) {
      // Not fatal — the reporter sees a stale timestamp and the next fix
      // retries.
      debugPrint('ResponderLocationProvider: push failed: $e');
    }
  }

  void clearError() {
    _error = null;
    _safeNotify();
  }

  /// Called on logout — an official must not keep broadcasting after signing
  /// out.
  Future<void> resetForLogout() async {
    if (_isSharing) await stopSharing();
    _userId = null;
    _error = null;
  }

// ── Disposal safety ───────────────────────────────────────────────────
  // Providers are torn down on logout and on navigation while their async
  // work is still in flight. `notifyListeners()` after `dispose()` throws
  // `A ChangeNotifier was used after being disposed` — an unhandled error on
  // a background future, which the user sees as a crash they cannot retry.
  bool _disposed = false;

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTracking();
    super.dispose();
  }
}
