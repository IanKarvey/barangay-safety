import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/location_service.dart';
import '../../utils/constants.dart';
import '../../l10n/app_strings.dart';
import '../../utils/helpers.dart';
import '../../widgets/app_tile_layer.dart';
import '../../widgets/app_map_attribution.dart';
import '../../widgets/app_text.dart';

/// One point being tracked on the map.
class TrackedPoint {
  final String id;
  final String label;
  final String? sublabel;
  final double lat;
  final double lng;
  final DateTime? updatedAt;
  final Color color;
  final IconData icon;

  /// Draws expanding radar rings — used for the party in distress so the eye
  /// goes to them first.
  final bool pulsing;

  const TrackedPoint({
    required this.id,
    required this.label,
    this.sublabel,
    required this.lat,
    required this.lng,
    this.updatedAt,
    required this.color,
    required this.icon,
    this.pulsing = false,
  });

  LatLng get latLng => LatLng(lat, lng);
}

/// Full-screen live tracking map.
///
/// Deliberately in-app rather than deep-linking to Google Maps: handing the
/// user off to another app loses the live updates, the distance readout and
/// the context of who they are looking at. Everything stays here.
///
/// Rebuilds whenever [pointsStream] emits, so markers move as the underlying
/// positions change.
class LiveTrackingScreen extends StatefulWidget {
  final String title;

  /// Emits the current set of points. Re-emit to move the markers.
  final Stream<List<TrackedPoint>> pointsStream;

  /// Shown once before the first stream event.
  final List<TrackedPoint> initialPoints;

  /// Whether to plot the viewer's own device position too.
  final bool showMyLocation;

  /// Optional phone number for the call button.
  final String? callNumber;

  const LiveTrackingScreen({
    super.key,
    required this.title,
    required this.pointsStream,
    this.initialPoints = const [],
    this.showMyLocation = true,
    this.callNumber,
  });

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final _locationService = LocationService();

  late List<TrackedPoint> _points;
  StreamSubscription<List<TrackedPoint>>? _pointsSub;

  LatLng? _myLocation;
  StreamSubscription? _mySub;

  /// Auto-fits the camera to all points until the user pans, then stops
  /// fighting them for control.
  bool _autoFit = true;
  bool _hasFittedOnce = false;

  late final AnimationController _pulseCtrl;

  /// Redraws the "updated Ns ago" labels while no new data arrives.
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    _points = widget.initialPoints;

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _pointsSub = widget.pointsStream.listen((points) {
      if (!mounted) return;
      setState(() => _points = points);
      if (_autoFit) _fitAll();
    });

    if (widget.showMyLocation) _trackMyLocation();

    _tickTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  Future<void> _trackMyLocation() async {
    try {
      final pos = await _locationService.getCurrentPosition();
      if (!mounted) return;
      setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
      if (_autoFit) _fitAll();

      _mySub = _locationService.getPositionStream().listen((pos) {
        if (!mounted) return;
        setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
      });
    } catch (e) {
      // Not fatal — the tracked points are the important part; the viewer's
      // own position is a convenience.
      debugPrint('LiveTracking: could not get my location: $e');
    }
  }

