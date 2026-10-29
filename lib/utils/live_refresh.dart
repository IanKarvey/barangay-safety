import 'dart:async';

import 'package:flutter/widgets.dart';

/// Keeps a screen's data current without the user leaving and coming back.
///
/// ## The problem this solves
///
/// Several screens loaded their data once in `initState` and never again:
/// the officials' Users tab, the superadmin's account tabs, the resident's
/// pending-verification screen, analytics, the map tab. An official who
/// verified someone still saw them as pending; a resident whose ID was
/// approved still saw "waiting"; a new registration never appeared. The only
/// way to see the truth was to log out and back in, which is what was reported
/// on 2026-08-25.
///
/// ## Why not realtime alone
///
/// Supabase realtime is the right primary mechanism and is used where it
/// works. But it fails *silently* in two ways that matter here:
///
///   1. A table absent from the `supabase_realtime` publication delivers
///      nothing at all, with **no error** — this project has already lost days
///      to that once, on `non_resident_sessions`.
///   2. Mobile sockets drop constantly. Without a resubscribe the stream is
///      dead until the app restarts.
///
/// Both failures look identical to the user: a screen that never changes. So
/// realtime gets a floor under it rather than being trusted on its own.
///
/// ## What this does
///
/// Refreshes when the app returns to the foreground, and on a slow timer while
/// the screen is actually the one being looked at. Neither is a substitute for
/// realtime — they are the guarantee that a screen is never more than one
/// interval stale even when realtime is completely down.
mixin LiveRefreshMixin<T extends StatefulWidget> on State<T> {
  Timer? _pollTimer;
  _LifecycleForwarder? _forwarder;
  bool _inFlight = false;

  /// Re-read this screen's data. Called on resume and on each tick.
  ///
  /// Must be safe to call repeatedly and concurrently with itself — the mixin
  /// already guards against overlap, but should not throw either.
  Future<void> onLiveRefresh();

  /// How often to re-read while the screen is visible.
  ///
  /// 20 seconds by default: frequent enough that an official is never looking
  /// at a stale roster for long, slow enough that it is not a meaningful
  /// battery or database cost. Screens where staleness is more expensive can
  /// shorten it.
  Duration get livePollInterval => const Duration(seconds: 20);

  void startLiveRefresh() {
    stopLiveRefresh();
    _forwarder = _LifecycleForwarder(_onResumed);
    WidgetsBinding.instance.addObserver(_forwarder!);
    _pollTimer = Timer.periodic(livePollInterval, (_) => _tick());
  }

  void stopLiveRefresh() {
    _pollTimer?.cancel();
    _pollTimer = null;
    final f = _forwarder;
    if (f != null) {
      WidgetsBinding.instance.removeObserver(f);
      _forwarder = null;
    }
  }

  /// Coming back from the background is the single most likely moment for the
  /// screen to be wrong, so it refreshes regardless of route position.
  void _onResumed() => _tick(force: true);

  Future<void> _tick({bool force = false}) async {
    if (!mounted || _inFlight) return;

    // Don't poll a screen buried under a dialog or another route — it costs
    // queries for something nobody is reading, and it can fight with whatever
    // is on top of it.
    if (!force) {
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
    }

    _inFlight = true;
    try {
      await onLiveRefresh();
    } catch (_) {
      // A background refresh must never surface an error over a screen the
      // user is reading. The next tick tries again.
    } finally {
      _inFlight = false;
    }
  }

  @override
  void dispose() {
    stopLiveRefresh();
    super.dispose();
  }
}

class _LifecycleForwarder extends WidgetsBindingObserver {
  _LifecycleForwarder(this.onResumed);

  final VoidCallback onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }
}
