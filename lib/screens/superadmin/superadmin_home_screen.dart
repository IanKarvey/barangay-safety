import '../../widgets/id_photo_strip.dart';
import '../../utils/live_refresh.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/incident_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/responder_location_provider.dart';
import '../../services/user_management_service.dart';
import '../../models/user_model.dart';
import '../../models/incident_model.dart';
import '../../config/app_config.dart';
import '../../utils/constants.dart';
import '../../l10n/app_strings.dart';
import '../../utils/helpers.dart';
import '../../widgets/widgets.dart';
import '../../utils/severity.dart';
import '../../widgets/app_text.dart';

class SuperAdminHomeScreen extends StatefulWidget {
  const SuperAdminHomeScreen({super.key});

  @override
  State<SuperAdminHomeScreen> createState() => _SuperAdminHomeScreenState();
}

class _SuperAdminHomeScreenState extends State<SuperAdminHomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
      context.read<IncidentProvider>().subscribeToAll();
      context.read<NotificationProvider>().subscribe();
      // A killed app leaves is_sharing_location = true with stale coordinates
      // still published — a frozen pin the reporter reads as live help.
      final me = context.read<AuthProvider>().user;
      if (me != null) {
        context.read<ResponderLocationProvider>().reconcileOnStartup(
              userId: me.id,
              wasSharing: me.isSharingLocation,
            );
      }
    });
  }

  // _loadData() doubles as a refresh callback (pull-to-refresh, navigation
  // return) — the realtime subscription is established once above instead of
  // being torn down and recreated on every one of those calls.
  void _loadData() {
    final provider = context.read<IncidentProvider>();
    provider.loadAllIncidents();
    provider.loadStats(null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LazyIndexedStack(
        index: _currentIndex,
        children: [
          _SuperAdminDashboard(onRefresh: _loadData, onViewAll: () => setState(() => _currentIndex = 2)),
          _SuperAdminMapView(),
          _SuperAdminAllIncidents(onRefresh: _loadData),
          const _SuperAdminUserManagement(),
        ],
      ),
      bottomNavigationBar: AnimatedBottomNavBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: [
          AnimatedNavItem(icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard_rounded, label: context.s.overview_),
          AnimatedNavItem(icon: Icons.map_outlined, activeIcon: Icons.map_rounded, label: context.s.cityMap),
          AnimatedNavItem(icon: Icons.list_alt_outlined, activeIcon: Icons.list_alt_rounded, label: context.s.allReports),
          AnimatedNavItem(icon: Icons.admin_panel_settings_outlined, activeIcon: Icons.admin_panel_settings_rounded, label: context.s.admin),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Enhanced Dashboard
// ═══════════════════════════════════════════════════════════════════════════
class _SuperAdminDashboard extends StatelessWidget {
  final VoidCallback onRefresh;
  final VoidCallback? onViewAll;
  const _SuperAdminDashboard({required this.onRefresh, this.onViewAll});

  String _greeting(AppStrings s) {
    final h = DateTime.now().hour;
    if (h < 12) return s.goodMorning;
    if (h < 17) return s.goodAfternoon;
    return s.goodEvening;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IncidentProvider>();
    final stats = provider.stats;

    final total = stats['total'] ?? 0;
    final pending = stats['pending'] ?? 0;
    final inProgress = stats['in_progress'] ?? 0;
    final resolved = stats['resolved'] ?? 0;
    final flagged = stats['flagged'] ?? 0;
    final resolutionRate = total > 0 ? (resolved / total * 100).round() : 0;

    final urgentIncidents = provider.incidents
        .where((i) =>
            (i.isPending || i.isInProgress) &&
            Severity.isUrgent(i.severityLevel))
        .take(3)
        .toList();

    final counts = List.generate(
      4,
      (i) => provider.incidents
          .where((inc) => inc.severityLevel == i + 1 && inc.status != 'resolved')
          .length,
    );
    final maxCount = counts.fold(0, (a, b) => a > b ? a : b);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async => onRefresh(),
        child: CustomScrollView(
          slivers: [
            // ── Header ────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0D1B6B), Color(0xFF1A237E), Color(0xFF283593)],
                  ),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The identity block (badge, greeting, name, barangay/date)
                    // gets a Column entry ALL TO ITSELF — no sibling in the
                    // same Row, not even the language toggle.
                    //
                    // A prior pass moved the 5 IconButtons to their own row
                    // below this one but left LanguageToggle sharing this
                    // Row's space with the Expanded text column. That was
                    // still enough to starve it: on a typical phone width,
                    // ~110px for the toggle plus the 20px gap left well under
                    // the space "Administrator" at 22px bold needs, so
                    // Flutter still had no legal word-boundary break point and
                    // split the word itself — confirmed on-device 2026-09-16,
                    // the fix having genuinely shipped the night before but
                    // not actually closed the gap. Nothing may share this Row
                    // with the Expanded child again; the controls (toggle +
                    // icons) all live in the row below instead.
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.verified_rounded, color: Colors.amber, size: 12),
                              SizedBox(width: 4),
                              Text(
                                'SUPER ADMIN',
                                style: TextStyle(
                                  color: Colors.amber,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AppText(
                      _greeting(context.s),
                      style: AppTextStyles.body.copyWith(color: Colors.white70),
                    ),
                    // Full row width, no sibling — see the note above this
                    // Column. This single line is the one in the screenshot.
                    AppText(
                      context.s.cityAdministrator,
                      style: AppTextStyles.heading2.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.location_city_rounded, color: Colors.white60, size: 13),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            context.s.allBarangays,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySmall.copyWith(color: Colors.white70),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(Icons.calendar_today, color: Colors.white60, size: 12),
                        const SizedBox(width: 3),
                        Text(
                          DateFormat('MMM d, yyyy').format(DateTime.now()),
                          style: AppTextStyles.bodySmall.copyWith(color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Controls: language toggle + every icon button, all on
                    // one full-width row of their own — never sharing space
                    // with the identity text above.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        LanguageToggle(onDark: true),
                        const SizedBox(width: 4),
                        Consumer<NotificationProvider>(
                          builder: (context, notifProvider, _) => AnimatedNotifBell(
                            count: notifProvider.unreadCount,
                            iconColor: Colors.white70,
                            onTap: () => Navigator.pushNamed(context, '/notifications'),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.local_fire_department_rounded,
                              color: Colors.white70),
                          tooltip: context.s.heatMap,
                          onPressed: () => Navigator.pushNamed(
                            context,
                            '/heatmap',
                            arguments: true,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.bar_chart_rounded, color: Colors.white70),
                          tooltip: context.s.analytics,
                          onPressed: () => Navigator.pushNamed(
                            context,
                            '/analytics',
                            arguments: true,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.history_rounded, color: Colors.white70),
                          tooltip: context.s.activityLog,
                          onPressed: () => Navigator.pushNamed(
                            context,
                            '/audit-log',
                            arguments: {'title': context.s.activityLog},
                          ),
                        ),
                        // Account menu. Officials had no way to reach their
                        // own profile, help, or the privacy notice — every one
                        // of those was resident-only. Logout lives in here now
                        // rather than as a seventh icon in this row.
                        IconButton(
                          icon: const Icon(Icons.account_circle_rounded,
                              color: Colors.white70),
                          tooltip: context.s.myAccount,
                          onPressed: () => showAccountSheet(context),
                        ),
                      ],
                    ),
                    if (flagged > 0 || pending > 0) ...[
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: onViewAll,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                flagged > 0
                                    ? Icons.flag_rounded
                                    : Icons.notifications_active_rounded,
                                color: flagged > 0 ? Colors.amber : Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: AppText(
                                  flagged > 0
                                      ? '$flagged flagged report${flagged == 1 ? '' : 's'} need${flagged == 1 ? 's' : ''} review'
                                      : '$pending report${pending == 1 ? '' : 's'} awaiting action city-wide',
                                  style: AppTextStyles.body.copyWith(
                                      color: Colors.white, fontSize: 13),
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios, color: Colors.white60, size: 12),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── Stat chips ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 0, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(right: 16),
                      child: AppText(context.s.cityWideOverview, style: AppTextStyles.heading3),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 112,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(right: 16),
                        children: [
                          _statChip('Total', total, Icons.description_rounded, AppColors.primary),
                          _statChip('Pending', pending, Icons.schedule_rounded, AppColors.statusPending),
                          _statChip('Active', inProgress, Icons.autorenew_rounded, AppColors.statusInProgress),
                          _statChip('Resolved', resolved, Icons.check_circle_rounded, AppColors.statusResolved),
                          _statChip('Flagged', flagged, Icons.flag_rounded, AppColors.error),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Resolution rate ───────────────────────────────────────────
            if (total > 0)
              SliverToBoxAdapter(child: _buildResolutionCard(context.s, resolutionRate, resolved, total)),

            // ── Severity chart ────────────────────────────────────────────
            if (maxCount > 0)
              SliverToBoxAdapter(child: _buildSeverityChart(context.s, counts, maxCount)),

            // ── Urgent attention ──────────────────────────────────────────
            if (urgentIncidents.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Icon(Icons.priority_high_rounded,
                            color: AppColors.error, size: 15),
                      ),
                      const SizedBox(width: 8),
                      AppText(context.s.needsAttention, style: AppTextStyles.heading3),
                    ],
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => IncidentCard(
                    incident: urgentIncidents[index],
                    showReporter: true,
                    onTap: () => Navigator.pushNamed(
                      context,
                      '/incident-manage',
                      arguments: urgentIncidents[index].id,
                    ).then((_) => onRefresh()),
                  ),
                  childCount: urgentIncidents.length,
                ),
              ),
            ],

            // ── Non-resident emergency reports (city-wide) ────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () =>
                        Navigator.pushNamed(context, '/non-resident-queue'),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.error.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.emergency_share_rounded,
                                color: AppColors.error, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AppText(context.s.nonResidentReports,
                                    style: AppTextStyles.body.copyWith(
                                        fontWeight: FontWeight.w700)),
                                Text(context.s.allBarangaysView,
                                    style: AppTextStyles.caption),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              color: AppColors.textTertiary),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Critical & high priority ──────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(child: AppText(context.s.criticalHighPriority, style: AppTextStyles.heading3)),
                    if (provider.incidents.isNotEmpty)
                      Text(
                        '${provider.incidents.where((i) => Severity.isUrgent(i.severityLevel) && !i.isResolved).length} active',
                        style: AppTextStyles.caption.copyWith(color: AppColors.error),
                      ),
                  ],
                ),
              ),
            ),

            if (provider.isLoading)
              const SliverToBoxAdapter(child: IncidentListShimmer(count: 3))
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final critical = provider.incidents
                        .where((i) =>
                            Severity.isUrgent(i.severityLevel) &&
                            !i.isResolved)
                        .toList();
                    if (index >= critical.length) return null;
                    return IncidentCard(
                      incident: critical[index],
                      showReporter: true,
                      onTap: () => Navigator.pushNamed(
                        context,
                        '/incident-manage',
                        arguments: critical[index].id,
                      ).then((_) => onRefresh()),
                    );
                  },
                  childCount: provider.incidents
                      .where((i) =>
                          Severity.isUrgent(i.severityLevel) && !i.isResolved)
                      .length,
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String label, int value, IconData icon, Color color) {
    return Container(
      width: 108,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 20),
          AppText(
            '$value',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: color, height: 1.0),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color.withValues(alpha: 0.75)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildResolutionCard(AppStrings t, int rate, int resolved, int total) {
    final Color rateColor = rate >= 70 ? AppColors.statusResolved : rate >= 40 ? AppColors.warning : AppColors.error;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up_rounded, color: AppColors.statusResolved, size: 18),
              const SizedBox(width: 6),
              Expanded(child: AppText(t.cityResolutionRate, style: AppTextStyles.heading3)),
              AppText('$rate%', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: rateColor)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: rate / 100,
              backgroundColor: AppColors.divider,
              valueColor: AlwaysStoppedAnimation(rateColor),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 7),
          AppText('$resolved of $total reports resolved city-wide', style: AppTextStyles.caption),
        ],
      ),
    );
  }

  Widget _buildSeverityChart(AppStrings t, List<int> counts, int maxCount) {
    final labels = ['Critical', 'High', 'Medium', 'Low'];
    final colors = [AppColors.severityCritical, AppColors.severityHigh, AppColors.severityMedium, AppColors.severityLow];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded, color: AppColors.primary, size: 18),
              const SizedBox(width: 6),
              AppText(t.activeBySeverity, style: AppTextStyles.heading3),
              const Spacer(),
              Flexible(child: AppText(t.unresolvedOnly, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary))),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 130,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (maxCount + 1).toDouble(),
                barGroups: List.generate(4, (i) => BarChartGroupData(
                  x: i,
                  barRods: [BarChartRodData(
                    toY: counts[i].toDouble(),
                    color: colors[i],
                    width: 34,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  )],
                )),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (value, _) => Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(labels[value.toInt()], style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: colors[value.toInt()])),
                    ),
                  )),
                  topTitles: AxisTitles(sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (value, _) => AppText('${counts[value.toInt()]}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  )),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// City Map (with MapController + fit button)
// ═══════════════════════════════════════════════════════════════════════════
class _SuperAdminMapView extends StatefulWidget {
  @override
  State<_SuperAdminMapView> createState() => _SuperAdminMapViewState();
}

class _SuperAdminMapViewState extends State<_SuperAdminMapView> {
  final MapController _mapController = MapController();
  String? _selectedStatus;

  List<IncidentModel> _filter(List<IncidentModel> all) {
    return all.where((i) {
      if (_selectedStatus == null) return i.status != 'resolved';
      return i.status == _selectedStatus;
    }).toList();
  }

  void _fitAllMarkers(List<IncidentModel> incidents) {
    if (incidents.isEmpty) return;
    final points = incidents.map((i) => LatLng(i.latitude, i.longitude)).toList();
    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(72)));
  }

  @override
  Widget build(BuildContext context) {
    // Scoped to just the incidents list — avoids rebuilding the whole map
    // (and re-running clustering) on unrelated provider notifies.
    final incidents = context.select<IncidentProvider, List<IncidentModel>>((p) => p.incidents);
    final filtered = _filter(incidents);

    return SafeArea(
      child: Column(
        children: [
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
                    AppText(context.s.cityWideIncidentMap, style: AppTextStyles.heading3),
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
                      _chip('Active', null),
                      _chip('Pending', 'pending'),
                      _chip('In Progress', 'in_progress'),
                      _chip('Resolved', 'resolved'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                IncidentMapWidget(
                  incidents: filtered,
                  centerLat: AppConfig.defaultLatitude,
                  centerLng: AppConfig.defaultLongitude,
                  zoom: 13.0,
                  mapController: _mapController,
                  onMarkerTap: (incident) {
                    _mapController.move(LatLng(incident.latitude, incident.longitude), 17.0);
                    _showQuickView(context, incident);
                  },
                ),
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: FloatingActionButton.small(
                    heroTag: 'fit_map_superadmin',
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    tooltip: context.s.fitAllIncidents,
                    onPressed: () => _fitAllMarkers(filtered),
                    child: const Icon(Icons.fit_screen_rounded),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String? status) {
    final selected = _selectedStatus == status;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => setState(() => _selectedStatus = status),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withValues(alpha: 0.12) : AppColors.background,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? AppColors.primary : AppColors.divider),
          ),
          child: AppText(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  void _showQuickView(BuildContext context, IncidentModel incident) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                SeverityBadge(level: incident.severityLevel),
                const SizedBox(width: 8),
                StatusChip(status: incident.status),
              ]),
              const SizedBox(height: 10),
              AppText(categoryLabel(context.s, incident.category), style: AppTextStyles.heading3),
              const SizedBox(height: 4),
              Text(incident.description, style: AppTextStyles.body.copyWith(color: AppColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              AppText(
                'Reported ${timeAgo(incident.createdAt)}${incident.reporterName != null ? ' by ${incident.reporterName}' : ''}${incident.barangayName != null ? ' · ${incident.barangayName}' : ''}',
                style: AppTextStyles.caption,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pushNamed(context, '/incident-manage', arguments: incident.id);
                  },
                  child: Text(context.s.manageIncident),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// All Incidents
// ═══════════════════════════════════════════════════════════════════════════
class _SuperAdminAllIncidents extends StatefulWidget {
  final VoidCallback onRefresh;
  const _SuperAdminAllIncidents({required this.onRefresh});

  @override
  State<_SuperAdminAllIncidents> createState() => _SuperAdminAllIncidentsState();
}

class _SuperAdminAllIncidentsState extends State<_SuperAdminAllIncidents> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedCategory;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List _applyFilters(List<IncidentModel> incidents) {
    return incidents.where((i) {
      if (_selectedCategory != null && i.category != _selectedCategory) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!i.description.toLowerCase().contains(q) &&
            !i.category.toLowerCase().contains(q) &&
            !(i.reporterName ?? '').toLowerCase().contains(q) &&
            !(i.barangayName ?? '').toLowerCase().contains(q) &&
            !(i.address ?? '').toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IncidentProvider>();
    final all = _applyFilters(provider.incidents);
    final pending = _applyFilters(provider.incidents.where((i) => i.isPending).toList());
    final active = _applyFilters(provider.incidents.where((i) => i.isInProgress).toList());
    final resolved = _applyFilters(provider.incidents.where((i) => i.isResolved).toList());

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(context.s.allIncidentReports, style: AppTextStyles.heading2),
                Text(context.s.acrossAllBarangays(provider.incidents.length), style: AppTextStyles.bodySmall),
                const SizedBox(height: 10),
                // Search bar
                TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: context.s.searchAllHint,
                    hintStyle: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.textSecondary),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.background,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.divider)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.divider)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
                  ),
                ),
                const SizedBox(height: 8),
                // Category chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _chip(context.s.all, _selectedCategory == null, () => setState(() => _selectedCategory = null)),
                      // Label translated; `cat` stays the canonical filter value.
                      ...AppConfig.incidentCategories.map((cat) => _chip(
                        categoryLabel(context.s, cat),
                        _selectedCategory == cat,
                        () => setState(() => _selectedCategory = _selectedCategory == cat ? null : cat),
                      )),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TabBar(
                  controller: _tabController,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primary,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  unselectedLabelStyle: const TextStyle(fontSize: 13),
                  tabs: [
                    Tab(text: 'All (${all.length})'),
                    Tab(text: 'Pending (${pending.length})'),
                    Tab(text: 'Active (${active.length})'),
                    Tab(text: 'Resolved (${resolved.length})'),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: provider.isLoading
                ? const IncidentListShimmer(count: 6)
                : TabBarView(
                    controller: _tabController,
                    children: [all, pending, active, resolved].map((list) {
                      if (list.isEmpty) {
                        return EmptyState(icon: Icons.inbox_rounded, title: context.s.noReportsTitle, subtitle: context.s.noReportsMatchFilters);
                      }
                      return RefreshIndicator(
                        onRefresh: () async => widget.onRefresh(),
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 20),
                          itemCount: list.length,
                          itemBuilder: (context, index) => IncidentCard(
                            incident: list[index],
                            showReporter: true,
                            onTap: () => Navigator.pushNamed(
                              context,
                              '/incident-manage',
                              arguments: list[index].id,
                            ).then((_) => widget.onRefresh()),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withValues(alpha: 0.12) : AppColors.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? AppColors.primary : AppColors.divider),
          ),
          child: AppText(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// User & Admin Management (enhanced)
// ═══════════════════════════════════════════════════════════════════════════
class _SuperAdminUserManagement extends StatefulWidget {
  const _SuperAdminUserManagement();

  @override
  State<_SuperAdminUserManagement> createState() => _SuperAdminUserManagementState();
}

class _SuperAdminUserManagementState extends State<_SuperAdminUserManagement>
    with SingleTickerProviderStateMixin, LiveRefreshMixin{
  final _userService = UserManagementService();
  late TabController _tabController;

  List<UserModel> _admins = [];
  List<UserModel> _residents = [];
  List<UserModel> _pendingVerifications = [];

  /// Set when the fetch failed, so the tabs can say so instead of showing
  /// zeroes that look like real data.
  String? _loadError;

  StreamSubscription? _profileSub;
  Timer? _profileDebounce;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUsers();
    _watchProfiles();
    // City-wide accounts were loaded once and never again, so a superadmin had
    // to sign out and back in to see a new registration or a verification
    // someone else had just done.
    startLiveRefresh();
  }

  /// Realtime across every barangay, debounced so a burst of changes is one
  /// refetch rather than one per row.
  void _watchProfiles() {
    _profileSub?.cancel();
    _profileSub = _userService.subscribeToProfiles(null).listen((_) {
      _profileDebounce?.cancel();
      _profileDebounce = Timer(const Duration(milliseconds: 400), () {
        if (mounted) _loadUsers(silent: true);
      });
    }, onError: (e) {
      debugPrint('SuperadminUsers: profile stream error: $e');
    });
  }

  @override
  Future<void> onLiveRefresh() => _loadUsers(silent: true);

  @override
  void dispose() {
    _profileSub?.cancel();
    _profileDebounce?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  /// [silent] skips the spinner so a background refresh does not blank tabs
  /// the superadmin is reading.
  Future<void> _loadUsers({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      // Three targeted queries instead of one download-everything-and-filter.
      //
      // The old version fetched every profile in the city and sorted them into
      // buckets in Dart. That is the whole `profiles` table over mobile data to
      // render three tab counts — and it silently depended on the fetch being
      // unbounded, so any row limit would have started dropping people out of
      // the pending queue without any sign that it had.
      //
      // Residents only in the pending bucket: non-resident signup was retired
      // 2026-08-08, so no official should be asked to approve an account from a
      // dead path.
      final results = await Future.wait([
        _userService.getStaffAccounts(),
        _userService.getResidentAccounts(),
        _userService.getPendingVerifications(),
      ]);
      if (!mounted) return;
      _admins = results[0];
      _residents = results[1];
      _pendingVerifications = results[2];
    } catch (e) {
      // Previously swallowed. A failed query then rendered as three empty tabs
      // reading "0 users" — indistinguishable from a city with no accounts, and
      // the superadmin had no way to tell that anything had gone wrong.
      _loadError = 'Could not load accounts. Check your connection and retry.';
      debugPrint('SuperadminHome: _loadUsers failed — $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(context.s.userManagement, style: AppTextStyles.heading2),
                AppText(
                  '${_admins.length + _residents.length + _pendingVerifications.length} total · ${_pendingVerifications.length} pending verification',
                  style: AppTextStyles.bodySmall,
                ),
                const SizedBox(height: 12),
                TabBar(
                  controller: _tabController,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primary,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  tabs: [
                    Tab(text: 'Officials (${_admins.length})'),
                    Tab(text: 'Residents (${_residents.length})'),
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(child: AppText('${context.s.statusPending} (${_pendingVerifications.length})')),
                          if (_pendingVerifications.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Container(
                              width: 8, height: 8,
                              decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildAdminList(),
                      _buildResidentList(),
                      _buildPendingList(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Shown instead of an empty state when the fetch itself failed.
  ///
  /// The distinction matters here more than almost anywhere else in the app:
  /// "there are no officials in Lipa City" and "we could not reach the server"
  /// look identical as an empty list, and only one of them is worth acting on.
  Widget _errorState() => EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load accounts',
        subtitle: _loadError,
        action: OutlinedButton.icon(
          onPressed: _loadUsers,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(context.s.retry),
        ),
      );

  Widget _buildAdminList() {
    if (_loadError != null) return _errorState();
    if (_admins.isEmpty) {
      return EmptyState(icon: Icons.admin_panel_settings_outlined, title: context.s.noOfficials);
    }
    return RefreshIndicator(
      onRefresh: _loadUsers,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 20),
        itemCount: _admins.length,
        itemBuilder: (_, i) => _adminCard(_admins[i]),
      ),
    );
  }

  Widget _buildResidentList() {
    if (_loadError != null) return _errorState();
    if (_residents.isEmpty) {
      return EmptyState(icon: Icons.people_outline, title: context.s.noResidents);
    }
    return RefreshIndicator(
      onRefresh: _loadUsers,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 20),
        itemCount: _residents.length,
        itemBuilder: (_, i) => _userCard(_residents[i]),
      ),
    );
  }

  Widget _buildPendingList() {
    if (_loadError != null) return _errorState();
    if (_pendingVerifications.isEmpty) {
      return EmptyState(
        icon: Icons.how_to_reg_outlined,
        title: context.s.noPendingVerifications,
        subtitle: context.s.allPendingReviewed,
      );
    }
    return RefreshIndicator(
      onRefresh: _loadUsers,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 20),
        itemCount: _pendingVerifications.length,
        itemBuilder: (_, i) => _pendingCard(_pendingVerifications[i]),
      ),
    );
  }

  Widget _adminCard(UserModel user) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: user.isSuperAdmin
              ? Colors.purple.withValues(alpha: 0.1)
              : AppColors.primary.withValues(alpha: 0.1),
          child: Icon(
            Icons.admin_panel_settings,
            color: user.isSuperAdmin ? Colors.purple : AppColors.primary,
          ),
        ),
        title: Row(
          children: [
            Expanded(child: AppText(user.fullName, style: const TextStyle(fontWeight: FontWeight.w600))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: (user.isSuperAdmin ? Colors.purple : AppColors.primary).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                user.isSuperAdmin ? 'Super Admin' : 'Official',
                style: TextStyle(
                  fontSize: 10,
                  color: user.isSuperAdmin ? Colors.purple : AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(user.email, style: AppTextStyles.caption),
            AppText(user.barangayName ?? 'No barangay assigned', style: AppTextStyles.caption),
            if (user.isLocked)
              Text(context.s.locked, style: AppTextStyles.caption.copyWith(color: AppColors.error, fontWeight: FontWeight.w700)),
          ],
        ),
        trailing: user.isSuperAdmin
            ? null
            : PopupMenuButton<String>(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                onSelected: (action) => _handleAction(action, user),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(context.s.editDetails)),
                  PopupMenuItem(value: 'position', child: Text(context.s.assignPosition)),
                  PopupMenuItem(value: 'demote', child: Text(context.s.removeAdminRole)),
                  PopupMenuItem(
                    value: user.isLocked ? 'unlock' : 'lock',
                    child: Text(user.isLocked ? 'Unlock Account' : 'Lock Account'),
                  ),
                ],
              ),
        isThreeLine: true,
      ),
    );
  }

  Widget _userCard(UserModel user) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: user.isLocked
              ? AppColors.error.withValues(alpha: 0.1)
              : AppColors.accent.withValues(alpha: 0.1),
          child: AppText(
            user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?',
            style: TextStyle(color: user.isLocked ? AppColors.error : AppColors.accent, fontWeight: FontWeight.w600),
          ),
        ),
        title: AppText(user.fullName, style: const TextStyle(fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(user.barangayName ?? '', style: AppTextStyles.caption),
            if (user.isLocked)
              Text(context.s.locked, style: AppTextStyles.caption.copyWith(color: AppColors.error, fontWeight: FontWeight.w700)),
          ],
        ),
        trailing: PopupMenuButton<String>(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          onSelected: (action) => _handleAction(action, user),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'edit', child: Text(context.s.editDetails)),
            PopupMenuItem(value: 'promote', child: Text(context.s.makeOfficial)),
            PopupMenuItem(
              value: user.isLocked ? 'unlock' : 'lock',
              child: Text(user.isLocked ? 'Unlock Account' : 'Lock Account'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pendingCard(UserModel user) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.warning.withValues(alpha: 0.1),
                  child: AppText(
                    user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?',
                    style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(user.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      AppText(user.email, style: AppTextStyles.caption),
                      AppText(user.barangayName ?? 'No barangay', style: AppTextStyles.caption),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(context.s.statusPending, style: TextStyle(fontSize: 10, color: AppColors.warning, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (user.isNonResident ? AppColors.error : AppColors.success).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        user.isNonResident ? 'Non-Resident' : 'Resident',
                        style: TextStyle(
                          fontSize: 10,
                          color: user.isNonResident ? AppColors.error : AppColors.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // §8 — all three photos, signed on demand.
            //
            // Was `Image.network(user.idPhotoUrl!)`, which could never have
            // worked: that column holds a storage *path*, and the
            // `id-verification` bucket is private. The superadmin has been
            // looking at a broken frame while the officials' screen — which
            // signs the path first — worked. It also only showed the front,
            // when the three photos only mean anything together.
            if (user.hasSubmittedId) ...[
              const SizedBox(height: 10),
              Text(context.s.submittedId, style: AppTextStyles.caption),
              const SizedBox(height: 6),
              IdPhotoStrip(user: user),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: Text(context.s.reject),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                    ),
                    onPressed: () => _rejectId(user),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: Text(context.s.approve),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                    onPressed: () => _verifyUser(user),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// §8 — sends an ID submission back for another attempt.
  ///
  /// This button used to call `_handleAction('lock', user)`, which **locked
  /// the applicant's account**. The same fault was reported on the officials'
  /// screen and fixed there on 2026-08-18; the superadmin copy was missed.
  ///
  /// The distinction matters: an unreadable photo is a mistake, not
  /// misconduct. Locking someone for a blurry ID leaves them stuck with no
  /// route to verification and no idea why. Clearing the submission returns
  /// them to the upload screen so they can simply retake it. Verification
  /// status is untouched — they were never verified and still are not.
  Future<void> _rejectId(UserModel user) async {
    final ok = await showFrostedConfirm(
      context,
      title: context.s.reject,
      message: "Clear ${user.fullName}'s ID photos so they can submit again? "
          'This does not lock their account.',
      confirmLabel: context.s.reject,
      destructive: true,
      icon: Icons.close_rounded,
    );
    if (ok != true || !mounted) return;

    try {
      await _userService.rejectIdSubmission(user.id);
      if (!mounted) return;
      showSuccessSnackbar(context, context.s.idRejected);
      _loadUsers(silent: true);
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not reject: $e');
    }
  }

  Future<void> _verifyUser(UserModel user) async {
    try {
      await _userService.verifyUser(user.id);
      if (mounted) {
        showSuccessSnackbar(context, '${user.fullName} approved and verified');
        _loadUsers(silent: true);
      }
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Failed to verify user');
    }
  }

  /// Assign or clear a hall position. The official-side roster has had this
  /// since positions shipped; the city-wide roster had no way to set one,
  /// which meant a superadmin could create officials they could not then give
  /// a job title to.
  Future<void> _pickPosition(UserModel user) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
            20, 18, 20, MediaQuery.of(ctx).padding.bottom + 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(ctx.s.assignPosition, style: AppTextStyles.heading3),
            const SizedBox(height: 4),
            AppText(user.fullName, style: AppTextStyles.bodySmall),
            const SizedBox(height: 10),
            ...UserPosition.all.map(
              (pos) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.badge_outlined,
                  color: user.position == pos
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                title: AppText(UserPosition.label(pos)),
                trailing: user.position == pos
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, pos),
              ),
            ),
            if (user.position != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.remove_circle_outline,
                    color: AppColors.error),
                title: AppText(ctx.s.removePosition),
                onTap: () => Navigator.pop(ctx, '__clear__'),
              ),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return;
    final position = choice == '__clear__' ? null : choice;

    try {
      await _userService.setUserPosition(user.id, position);
      if (!mounted) return;
      showSuccessSnackbar(
        context,
        position == null
            ? 'Removed ${user.fullName}\'s position'
            : '${user.fullName} is now ${UserPosition.label(position)}',
      );
      _loadUsers();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not set position: $e');
    }
  }

  Future<void> _handleAction(String action, UserModel user) async {
    try {
      switch (action) {
        case 'promote':
          await _userService.changeUserRole(user.id, 'admin');
          if (mounted) showSuccessSnackbar(context, '${user.fullName} promoted to Official');
          break;
        case 'edit':
          await showEditUserDetailsSheet(context, user);
          break;
        case 'position':
          await _pickPosition(user);
          break;
        case 'demote':
          // Clears the job title in the same statement. Dropping the role
          // alone leaves an ex-official holding e.g. `position = 'captain'`,
          // which the `profiles_position_requires_staff_role` constraint
          // rejects - the demotion failed outright and the screen said it
          // worked.
          await _userService.demoteToResident(user.id);
          if (mounted) showSuccessSnackbar(context, '${user.fullName} role changed to Resident');
          break;
        case 'lock':
          await _userService.toggleLockUser(user.id, true);
          if (mounted) showSuccessSnackbar(context, '${user.fullName} locked');
          break;
        case 'unlock':
          await _userService.toggleLockUser(user.id, false);
          if (mounted) showSuccessSnackbar(context, '${user.fullName} unlocked');
          break;
      }
      _loadUsers();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Action failed');
    }
  }
}