  @override
  void dispose() {
    _pointsSub?.cancel();
    _mySub?.cancel();
    _tickTimer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _fitAll() {
    final all = <LatLng>[
      ..._points.map((p) => p.latLng),
      if (_myLocation != null) _myLocation!,
    ];
    if (all.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (all.length == 1) {
        _mapController.move(all.first, _hasFittedOnce ? _mapController.camera.zoom : 17.0);
      } else {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(all),
            padding: const EdgeInsets.fromLTRB(60, 140, 60, 220),
          ),
        );
      }
      _hasFittedOnce = true;
    });
  }

  /// Straight-line distance from the viewer to a tracked point.
  double? _distanceMetersTo(TrackedPoint p) {
    if (_myLocation == null) return null;
    return _locationService.distanceBetween(
        _myLocation!.latitude, _myLocation!.longitude, p.lat, p.lng);
  }

  @override
  Widget build(BuildContext context) {
    final primary = _points.isNotEmpty ? _points.first : null;
    final distance = primary != null ? _distanceMetersTo(primary) : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: primary?.latLng ??
                  _myLocation ??
                  const LatLng(13.9411, 121.1632),
              initialZoom: 16.0,
              maxZoom: 18.0,
              minZoom: 10.0,
              // Any manual interaction hands control to the user.
              onPointerDown: (_, __) {
                if (_autoFit) setState(() => _autoFit = false);
              },
            ),
            children: [
              const AppTileLayer(),
              const AppMapAttribution(),

              // Line between viewer and the primary tracked point, so the
              // relationship is readable at a glance.
              if (_myLocation != null && primary != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [_myLocation!, primary.latLng],
                      strokeWidth: 3,
                      color: primary.color.withValues(alpha: 0.55),
                      isDotted: true,
                    ),
                  ],
                ),

              // Radar rings under pulsing points
              MarkerLayer(
                markers: [
                  for (final p in _points.where((p) => p.pulsing))
                    Marker(
                      key: ValueKey('pulse_${p.id}'),
                      point: p.latLng,
                      width: 120,
                      height: 120,
                      child: IgnorePointer(
                        child: _RadarRings(ctrl: _pulseCtrl, color: p.color),
                      ),
                    ),
                ],
              ),

              MarkerLayer(
                markers: [
                  if (_myLocation != null)
                    Marker(
                      key: const ValueKey('me'),
                      point: _myLocation!,
                      width: 44,
                      height: 44,
                      child: const _MeMarker(),
                    ),
                  for (final p in _points)
                    Marker(
                      key: ValueKey(p.id),
                      point: p.latLng,
                      width: 52,
                      height: 62,
                      child: GestureDetector(
                        onTap: () => _showPointSheet(p),
                        child: _PointMarker(point: p),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Header
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                children: [
                  _RoundButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.10),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: AppText(
                              widget.title,
                              style: AppTextStyles.body
                                  .copyWith(fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const _LiveDot(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom edge: map controls above the info panel ────────────
          //
          // Was two `Positioned` widgets with hand-tuned offsets — the panel
          // pinned at bottom 20 and the controls at bottom 170. Two ways that
          // broke on a real device:
          //
          //   1. `_InfoPanel` grows with the responder's name and the
          //      distance string, and with the phone's font scale. Past
          //      ~150px tall it ran under the controls, and since the
          //      controls are right-aligned they landed on the panel's Call
          //      button — the same fault reported on the non-resident screen.
          //   2. The two used *different* conditions. The controls lifted on
          //      `distance != null || _points.isNotEmpty`, the panel appeared
          //      on `primary != null`. When those disagreed the controls
          //      floated 170px up with nothing beneath them.
          //
          // A Column settles both: the controls sit above whatever is
          // actually rendered, and there is only one condition left.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 14, bottom: 14),
                    child: Column(
                      children: [
                        _RoundButton(
                          icon: Icons.zoom_out_map_rounded,
                          tint: _autoFit
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          tooltip: context.s.fitEveryone,
                          onTap: () {
                            setState(() => _autoFit = true);
                            _fitAll();
                            HapticFeedback.selectionClick();
                          },
                        ),
                        const SizedBox(height: 10),
                        _RoundButton(
                          icon: Icons.my_location_rounded,
                          tooltip: context.s.centerOnMe,
                          onTap: () {
                            if (_myLocation == null) return;
                            setState(() => _autoFit = false);
                            _mapController.move(_myLocation!, 17.0);
                            HapticFeedback.selectionClick();
                          },
                        ),
                      ],
                    ),
                  ),

                  // Distance / call panel
                  if (primary != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                      child: _InfoPanel(
                        point: primary,
                        distanceMeters: distance,
                        callNumber: widget.callNumber,
                        onCall: widget.callNumber == null
                            ? null
                            : () => _call(widget.callNumber!),
                      ),
                    )
                  else
                    const SizedBox(height: 26),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _call(String number) async {
    try {
      await launchUrl(Uri.parse('tel:$number'));
    } catch (_) {
      if (mounted) showErrorSnackbar(context, 'Could not open the dialer.');
    }
  }

  void _showPointSheet(TrackedPoint p) {
    HapticFeedback.selectionClick();
    final dist = _distanceMetersTo(p);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
            24, 12, 24, MediaQuery.of(ctx).padding.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: p.color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(p.icon, color: p.color, size: 28),
            ),
            const SizedBox(height: 14),
            AppText(p.label, style: AppTextStyles.heading3),
            if (p.sublabel != null) ...[
              const SizedBox(height: 4),
              AppText(p.sublabel!, style: AppTextStyles.bodySmall),
            ],
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _MiniStat(
                  label: context.s.distance,
                  value: dist != null ? formatDistance(dist) : '—',
                ),
                _MiniStat(
                  label: context.s.lastUpdate,
                  value: p.updatedAt != null ? timeAgo(p.updatedAt!) : '—',
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.center_focus_strong_rounded, size: 18),
                label: Text(context.s.centerOnThis),
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() => _autoFit = false);
                  _mapController.move(p.latLng, 18.0);
                },
              ),
            ),
          ],
        ),
      ).animate().slideY(
          begin: 0.2, end: 0, duration: 360.ms, curve: Curves.easeOutBack),
    );
  }
}

