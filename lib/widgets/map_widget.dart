import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/incident_model.dart';
import '../config/app_config.dart';
import '../widgets/app_map_attribution.dart';
import '../utils/constants.dart';
import '../utils/helpers.dart';
import '../l10n/app_strings.dart';
import 'app_tile_layer.dart';
import '../utils/severity.dart';
import '../widgets/app_text.dart';

class IncidentMapWidget extends StatelessWidget {
  final List<IncidentModel> incidents;
  final double? centerLat;
  final double? centerLng;
  final double zoom;
  final void Function(IncidentModel)? onMarkerTap;
  final MapController? mapController;
  final LatLng? userLocation;
  final bool showUserLocation;

  const IncidentMapWidget({
    super.key,
    required this.incidents,
    this.centerLat,
    this.centerLng,
    this.zoom = 14.0,
    this.onMarkerTap,
    this.mapController,
    this.userLocation,
    this.showUserLocation = false,
  });

  @override
  Widget build(BuildContext context) {
    final center = LatLng(
      centerLat ?? AppConfig.defaultLatitude,
      centerLng ?? AppConfig.defaultLongitude,
    );

    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        maxZoom: 18.0,
        minZoom: 10.0,
      ),
      children: [
        // OSM tile layer
        const AppTileLayer(),
        const AppMapAttribution(),

        // User location marker
        if (showUserLocation && userLocation != null)
          MarkerLayer(
            markers: [
              Marker(
                point: userLocation!,
                width: 30,
                height: 30,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.blue, width: 2),
                  ),
                  child: const Center(
                    child: Icon(Icons.my_location, size: 16, color: Colors.blue),
                  ),
                ),
              ),
            ],
          ),

        // Incident markers — custom severity pins with proximity clustering
        MarkerLayer(
          markers: _buildMarkers(context, incidents),
        ),
      ],
    );
  }

  List<Marker> _buildMarkers(BuildContext context, List<IncidentModel> incidents) {
    // Bucket incidents into a ~0.003°-wide grid so nearby ones cluster in a
    // single O(n) pass instead of comparing every incident against every
    // other (O(n²)) on every rebuild — this got expensive as the list grew
    // and re-ran on every provider notification, not just real data changes.
    const cellSize = 0.003;
    final grid = <String, List<IncidentModel>>{};
    for (final incident in incidents) {
      final cellX = (incident.longitude / cellSize).floor();
      final cellY = (incident.latitude / cellSize).floor();
      grid.putIfAbsent('$cellX:$cellY', () => []).add(incident);
    }

    final markers = <Marker>[];
    for (final cluster in grid.values) {
      // Use highest severity (lowest number) as the representative
      cluster.sort((a, b) => a.severityLevel.compareTo(b.severityLevel));
      final rep = cluster.first;
      final color = severityColor(rep.severityLevel);
      final pinSize = _pinSize(rep.severityLevel);

      markers.add(Marker(
        // Keyed on the representative incident so Flutter preserves the pin's
        // animation state (esp. the radar pulse) across unrelated rebuilds,
        // instead of tearing down and recreating it every time.
        key: ValueKey(rep.id),
        point: LatLng(rep.latitude, rep.longitude),
        width: pinSize + 16,
        height: pinSize + 20,
        child: GestureDetector(
          onTap: () {
            if (cluster.length > 1) {
              _showClusterSheet(context, cluster);
            } else {
              onMarkerTap?.call(rep);
            }
          },
          child: RepaintBoundary(
            child: _SeverityPin(
              severityLevel: rep.severityLevel,
              color: color,
              clusterCount: cluster.length > 1 ? cluster.length : null,
            ),
          ),
        ),
      ));
    }

    return markers;
  }

  void _showClusterSheet(BuildContext context, List<IncidentModel> cluster) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => _ClusterSheet(
        incidents: cluster,
        onSelect: (incident) {
          Navigator.pop(context);
          onMarkerTap?.call(incident);
        },
      ),
    );
  }

  double _pinSize(int level) {
    switch (level) {
      case 1: return 46;
      case 2: return 42;
      case 3: return 38;
      default: return 34;
    }
  }
}

// ── Custom severity pin marker ───────────────────────────────────────────────
class _SeverityPin extends StatefulWidget {
  final int severityLevel;
  final Color color;
  final int? clusterCount;

  const _SeverityPin({
    required this.severityLevel,
    required this.color,
    this.clusterCount,
  });

  @override
  State<_SeverityPin> createState() => _SeverityPinState();
}

