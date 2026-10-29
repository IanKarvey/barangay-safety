import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// One contribution to the heat surface.
class HeatPoint {
  final LatLng position;

  /// Relative influence. Severity-weighted so one critical incident reads
  /// hotter than one noise complaint — a plain count would make the busiest
  /// category look like the most dangerous place.
  final double weight;

  const HeatPoint({required this.position, this.weight = 1.0});
}

/// Density heat overlay for [FlutterMap].
///
/// Written directly against [CustomPainter] rather than pulling in a heatmap
/// package: the plugins available for flutter_map 6.x either lag the API or
/// add a transitive dependency tree for what is ~100 lines of canvas work.
///
/// Technique is the standard two-pass one:
///   1. Draw each point as a radial alpha gradient with [BlendMode.plus], so
///      overlapping points accumulate intensity in the alpha channel.
///   2. Recolour that accumulated alpha through a gradient ramp, so intensity
///      maps to blue → green → yellow → orange → red.
///
/// Both passes happen inside one `saveLayer` so the accumulation is isolated
/// from whatever is painted beneath.
class HeatmapLayer extends StatelessWidget {
  final List<HeatPoint> points;

  /// Influence radius of a single point, in screen pixels.
  final double radius;

  /// Overall layer opacity.
  final double opacity;

  const HeatmapLayer({
    super.key,
    required this.points,
    this.radius = 85,
    this.opacity = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    if (points.isEmpty) return const SizedBox.shrink();

    // SizedBox.expand rather than relying on Size.infinite alone — guarantees
    // the painter is handed the full map viewport regardless of how
    // FlutterMap lays its children out.
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _HeatmapPainter(
            points: points,
            camera: camera,
            radius: radius,
            opacity: opacity,
          ),
        ),
      ),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  final List<HeatPoint> points;
  final MapCamera camera;
  final double radius;
  final double opacity;

  _HeatmapPainter({
    required this.points,
    required this.camera,
    required this.radius,
    required this.opacity,
  });

  /// Per-point colour ramp, coolest at the fading edge and hottest at the
  /// core. Under [BlendMode.plus] overlapping blobs sum toward the hot end,
  /// so density — not screen position — drives the colour.
  ///
  /// (Recolouring accumulated alpha through a single gradient would tint by
  /// position instead of intensity; thresholding alpha per band needs a
  /// fragment shader, which is more machinery than this warrants.)
  static const _coreColor = Color(0xFFDC2626);   // red    — dense core
  static const _midColor = Color(0xFFF97316);    // orange — shoulder
  static const _edgeColor = Color(0xFF2563EB);   // blue   — isolated edge

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // One isolated layer so additive blending accumulates only between heat
    // points, never against the map tiles underneath.
    canvas.saveLayer(rect, Paint());

    for (final p in points) {
      final pt = camera.latLngToScreenPoint(p.position);
      final center = Offset(pt.x, pt.y);

      // Skip points comfortably outside the viewport.
      if (center.dx < -radius ||
          center.dy < -radius ||
          center.dx > size.width + radius ||
          center.dy > size.height + radius) {
        continue;
      }

      final w = p.weight.clamp(0.0, 1.0);

      // Heavier points reach slightly further — reads more naturally than
      // identical blobs differing only in brightness.
      final r = radius * (0.75 + 0.25 * w);

      // A single incident must be clearly visible on its own: barangay data
      // is sparse, so tuning these for dense overlap (as an earlier version
      // did) rendered lone reports at ~7% alpha — invisible in practice.
      // The floor guarantees one report still reads; overlap then pushes
      // toward red via BlendMode.plus.
      final coreAlpha = (0.9 * w).clamp(0.62, 1.0) * opacity;
      final midAlpha = coreAlpha * 0.68;
      final edgeAlpha = coreAlpha * 0.34;

      final paint = Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(
          center,
          r,
          [
            _coreColor.withValues(alpha: coreAlpha),
            _midColor.withValues(alpha: midAlpha),
            _edgeColor.withValues(alpha: edgeAlpha),
            _edgeColor.withValues(alpha: 0.0),
          ],
          const [0.0, 0.35, 0.7, 1.0],
        );

      canvas.drawCircle(center, r, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter old) {
    return old.points != points ||
        old.radius != radius ||
        old.opacity != opacity ||
        old.camera.zoom != camera.zoom ||
        old.camera.center != camera.center;
  }
}

/// Groups incidents into weighted heat points and finds the densest clusters.
class HeatmapAnalysis {
  /// Grid cell size in degrees for hotspot clustering (~330m).
  static const double _cellSize = 0.003;

  /// Highest-density locations, strongest first.
  ///
  /// Uses the same grid-bucket approach as the marker clustering so a
  /// "hotspot" here means the same thing a cluster pin means on the map.
  static List<Hotspot> topHotspots(
    List<HeatPoint> points, {
    int limit = 5,
  }) {
    if (points.isEmpty) return [];

    final grid = <String, List<HeatPoint>>{};
    for (final p in points) {
      final cx = (p.position.longitude / _cellSize).floor();
      final cy = (p.position.latitude / _cellSize).floor();
      grid.putIfAbsent('$cx:$cy', () => []).add(p);
    }

    final hotspots = grid.values.map((cluster) {
      final avgLat = cluster.map((p) => p.position.latitude).reduce((a, b) => a + b) /
          cluster.length;
      final avgLng = cluster.map((p) => p.position.longitude).reduce((a, b) => a + b) /
          cluster.length;
      final intensity = cluster.fold<double>(0, (sum, p) => sum + p.weight);
      return Hotspot(
        center: LatLng(avgLat, avgLng),
        count: cluster.length,
        intensity: intensity,
      );
    }).toList()
      ..sort((a, b) => b.intensity.compareTo(a.intensity));

    return hotspots.take(limit).toList();
  }

  /// Great-circle distance in metres, for labelling hotspots.
  static double distanceMeters(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    double toRad(double d) => d * math.pi / 180.0;
    final dLat = toRad(b.latitude - a.latitude);
    final dLng = toRad(b.longitude - a.longitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(toRad(a.latitude)) *
            math.cos(toRad(b.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }
}

class Hotspot {
  final LatLng center;
  final int count;
  final double intensity;

  const Hotspot({
    required this.center,
    required this.count,
    required this.intensity,
  });
}