// ── Info panel ──────────────────────────────────────────────────────────────
class _InfoPanel extends StatelessWidget {
  final TrackedPoint point;
  final double? distanceMeters;
  final String? callNumber;
  final VoidCallback? onCall;

  const _InfoPanel({
    required this.point,
    this.distanceMeters,
    this.callNumber,
    this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final stale = point.updatedAt == null ||
        DateTime.now().difference(point.updatedAt!) >
            const Duration(minutes: 2);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.13),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: point.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(point.icon, color: point.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(point.label,
                        style: AppTextStyles.body
                            .copyWith(fontWeight: FontWeight.w700)),
                    AppText(
                      point.updatedAt != null
                          ? 'Updated ${timeAgo(point.updatedAt!)}'
                          : 'No location yet',
                      style: AppTextStyles.caption.copyWith(
                        color: stale ? AppColors.error : null,
                        fontWeight: stale ? FontWeight.w600 : null,
                      ),
                    ),
                  ],
                ),
              ),
              if (onCall != null)
                IconButton(
                  icon: const Icon(Icons.phone_rounded,
                      color: AppColors.success),
                  tooltip: context.s.call,
                  onPressed: onCall,
                ),
            ],
          ),
          if (distanceMeters != null) ...[
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.straighten_rounded,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    '${formatDistance(distanceMeters!)} away',
                    key: ValueKey(formatDistance(distanceMeters!)),
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 340.ms)
        .slideY(begin: 0.3, end: 0, curve: Curves.easeOutBack);
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppText(value,
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        AppText(label, style: AppTextStyles.caption),
      ],
    );
  }
}

// ── Markers ─────────────────────────────────────────────────────────────────
class _PointMarker extends StatelessWidget {
  final TrackedPoint point;
  const _PointMarker({required this.point});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: point.color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: point.color.withValues(alpha: 0.5),
                blurRadius: 14,
                spreadRadius: 1,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(point.icon, color: Colors.white, size: 20),
        ),
        CustomPaint(
          size: const Size(12, 8),
          painter: _PinTailPainter(color: point.color),
        ),
      ],
    );
  }
}

class _MeMarker extends StatelessWidget {
  const _MeMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.22),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.primary, width: 3),
      ),
      child: const Icon(Icons.person_pin_circle_rounded,
          size: 20, color: AppColors.primary),
    );
  }
}

class _PinTailPainter extends CustomPainter {
  final Color color;
  const _PinTailPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    // ui.Path — bare `Path` resolves to flutter_map's Path<LatLng> here.
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Three staggered expanding rings — draws the eye to the party in distress.
class _RadarRings extends StatelessWidget {
  final AnimationController ctrl;
  final Color color;
  const _RadarRings({required this.ctrl, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        return Stack(
          alignment: Alignment.center,
          children: List.generate(3, (i) {
            final t = (ctrl.value + i / 3) % 1.0;
            final size = 26 + t * 94;
            return Opacity(
              opacity: (1 - t).clamp(0.0, 1.0) * 0.5,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: Tween<double>(begin: 0.3, end: 1).animate(_c),
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(context.s.live,
            style: AppTextStyles.caption.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.success,
              fontSize: 10,
            )),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? tint;
  final String? tooltip;

  const _RoundButton({
    required this.icon,
    required this.onTap,
    this.tint,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Icon(icon, size: 21, color: tint ?? AppColors.textPrimary),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
