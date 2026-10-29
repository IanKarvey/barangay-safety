import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/non_resident_session_model.dart';
import '../services/non_resident_service.dart';
import '../services/responder_location_service.dart';
import '../services/location_service.dart';

/// Holds the non-resident's session and keeps their live location flowing to
/// the barangay while a report is in flight. See §1 in
/// BARANGAY_CONNECT_REQUIREMENTS.md.
class NonResidentProvider with ChangeNotifier {
  final NonResidentService _service = NonResidentService();
  final LocationService _locationService = LocationService();

  NonResidentSessionModel? _session;
  bool _isLoading = false;
  String? _error;

  /// GPS stream — one fix per second while a session is open, so the barangay
  /// follows the reporter continuously rather than in jumps.
  StreamSubscription<Position>? _positionSub;

  /// Backstop in case the GPS stream stalls entirely (tunnel, indoors); keeps
  /// the barangay's "last seen" timestamp honest. Also covers mock-location
  /// setups (emulators) where the GPS stream only fires on manual change.
  Timer? _heartbeatTimer;
  static const _heartbeatInterval = Duration(seconds: 5);

  /// Watches this reporter's own session so official-side decisions —
  /// deployed, resolved, disregarded — reach them live. Without this the
  /// reporter sits on a stale screen never learning help is on the way.
  StreamSubscription? _sessionSub;

  /// Backs off before reopening a dropped session watch.
  Timer? _sessionResubscribeTimer;

  /// Set when the barangay changes the status, so the UI can announce it
  /// once. The screen clears it after showing the popup.
  String? _pendingStatusAnnouncement;
  String? get pendingStatusAnnouncement => _pendingStatusAnnouncement;
  void consumeStatusAnnouncement() => _pendingStatusAnnouncement = null;

  /// The assigned official's live position, so the reporter can watch help
  /// approach rather than guess whether it's coming. At most one entry — a
  /// reporter must never be able to track officials handling other incidents.
  List<ResponderLocation> _responders = [];
  Timer? _respondersTimer;
  List<ResponderLocation> get responders => _responders;

  /// How often responder positions are refreshed. Polled rather than streamed
  /// because an anonymous reporter reads the `responder_locations` view, and
  /// Supabase realtime publishes tables, not views.
  static const _respondersInterval = Duration(seconds: 5);

  /// Database write ceiling. GPS emits ~1Hz and every write fans out to the
  /// barangay over realtime, so this is the throughput knob — lower it for a
  /// smoother trail, raise it to cut database and battery load.
  static const _minWriteGap = Duration(seconds: 1);
  DateTime? _lastWriteAt;

  NonResidentSessionModel? get session => _session;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasSession => _session != null && !_session!.isExpired;

  /// True when the user must not leave or be logged out — a report is live.
  bool get isLogoutLocked => _session?.logoutLocked ?? false;

  // ── Sign in ───────────────────────────────────────────────────────────
  /// Opens a session from contact number + name. Barangay is auto-detected
  /// from GPS. Returns false and sets [error] on failure.
  Future<bool> signIn({
    required String phone,
    required String fullName,
  }) async {
    _isLoading = true;
    _error = null;
    _safeNotify();

    try {
      final position = await _locationService.getCurrentPosition();
      _session = await _service.signInAndOpenSession(
        phone: phone,
        fullName: fullName,
        lat: position.latitude,
        lng: position.longitude,
      );
      _isLoading = false;
      _safeNotify();
      // Track from the moment they're in — not only once they report. The
      // barangay should be able to find them even mid-report-decision.
      startLocationTracking();
      _watchOwnSession();
      _watchResponders();
      return true;
    } on NonResidentException catch (e) {
      _error = e.message;
      _isLoading = false;
      _safeNotify();
      return false;
    } on LocationException catch (e) {
      _error = e.message;
      _isLoading = false;
      _safeNotify();
      return false;
    } catch (e) {
      _error = 'Could not start your session. Please try again.';
      _isLoading = false;
      _safeNotify();
      return false;
    }
  }

  /// Restore an existing session on app start, so reopening the app does not
  /// bounce a signed-in non-resident back to the login screen.
  Future<void> restoreSession() async {
    try {
      _session = await _service.getCurrentSession();
      // Any open session gets tracked, not just in-flight ones.
      if (_session != null && !_session!.isClosed) {
        startLocationTracking();
        _watchOwnSession();
        _watchResponders();
      }
    } catch (e) {
      debugPrint('NonResidentProvider: could not restore session: $e');
      _session = null;
    }
    _safeNotify();
  }

  // ── Report lifecycle ──────────────────────────────────────────────────
  /// Files the one allowed report and notifies the barangay.
  Future<bool> markReported({String? incidentId}) async {
    if (_session == null) return false;
    try {
      _session = await _service.markReported(_session!.id,
          incidentId: incidentId);
      startLocationTracking();
      _safeNotify();
      return true;
    } catch (e) {
      _error = 'Could not submit your report. Please try again.';
      _safeNotify();
      return false;
    }
  }

