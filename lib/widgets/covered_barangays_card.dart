import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../services/covered_barangays_service.dart';
import '../utils/constants.dart';
import 'app_tile_layer.dart';
import 'responsive_layout.dart';

/// Which barangays this system covers, shown where people will see it.
///
/// Panel revision #4: display the covered areas and highlight the five barangays
/// with the most incident reports. The five come from [AppConfig.barangayCenters]
/// (the barangays the app actually routes reports to), so this can never show a
/// barangay the system does not serve.
///
/// ## Counts are optional
///
/// The ranking bars need a database function a resident cannot replace with a
/// query (see [SupabaseCoveredBarangaysSource]). If it has not been installed or
/// the load fails, the card still names and maps the five barangays, just
/// without numbers — the coverage is the point, the ranking is the detail.
class CoveredBarangaysCard extends StatefulWidget {
  const CoveredBarangaysCard({
    super.key,
    this.highlightName,
    this.source,
    this.showTiles = true,
  });

  /// The signed-in person's barangay, marked "You".
  final String? highlightName;

  /// Where counts come from; defaults to Supabase. Injectable for tests.
  final CoveredBarangaysSource? source;

  /// Whether to draw map tiles. Off in tests, where there is no network.
  final bool showTiles;

  @override
  State<CoveredBarangaysCard> createState() => _CoveredBarangaysCardState();
}

class _CoveredBarangaysCardState extends State<CoveredBarangaysCard> {
  late final CoveredBarangaysSource _source =
      widget.source ?? SupabaseCoveredBarangaysSource();

  late final Future<Map<String, int>?> _counts = _load();

  Future<Map<String, int>?> _load() async {
    try {
      return await _source.counts();
    } catch (_) {
      return null;
    }
  }

  static int _number(String name) =>
      int.tryParse(name.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: FutureBuilder<Map<String, int>?>(
        future: _counts,
        builder: (context, snap) {
          final counts = snap.data;
          final names = AppConfig.barangayCenters.keys.toList()
            ..sort((a, b) {
              final byCount =
                  (counts?[b] ?? 0).compareTo(counts?[a] ?? 0);
              return byCount != 0 ? byCount : _number(a).compareTo(_number(b));
            });
          final max = counts == null || counts.isEmpty
              ? 0
              : counts.values.reduce((a, b) => a > b ? a : b);

          Color tone(String name) {
            if (counts == null || max == 0) return AppColors.primary;
            return Color.lerp(
                  AppColors.primary,
                  AppColors.error,
                  ((counts[name] ?? 0) / max).clamp(0.0, 1.0),
                ) ??
                AppColors.primary;
          }

          final map = _CoverageMap(
            names: names,
            tone: tone,
            showTiles: widget.showTiles,
          );
          final list = _RankedList(
            names: names,
            counts: counts,
            max: max,
            highlightName: widget.highlightName,
            tone: tone,
            loading: snap.connectionState != ConnectionState.done,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, c) {
                  if (c.maxWidth >= kWideBreakpoint) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: SizedBox(height: 280, child: map)),
                        const SizedBox(width: 18),
                        Expanded(flex: 5, child: list),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      SizedBox(height: 190, child: map),
                      const SizedBox(height: 14),
                      list,
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.map_rounded,
                size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Covered Barangays',
                  style: AppTextStyles.heading3.copyWith(fontSize: 17),
                ),
                const SizedBox(height: 2),
                Text(
                  'The ${AppConfig.barangayCenters.length} Lipa City barangays '
                  'with the most incident reports — where this system is active.',
                  style: AppTextStyles.caption.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        ],
      );
}

/// The five barangays as highlighted zones on a map.
///
/// Not interactive: inside a scrolling page, a map that captures drags traps the
/// scroll. The point of it is to *see* where the coverage is, not to explore.
class _CoverageMap extends StatelessWidget {
  const _CoverageMap({
    required this.names,
    required this.tone,
    required this.showTiles,
  });

  final List<String> names;
  final Color Function(String) tone;
  final bool showTiles;

  @override
  Widget build(BuildContext context) {
    LatLng at(String n) {
      final c = AppConfig.barangayCenters[n]!;
      return LatLng(c['lat']!, c['lng']!);
    }

    final points = names.map(at).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: FlutterMap(
        options: MapOptions(
          backgroundColor: const Color(0xFFE4ECF5),
          initialCameraFit: CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.all(58),
            maxZoom: 16,
          ),
          interactionOptions:
              const InteractionOptions(flags: InteractiveFlag.none),
        ),
        children: [
          if (showTiles) const AppTileLayer(),
          CircleLayer(
            circles: [
              for (final n in names)
                CircleMarker(
                  point: at(n),
                  radius: 140,
                  useRadiusInMeter: true,
                  color: tone(n).withValues(alpha: 0.22),
                  borderColor: tone(n),
                  borderStrokeWidth: 2,
                ),
            ],
          ),
          MarkerLayer(
            markers: [
              for (final n in names)
                Marker(
                  point: at(n),
                  width: 30,
                  height: 30,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tone(n),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Text(
                      '${_CoveredBarangaysCardState._number(n)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The barangays in rank order, with a bar for each count.
class _RankedList extends StatelessWidget {
  const _RankedList({
    required this.names,
    required this.counts,
    required this.max,
    required this.highlightName,
    required this.tone,
    required this.loading,
  });

  final List<String> names;
  final Map<String, int>? counts;
  final int max;
  final String? highlightName;
  final Color Function(String) tone;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (i, n) in names.indexed)
          _row(rank: i + 1, name: n),
        if (counts == null && !loading)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Incident counts are unavailable right now.',
              style: AppTextStyles.caption,
            ),
          ),
      ],
    );
  }

  Widget _row({required int rank, required String name}) {
    final mine = name == highlightName;
    final color = tone(name);
    final count = counts?[name];
    final fraction =
        (count == null || max == 0) ? 0.0 : (count / max).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
      decoration: BoxDecoration(
        color: mine
            ? AppColors.primary.withValues(alpha: 0.07)
            : AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: mine
              ? AppColors.primary.withValues(alpha: 0.35)
              : AppColors.divider,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (mine) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'You',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (count != null) ...[
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 5,
                      backgroundColor: color.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 12),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