class _SeverityPinState extends State<_SeverityPin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    if (Severity.isCritical(widget.severityLevel)) _pulseCtrl.repeat();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  IconData get _icon {
    switch (widget.severityLevel) {
      case Severity.critical: return Icons.warning_rounded;
      case Severity.high: return Icons.report_rounded;
      case Severity.medium: return Icons.info_rounded;
      default: return Icons.location_on_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Worse incidents draw a bigger pin, so a map read at a glance ranks
    // itself. Sizes stay tied to the named levels rather than raw numbers.
    final size = switch (widget.severityLevel) {
      Severity.critical => 46.0,
      Severity.high => 42.0,
      Severity.medium => 38.0,
      _ => 34.0,
    };

    return Stack(
      alignment: Alignment.topCenter,
      children: [
        // Radar pulse rings — critical only
        if (Severity.isCritical(widget.severityLevel)) ...[
          _PulseRing(ctrl: _pulseCtrl, color: widget.color, delay: 0.0, pinSize: size),
          _PulseRing(ctrl: _pulseCtrl, color: widget.color, delay: 0.33, pinSize: size),
          _PulseRing(ctrl: _pulseCtrl, color: widget.color, delay: 0.66, pinSize: size),
        ],

        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Circle head
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.55),
                    blurRadius: 14,
                    spreadRadius: 1,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(_icon, color: Colors.white, size: size * 0.46),
            ),
            // Triangle tail
            CustomPaint(
              size: const Size(14, 9),
              painter: _TrianglePainter(color: widget.color),
            ),
          ],
        ),

        // Cluster count badge
        if (widget.clusterCount != null)
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.textPrimary,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: AppText(
                '${widget.clusterCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Radar pulse ring ─────────────────────────────────────────────────────────
class _PulseRing extends StatelessWidget {
  final AnimationController ctrl;
  final Color color;
  final double delay;
  final double pinSize;

  const _PulseRing({
    required this.ctrl,
    required this.color,
    required this.delay,
    required this.pinSize,
  });

  @override
  Widget build(BuildContext context) {
    final anim = CurvedAnimation(
      parent: ctrl,
      curve: Interval(delay, (delay + 0.67).clamp(0.0, 1.0), curve: Curves.easeOut),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) {
        final t = anim.value;
        final radius = pinSize * (0.5 + t * 1.1);
        return SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: (1 - t) * 0.55),
                width: 1.8,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Triangle tail painter ────────────────────────────────────────────────────
class _TrianglePainter extends CustomPainter {
  final Color color;
  const _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
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

// ── Cluster bottom sheet ─────────────────────────────────────────────────────

class _ClusterSheet extends StatelessWidget {
  final List<IncidentModel> incidents;
  final void Function(IncidentModel) onSelect;

  const _ClusterSheet({required this.incidents, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      padding: EdgeInsets.fromLTRB(0, 12, 0, safeBottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: AppText(
                    '${incidents.length}',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Incidents at this location',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.divider),
          // Incident list
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              shrinkWrap: true,
              itemCount: incidents.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 20, endIndent: 20, color: AppColors.divider),
              itemBuilder: (ctx, i) {
                final inc = incidents[i];
                final color = severityColor(inc.severityLevel);
                return GestureDetector(
                  onTap: () => onSelect(inc),
                  child: Container(
                    color: Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Row(
                      children: [
                        // Severity dot
                        Container(
                          width: 10, height: 10,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 12),
                        // Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppText(
                                categoryLabel(context.s, inc.category),
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              AppText(
                                inc.description.length > 60
                                    ? '${inc.description.substring(0, 60)}…'
                                    : inc.description,
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      severityLabel(inc.severityLevel),
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: color,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceSecondary,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      statusLabelFor(context.s, inc.status),
                                      style: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    timeAgo(inc.createdAt),
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 11,
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right_rounded,
                            size: 18, color: AppColors.textTertiary),
                      ],
                    ),
                  ),
                )
                    .animate(delay: Duration(milliseconds: 60 + i * 40))
                    .fadeIn(duration: 240.ms)
                    .slideX(begin: 0.04, end: 0, duration: 260.ms, curve: Curves.easeOutCubic);
              },
            ),
          ),
        ],
      ),
    ).animate().slideY(begin: 0.18, end: 0, duration: 380.ms, curve: Curves.easeOutBack);
  }
}

/// A simple map for picking a location.
class LocationPickerMap extends StatefulWidget {
  final LatLng initialPosition;
  final void Function(LatLng) onLocationSelected;

  const LocationPickerMap({
    super.key,
    required this.initialPosition,
    required this.onLocationSelected,
  });

  @override
  State<LocationPickerMap> createState() => _LocationPickerMapState();
}

class _LocationPickerMapState extends State<LocationPickerMap> {
  late LatLng _selectedPosition;

  @override
  void initState() {
    super.initState();
    _selectedPosition = widget.initialPosition;
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
        initialCenter: _selectedPosition,
        initialZoom: 16.0,
        onTap: (tapPos, latLng) {
          setState(() {
            _selectedPosition = latLng;
          });
          widget.onLocationSelected(latLng);
        },
      ),
      children: [
        const AppTileLayer(),
        const AppMapAttribution(),
        MarkerLayer(
          markers: [
            Marker(
              point: _selectedPosition,
              width: 40,
              height: 40,
              child: const Icon(
                Icons.location_pin,
                size: 40,
                color: Colors.red,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