  /// Upload photo/video proof and move the session to `proof_ready`.
  Future<bool> uploadProof(File file, {String type = 'photo'}) async {
    if (_session == null) return false;
    _isLoading = true;
    _safeNotify();
    try {
      _session = await _service.uploadProof(_session!.id, file, type: type);
      _isLoading = false;
      _safeNotify();
      return true;
    } catch (e) {
      debugPrint('NonResidentProvider: proof upload failed: $e');
      _error = 'Could not upload your proof. Please try again.';
      _isLoading = false;
      _safeNotify();
      return false;
    }
  }

  /// The official assigned to this reporter, once the barangay picks one.
  ResponderContact? _assignedOfficial;
  ResponderContact? get assignedOfficial => _assignedOfficial;

  /// Record that the reporter could not call. Does not mark them as having
  /// called — the Secretary must know to phone out instead of waiting.
  Future<bool> markCallFailed({String reason = 'other'}) async {
    if (_session == null) return false;
    try {
      _session = await _service.markCallFailed(_session!.id, reason: reason);
      _safeNotify();
      return true;
    } catch (e) {
      debugPrint('NonResidentProvider: markCallFailed failed: $e');
      return false;
    }
  }

  /// Advance the session (called → proof_ready → deployed → completed).
  Future<bool> setStatus(String status, {String? disregardReason}) async {
    if (_session == null) return false;
    try {
      _session = await _service.setStatus(_session!.id, status,
          disregardReason: disregardReason);
      if (_session!.isClosed) stopLocationTracking();
      _safeNotify();
      return true;
    } catch (e) {
      _error = 'Could not update your report status.';
      _safeNotify();
      return false;
    }
  }

  // ── Responder tracking ────────────────────────────────────────────────
  /// Begin polling for officials sharing their location in this barangay.
  void _watchResponders() {
    if (_session == null || _respondersTimer != null) return;

    _fetchResponders();
    _refreshSessionStatus();
    // The same tick carries the session refresh. It is one row, it is already
    // on a timer that has to exist for responder positions, and it means a
    // reporter is never held on a locked screen for more than one interval
    // even if realtime is completely down.
    _respondersTimer = Timer.periodic(_respondersInterval, (_) {
      _fetchResponders();
      _refreshSessionStatus();
    });
  }

  void _stopWatchingResponders() {
    _respondersTimer?.cancel();
    _respondersTimer = null;
    _responders = [];
    _assignedOfficial = null;
  }

  /// Refreshes the ONE official assigned to this reporter.
  ///
  /// Deliberately not "every official sharing in the barangay" — that let any
  /// reporter watch staff travelling to somebody else's emergency. The
  /// database now scopes this to the caller's own session.
  Future<void> _fetchResponders() async {
    if (_session == null) return;
    try {
      final official = await _service.getMyAssignedOfficial();
      _assignedOfficial = official;
      _responders = (official != null && official.hasLocation)
          ? [
              ResponderLocation(
                id: official.id,
                fullName: official.fullName,
                position: official.position,
                barangayId: _session?.barangayId,
                lat: official.lat!,
                lng: official.lng!,
                updatedAt: official.locationAt,
              )
            ]
          : const [];
      _safeNotify();
    } catch (e) {
      debugPrint('NonResidentProvider: assigned responder fetch failed: $e');
    }
  }

  // ── Session watch ─────────────────────────────────────────────────────
  /// Subscribes to this reporter's own session row so status changes made by
  /// the barangay arrive live. Safe to call repeatedly.
  void _watchOwnSession() {
    final session = _session;
    if (session == null || _sessionSub != null) return;

    _sessionSub = _service.watchSession(session.id).listen(
      (updated) {
        if (updated != null) _applySessionUpdate(updated);
        // An assignment can land at any point, not just on a status change.
        _fetchResponders();
      },
      onError: (e) {
        // Previously this only logged, and `onDone` was not handled at all —
        // so the first dropped socket ended the watch permanently. The
        // reporter then sat on a screen that never updated, and because
        // logout stays locked while a report is in flight they could not
        // leave either. Marking a report resolved appeared to do nothing
        // until the app was restarted. Reported from a device 2026-08-25.
        debugPrint('NonResidentProvider: session watch error, retrying: $e');
        _resubscribeSession();
      },
      onDone: () {
        debugPrint('NonResidentProvider: session watch closed, retrying');
        _resubscribeSession();
      },
      cancelOnError: false,
    );
  }

  /// Reopens a dead session watch.
  ///
  /// `_sessionSub` is nulled first and that is the whole point: the guard at
  /// the top of [_watchOwnSession] returns early when it is non-null, so a
  /// subscription that had errored but was still assigned made every later
  /// attempt a no-op.
  void _resubscribeSession() {
    _sessionSub?.cancel();
    _sessionSub = null;
    _sessionResubscribeTimer?.cancel();
    _sessionResubscribeTimer = Timer(const Duration(seconds: 3), () {
      if (_disposed) return;
      _watchOwnSession();
    });
  }

