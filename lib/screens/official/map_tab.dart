import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../providers/auth_provider.dart';
import '../../providers/incident_provider.dart';
import '../../models/incident_model.dart';
import '../../config/app_config.dart';
import '../../utils/constants.dart';
import '../../utils/permissions.dart';
import '../../l10n/app_strings.dart';
import '../../utils/helpers.dart';
import '../../widgets/widgets.dart';
import '../../widgets/app_text.dart';

class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  String? _selectedStatus;
  int? _selectedSeverity;
  final MapController _mapController = MapController();

  void _fitAllMarkers(List<IncidentModel> incidents) {
    if (incidents.isEmpty) return;
    final points = incidents.map((i) => LatLng(i.latitude, i.longitude)).toList();
    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(72)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    // Scoped to just the incidents list — avoids rebuilding the whole map
    // (and re-running clustering) on unrelated provider notifies like
    // stats/myIncidents/loading-flag changes.
    final incidents = visibleIncidents(
      context.read<AuthProvider>().user,
      context.select<IncidentProvider, List<IncidentModel>>((p) => p.incidents),
    );

    // Apply local filters — resolved incidents are hidden by default
    List<IncidentModel> filtered = incidents.where((i) {
      final statusOk = _selectedStatus == null
          ? i.status != 'resolved'          // default: active only
          : i.status == _selectedStatus;
      if (!statusOk) return false;
      if (_selectedSeverity != null && i.severityLevel != _selectedSeverity) return false;
      return true;
    }).toList();

    // Determine map center from user's barangay
    double? centerLat;
    double? centerLng;
    if (user?.barangayName != null) {
      final coords = AppConfig.barangayCenters[user!.barangayName];
      centerLat = coords?['lat'];
      centerLng = coords?['lng'];
    }

    return SafeArea(
      child: Column(
        children: [
          // Filter bar
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.map_rounded, color: AppColors.primary),
                    const SizedBox(width: 8),
                    AppText(context.s.incidentMap, style: AppTextStyles.heading3),
                    const Spacer(),
                    Text(
                      '${filtered.length} active pin${filtered.length == 1 ? '' : 's'}',
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('Active', _selectedStatus == null, () {
                        setState(() => _selectedStatus = null);
                      }),
                      _filterChip('Pending', _selectedStatus == 'pending', () {
                        setState(() => _selectedStatus = _selectedStatus == 'pending' ? null : 'pending');
                      }),
                      _filterChip('In Progress', _selectedStatus == 'in_progress', () {
                        setState(() => _selectedStatus = _selectedStatus == 'in_progress' ? null : 'in_progress');
                      }),
                      _filterChip('Resolved', _selectedStatus == 'resolved', () {
                        setState(() => _selectedStatus = _selectedStatus == 'resolved' ? null : 'resolved');
                      }),
                      const SizedBox(width: 8),
                      Container(width: 1, height: 24, color: AppColors.divider),
                      const SizedBox(width: 8),
                      ...List.generate(4, (i) {
                        final level = i + 1;
                        return _filterChip(
                          'L$level',
                          _selectedSeverity == level,
                          () {
                            setState(() {
                              _selectedSeverity = _selectedSeverity == level ? null : level;
                            });
                          },
                          color: severityColor(level),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Map + FAB overlay
          Expanded(
            child: Stack(
              children: [
                IncidentMapWidget(
                  incidents: filtered,
                  centerLat: centerLat,
                  centerLng: centerLng,
                  zoom: 15.0,
                  mapController: _mapController,
                  onMarkerTap: (incident) {
                    _mapController.move(
                      LatLng(incident.latitude, incident.longitude),
                      17.0,
                    );
                    _showIncidentQuickView(context, incident);
                  },
                ),
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: Column(
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'fit_map_official',
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primary,
                        tooltip: context.s.fitAllIncidents,
                        onPressed: () => _fitAllMarkers(filtered),
                        child: const Icon(Icons.fit_screen_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap, {Color? color}) {
    final chipColor = color ?? AppColors.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? chipColor.withValues(alpha: 0.15) : AppColors.background,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? chipColor : AppColors.divider,
            ),
          ),
          child: AppText(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? chipColor : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  void _showIncidentQuickView(BuildContext context, IncidentModel incident) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                Row(
                  children: [
                    SeverityBadge(level: incident.severityLevel),
                    const SizedBox(width: 8),
                    StatusChip(status: incident.status),
                  ],
                ),
                const SizedBox(height: 12),
                AppText(categoryLabel(context.s, incident.category), style: AppTextStyles.heading3),
                const SizedBox(height: 4),
                Text(
                  incident.description,
                  style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                AppText(
                  'Reported ${timeAgo(incident.createdAt)}${incident.reporterName != null ? ' by ${incident.reporterName}' : ''}',
                  style: AppTextStyles.caption,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.pushNamed(
                        context,
                        '/incident-manage',
                        arguments: incident.id,
                      );
                    },
                    child: Text(context.s.manageIncident),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
