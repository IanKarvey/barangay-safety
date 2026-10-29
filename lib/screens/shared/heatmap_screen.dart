import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../models/heat_incident_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/incident_service.dart';
import '../../config/app_config.dart';
import '../../utils/constants.dart';
import '../../l10n/app_strings.dart';
import '../../widgets/app_tile_layer.dart';
import '../../widgets/app_map_attribution.dart';
import '../../widgets/heatmap_layer.dart';
import '../../widgets/app_text.dart';

/// Which slice of incidents the heat surface is built from.
enum HeatLens {
  all('All Reports', Icons.layers_rounded, null),
  crime('Crime', Icons.gavel_rounded, {
    'Theft / Robbery',
    'Physical Assault',
    'Vandalism',
    'Suspicious Activity',
    'Drug-Related',
    'Domestic Violence',
  }),
  fire('Fire', Icons.local_fire_department_rounded, {'Fire'}),
  flood('Flooding', Icons.water_rounded, {'Flooding'}),
  accident('Accidents', Icons.car_crash_rounded, {
    'Vehicular Accident',
    'Medical Emergency',
  });

  const HeatLens(this.label, this.icon, this.categories);

  /// English fallback. Use [labelFor] for anything drawn on screen.
  final String label;

  String labelFor(AppStrings t) => switch (this) {
        HeatLens.all => t.lensAllReports,
        HeatLens.crime => t.lensCrime,
        HeatLens.fire => t.lensFire,
        HeatLens.flood => t.lensFlood,
        HeatLens.accident => t.lensAccidents,
      };

  final IconData icon;

  /// Null means "everything".
  final Set<String>? categories;

  bool matches(HeatIncident i) =>
      categories == null || categories!.contains(i.category);
}

/// Density map of where incidents actually happen.
///
/// Answers a question the pin map cannot: not "where was this one report"
/// but "where do reports keep happening" — which is what drives patrol
/// routing and budget decisions.
class HeatmapScreen extends StatefulWidget {
  final bool isSuperAdmin;

  const HeatmapScreen({super.key, this.isSuperAdmin = false});

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  final _incidentService = IncidentService();
  final _mapController = MapController();

  List<HeatIncident> _incidents = [];
  bool _isLoading = true;
  String? _error;

  HeatLens _lens = HeatLens.all;

  /// Days of history to include. Older incidents say less about where the
  /// problem is *now*.
  int _windowDays = 90;
  static const _windowOptions = [30, 90, 365, 0]; // 0 = all time

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final user = context.read<AuthProvider>().user;
      // Always via the RPC: RLS would otherwise limit a resident to their own
      // reports, and the RPC strips reporter/description/address before it
      // ever reaches the client.
      final data = await _incidentService.getHeatPoints(
        barangayId: widget.isSuperAdmin ? null : user?.barangayId,
      );
      if (!mounted) return;
      setState(() {
        _incidents = data;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Could not load incident data: $e';
      });
    }
  }

  List<HeatIncident> get _filtered {
    final cutoff = _windowDays == 0
        ? null
        : DateTime.now().subtract(Duration(days: _windowDays));
    return _incidents
        .where((i) => _lens.matches(i))
        .where((i) => cutoff == null || i.createdAt.isAfter(cutoff))
        .toList();
  }

  /// Severity-weighted so one critical incident reads hotter than one noise
  /// complaint. A plain count would make the noisiest street look like the
  /// most dangerous one.
  List<HeatPoint> get _heatPoints => _filtered
      .map((i) => HeatPoint(
            position: LatLng(i.lat, i.lng),
            weight: i.weight,
          ))
      .toList();

  void _fitToData() {
    final pts = _heatPoints.map((p) => p.position).toList();
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      _mapController.move(pts.first, 16);
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: const EdgeInsets.fromLTRB(50, 190, 50, 260),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final points = _heatPoints;
    final hotspots = HeatmapAnalysis.topHotspots(points, limit: 3);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(context.s.incidentHeatMap),
        actions: [
          IconButton(
            icon: const Icon(Icons.zoom_out_map_rounded),
            tooltip: context.s.fitToData,
            onPressed: _fitToData,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: context.s.refresh,
            onPressed: _load,
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: AppText(_error!,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall),
              ),
            )
          : Column(
              children: [
                _buildControls(),
                Expanded(
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: const MapOptions(
                          initialCenter: LatLng(
                            AppConfig.defaultLatitude,
                            AppConfig.defaultLongitude,
                          ),
                          initialZoom: 13.5,
                          maxZoom: 18,
                          minZoom: 10,
                        ),
                        children: [
                          const AppTileLayer(),
                          const AppMapAttribution(),
                          HeatmapLayer(points: points),
                        ],
                      ),

                      if (_isLoading)
                        const Center(child: CircularProgressIndicator()),

                      if (!_isLoading && points.isEmpty)
                        Center(
                          child: Container(
                            margin: const EdgeInsets.all(32),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 16,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.search_off_rounded,
                                    size: 34, color: AppColors.textTertiary),
                                const SizedBox(height: 10),
                                Text(
                                    context.s.nothingInPeriod(
                                        _lens.labelFor(context.s).toLowerCase()),
                                    style: AppTextStyles.bodySmall,
                                    textAlign: TextAlign.center),
                              ],
                            ),
                          ),
                        ),

                      // Legend
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: _buildLegend(points.length),
                      ),

                      // Hotspot ranking
                      if (hotspots.isNotEmpty)
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: _buildHotspots(hotspots),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildControls() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final lens in HeatLens.values) ...[
                  _chip(
                    label: lens.labelFor(context.s),
                    icon: lens.icon,
                    selected: _lens == lens,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _lens = lens);
                    },
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(context.s.period, style: AppTextStyles.caption),
                const SizedBox(width: 8),
                for (final d in _windowOptions) ...[
                  _chip(
                    label: d == 0 ? 'All time' : 'Last $d days',
                    selected: _windowDays == d,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _windowDays = d);
                    },
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.13)
              : AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 14,
                  color: selected ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(width: 5),
            ],
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppText('$count report${count == 1 ? '' : 's'}',
              style: AppTextStyles.caption
                  .copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Container(
            width: 120,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF2563EB),
                  Color(0xFFF97316),
                  Color(0xFFDC2626),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(context.s.isolated,
                    style: AppTextStyles.caption.copyWith(fontSize: 9)),
                Text(context.s.hotspot,
                    style: AppTextStyles.caption.copyWith(fontSize: 9)),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 320.ms).slideY(begin: 0.3, end: 0);
  }

  Widget _buildHotspots(List<Hotspot> hotspots) {
    return Container(
      width: 168,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.whatshot_rounded,
                  size: 14, color: AppColors.error),
              const SizedBox(width: 5),
              Text(context.s.topHotspots,
                  style: AppTextStyles.caption
                      .copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          for (int i = 0; i < hotspots.length; i++) ...[
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                _mapController.move(hotspots[i].center, 17);
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.error
                            .withValues(alpha: 0.16 + (0.16 * (2 - i))),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: AppText('${i + 1}',
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.error)),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: AppText(
                        '${hotspots[i].count} report${hotspots[i].count == 1 ? '' : 's'}',
                        style: AppTextStyles.caption,
                      ),
                    ),
                    const Icon(Icons.north_east_rounded,
                        size: 12, color: AppColors.textTertiary),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 320.ms).slideY(begin: 0.3, end: 0);
  }
}