  /// Folds a freshly-read session row into local state.
  ///
  /// Shared by the realtime watch and the polling backstop so the two can
  /// never disagree about what a status change means.
  ///
  /// Two things must survive the merge:
  ///  - position: our own GPS stream is fresher than a value that
  ///    round-tripped through the database.
  ///  - barangayName: Supabase realtime streams raw table rows and cannot
  ///    join, so `barangays(name)` is absent there. Without this the banner
  ///    reverts to "Locating your barangay…" on the first update. A polled
  ///    row *does* carry the join, so the incoming value wins when present.
  void _applySessionUpdate(NonResidentSessionModel updated) {
    final previousStatus = _session?.status;

    _session = updated.copyWith(
      lastLat: _session?.lastLat,
      lastLng: _session?.lastLng,
      lastLocationAt: _session?.lastLocationAt,
      barangayName: updated.barangayName ?? _session?.barangayName,
    );

    if (previousStatus != null && previousStatus != updated.status) {
      _pendingStatusAnnouncement = updated.status;
      if (_session!.isClosed) stopLocationTracking();
    }
    _safeNotify();
  }

  /// Re-reads this reporter's own session from the database.
  ///
  /// A backstop, not the primary path — realtime is. It exists because the
  /// cost of realtime silently failing here is not a stale screen, it is a
  /// person held on a locked screen during an emergency after the barangay
  /// has already finished with their report. Five seconds of staleness is
  /// acceptable; being trapped until an app restart is not.
  Future<void> _refreshSessionStatus() async {
    final current = _session;
    if (current == null || current.isClosed) return;
    try {
      final fresh = await _service.getCurrentSession();
      if (fresh != null && fresh.id == current.id) {
        _applySessionUpdate(fresh);
      }
    } catch (e) {
      debugPrint('NonResidentProvider: session refresh failed: $e');
    }
  }

  // ── Live location ─────────────────────────────────────────────────────
  /// Starts continuous GPS tracking. Safe to call repeatedly — it won't stack
  /// duplicate subscriptions.
  void startLocationTracking() {
    if (_positionSub != null) return; // already tracking

    // Emits whenever the reporter moves ~10m, so the barangay follows their
    // actual movement rather than sampling on a clock.
    _positionSub = _locationService.getLiveTrackingStream().listen(
      (position) => _pushLocation(position.latitude, position.longitude),
      onError: (e) =>
          debugPrint('NonResidentProvider: position stream error: $e'),
    );

    // Standing still produces no stream events, which would look identical to
    // "lost them" on the barangay's screen. This keeps the timestamp fresh.
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) async {
      final s = _session;
      if (s == null || !s.hasLocation) return;
      await _pushLocation(s.lastLat!, s.lastLng!, force: true);
    });

    // Don't wait for the first movement to show something.
    _pushCurrentFix();
  }

  void stopLocationTracking() {
    _positionSub?.cancel();
    _positionSub = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _lastWriteAt = null;
  }

  Future<void> _pushCurrentFix() async {
    try {
      final position = await _locationService.getCurrentPosition();
      await _pushLocation(position.latitude, position.longitude, force: true);
    } catch (e) {
      debugPrint('NonResidentProvider: initial fix failed: $e');
    }
  }

  /// Writes a position to the session row and updates local state.
  ///
  /// [force] bypasses the write-rate limit — used for the initial fix and the
  /// standing-still heartbeat, which must always land.
  Future<void> _pushLocation(double lat, double lng,
      {bool force = false}) async {
    final session = _session;
    if (session == null) return;

    final now = DateTime.now();
    if (!force &&
        _lastWriteAt != null &&
        now.difference(_lastWriteAt!) < _minWriteGap) {
      return;
    }
    _lastWriteAt = now;

    // Update the UI immediately — the marker should track the user even if
    // the network write is slow or fails.
    _session = session.copyWith(
      lastLat: lat,
      lastLng: lng,
      lastLocationAt: now,
    );
    _safeNotify();

    try {
      await _service.updateLocation(session.id, lat, lng);
    } catch (e) {
      // A single failed write is not fatal — the barangay sees a stale
      // timestamp and the next emission retries.
      debugPrint('NonResidentProvider: location push failed: $e');
    }
  }

  // ── Sign out ──────────────────────────────────────────────────────────
  /// Ends the session. Refuses while a report is in flight — logout is locked
  /// so a bogus reporter cannot vanish mid-report.
  Future<bool> signOut({bool force = false}) async {
    if (isLogoutLocked && !force) return false;
    stopLocationTracking();
    _stopWatchingResponders();
    _sessionSub?.cancel();
    _sessionResubscribeTimer?.cancel();
    _sessionSub = null;
    _pendingStatusAnnouncement = null;
    try {
      await _service.endSession();
    } catch (e) {
      debugPrint('NonResidentProvider: sign out failed: $e');
    }
    _session = null;
    _error = null;
    _safeNotify();
    return true;
  }

  void clearError() {
    _error = null;
    _safeNotify();
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
    stopLocationTracking();
    _stopWatchingResponders();
    _sessionSub?.cancel();
    // One-shot retry timer. Harmless if it fires (it checks _disposed) but a
    // timer outliving its provider is exactly the shape of a leak.
    _sessionResubscribeTimer?.cancel();
    super.dispose();
  }
}
