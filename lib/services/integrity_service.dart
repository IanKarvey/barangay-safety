import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Whether anything about how a report was filed warrants a second look.
class ReportIntegrity {
  /// Device had an active VPN transport when the report was filed.
  final bool viaVpn;

  /// Device reported the GPS fix as mocked — a location-spoofing app.
  final bool locationMocked;

  const ReportIntegrity({
    this.viaVpn = false,
    this.locationMocked = false,
  });

  bool get hasConcern => viaVpn || locationMocked;
}

/// §5 — integrity signals collected when a report is filed.
///
/// ## These flag, they never block
///
/// Refusing a report because a VPN is switched on would mean turning away a
/// real emergency from someone whose phone happens to route through one — and
/// pushing that emergency off the system entirely, which is strictly worse than
/// accepting it with a note attached. The Secretary already reviews every
/// report before anyone is dispatched, so a warning on their screen is both
/// safer and more useful than a locked door.
///
/// ## Mock location is the signal that matters
///
/// A VPN changes the IP address, not the GPS fix, and every location this app
/// depends on — the Lipa City geofence, the incident pin, responder tracking —
/// comes from GPS. A mock-location app is what actually lets someone file a
/// report from a place they are not. VPN is recorded because §5 asks for it and
/// it costs nothing, but it is the weaker of the two.
///
/// ## Platform limits, stated honestly
///
/// Android reports both reliably. **iOS reports neither**: `isMocked` is always
/// false there, and iOS gives no supported way to detect a VPN. Any claim that
/// this app "detects VPNs" is an Android-only claim, and a determined user can
/// defeat it on either platform. It raises the effort required; it is not a
/// guarantee.
class IntegrityService {
  final Connectivity _connectivity;

  IntegrityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  /// Collects the signals for a report being filed at [position].
  ///
  /// Never throws. A failed check returns "no concern" rather than blocking
  /// submission — an integrity check that can stop an emergency report is a
  /// worse problem than the one it solves.
  Future<ReportIntegrity> check(Position? position) async {
    return ReportIntegrity(
      viaVpn: await _isOnVpn(),
      locationMocked: position?.isMocked ?? false,
    );
  }

  Future<bool> _isOnVpn() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return results.contains(ConnectivityResult.vpn);
    } catch (e) {
      debugPrint('IntegrityService: VPN check unavailable: $e');
      return false;
    }
  }
}
