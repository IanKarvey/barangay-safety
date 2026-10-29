import '../../utils/live_refresh.dart';
import '../../utils/analytics_report.dart';
import '../../utils/incident_route.dart';
import '../../utils/report_log.dart';
import '../../widgets/report_log_section.dart';
import '../../utils/file_download.dart';
import '../../utils/manila_time.dart';
import '../../widgets/export_format_sheet.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../../models/incident_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/incident_service.dart';
import '../../services/user_management_service.dart';
import '../../utils/constants.dart';
import '../../utils/date_range.dart';
import '../../config/app_config.dart';
import '../../l10n/app_strings.dart';
import '../../utils/helpers.dart';
import '../../widgets/widgets.dart';
import '../../widgets/app_text.dart';
import '../../widgets/responsive_layout.dart';

class AnalyticsScreen extends StatefulWidget {
  final bool isSuperAdmin;
  const AnalyticsScreen({super.key, this.isSuperAdmin = false});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with LiveRefreshMixin {
  final _incidentService = IncidentService();
  final _userService = UserManagementService();
  List<IncidentModel> _incidents = [];
  UserStats? _userStats;
  Map<String, int> _ageBrackets = const {};

  // Applied to the charts AND the PDF, so the exported document always matches
  // what the official was looking at when they pressed Export.
  ReportRange _range = ReportRange.allTime;
  List<IncidentModel> _allIncidents = [];
  bool _isLoading = true;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    // Charts were computed once on open. A report filed while the screen was
    // up never appeared, and the counts silently drifted from the queue.
    startLiveRefresh();
    _loadData();
  }

  /// Charts are read-heavy; a slower tick than the default is plenty.
  @override
  Duration get livePollInterval => const Duration(seconds: 45);

  @override
  Future<void> onLiveRefresh() => _loadData(silent: true);

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);

    // Read from context once, before any await — afterwards this State may be
    // gone and `context.read` is no longer safe.
    final barangayId =
        widget.isSuperAdmin ? null : context.read<AuthProvider>().user?.barangayId;

    try {
      // All three run together. They are independent queries and used to be
      // awaited one after another, so opening analytics cost the sum of three
      // round trips — and the first of them fetches up to 500 incidents with
      // their joins, which is the slowest request in the app.
      //
      // §10 user statistics are fetched here rather than lazily because the
      // PDF export needs them too.
      final incidentsFuture = widget.isSuperAdmin
          ? _incidentService.getAllIncidents(limit: 500)
          : barangayId != null
              ? _incidentService.getIncidentsByBarangay(barangayId, limit: 500)
              : Future.value(<IncidentModel>[]);

      // Demographics degrade rather than blanking the screen: incident
      // analytics are still worth showing without them. Caught per-future so a
      // failing demographics RPC cannot take the incident charts down with it,
      // and so the two no longer share a failure — previously a throw from
      // getUserStats meant getAgeDemographics was never even attempted.
      final statsFuture = _userService
          .getUserStats(barangayId: barangayId)
          .then<UserStats?>((v) => v)
          .catchError((Object e) {
        debugPrint('AnalyticsScreen: user stats unavailable: $e');
        return null;
      });

      final bracketsFuture = _userService
          .getAgeDemographics(barangayId: barangayId)
          .catchError((Object e) {
        debugPrint('AnalyticsScreen: age demographics unavailable: $e');
        return <String, int>{};
      });

      final data = await incidentsFuture;
      final stats = await statsFuture;
      final brackets = await bracketsFuture;

      if (mounted) {
        setState(() {
          _allIncidents = data;
          _incidents = _inRange(data);
          _userStats = stats;
          _ageBrackets = brackets;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('AnalyticsScreen: load failed: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<IncidentModel> _inRange(List<IncidentModel> source) =>
      source.where((i) => _range.includes(i.createdAt)).toList();

  void _setRange(ReportRange range) {
    setState(() {
      _range = range;
      _incidents = _inRange(_allIncidents);
    });
  }

  /// The window selector. Sits above the charts because it governs every
  /// number below it.
  Widget _rangeSelector() {
    final t = context.s;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final r in ReportRange.values) ...[
            _rangeChip(r.labelFor(t), _range == r, () => _setRange(r)),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _rangeChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
          ),
        ),
        child: AppText(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  // ── Computed Stats ──────────────────────────────────────────────────────────
  int get _total => _incidents.length;
  int get _resolved => _incidents.where((i) => i.isResolved).length;
  int get _pending => _incidents.where((i) => i.isPending).length;
  int get _inProgress => _incidents.where((i) => i.isInProgress).length;
  int get _flagged => _incidents.where((i) => i.isFlagged).length;
  int get _nonResidentCount =>
      _incidents.where((i) => i.isNonResidentReport).length;
  int get _overdue => _incidents.where((i) => slaStatus(i) == 'overdue').length;

  double get _resolutionRate =>
      _total > 0 ? (_resolved / _total * 100) : 0;

  double get _avgResolutionHours {
    final resolved = _incidents.where((i) => i.isResolved && i.resolvedAt != null);
    if (resolved.isEmpty) return 0;
    final totalHours = resolved.fold<double>(
      0,
      (sum, i) => sum + i.resolvedAt!.difference(i.createdAt).inMinutes / 60,
    );
    return totalHours / resolved.length;
  }

  double get _slaCompliance {
    if (_resolved == 0) return 0;
    final onTime = _incidents.where((i) {
      if (!i.isResolved || i.resolvedAt == null) return false;
      final h = i.resolvedAt!.difference(i.createdAt).inHours;
      return h <= 48;
    }).length;
    return onTime / _resolved * 100;
  }

  // 7-day buckets: [6 days ago … today]
  List<int> get _last7Days {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final day = now.subtract(Duration(days: 6 - i));
      return _incidents.where((inc) {
        final d = inc.createdAt;
        return d.year == day.year &&
            d.month == day.month &&
            d.day == day.day;
      }).length;
    });
  }

  // Top categories sorted by count
  List<MapEntry<String, int>> get _categoryBreakdown {
    final map = <String, int>{};
    for (final i in _incidents) {
      map[i.category] = (map[i.category] ?? 0) + 1;
    }
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(8).toList();
  }

  List<ReportLogEntry> _reportLog(List<IncidentModel> source) => buildReportLog(
        source,
        isOverdue: (i) => slaStatus(i) == 'overdue',
      );

  /// Every report in the chosen period, for the export.
  ///
  /// The screen holds the newest 500 (enough to read, cheap to load). An export is
  /// meant to contain EVERY report, so when the screen's copy hit that cap this
  /// pages through the rest rather than quietly leaving the older ones out.
  Future<List<IncidentModel>> _everyReportInRange() async {
    if (_allIncidents.length < 500) return _incidents;

    final barangayId =
        widget.isSuperAdmin ? null : context.read<AuthProvider>().user?.barangayId;
    const page = 500;
    const hardCap = 10000; // a browser tab or a phone should not be asked for more
    final all = <IncidentModel>[];
    var offset = 0;
    while (all.length < hardCap) {
      final chunk = widget.isSuperAdmin
          ? await _incidentService.getAllIncidents(limit: page, offset: offset)
          : barangayId != null
              ? await _incidentService.getIncidentsByBarangay(barangayId,
                  limit: page, offset: offset)
              : <IncidentModel>[];
      all.addAll(chunk);
      if (chunk.length < page) break;
      offset += page;
    }
    return _inRange(all);
  }

  /// Exports the report the official is looking at, as Excel or Word.
  ///
  /// Every figure comes from the same getters the charts use, filtered to the same
  /// period, so the file always matches the screen. PDF is not offered: officials
  /// asked for files they can open and edit.
  Future<void> _exportReport() async {
    final format = await showExportFormatSheet(context);
    if (format == null || !mounted) return;

    setState(() => _isExporting = true);
    try {
      final user = context.read<AuthProvider>().user;
      final barangayName = widget.isSuperAdmin
          ? 'All Barangays'
          : (user?.barangayName ?? 'Barangay');
      final now = DateTime.now();

      final report = buildAnalyticsReport(
        appName: AppConfig.appName,
        barangayName: barangayName,
        periodLabel: _range.label,
        generatedAt: now,
        today: now,
        total: _total,
        nonResident: _nonResidentCount,
        pending: _pending,
        inProgress: _inProgress,
        resolved: _resolved,
        flagged: _flagged,
        overdue: _overdue,
        resolutionRate: _resolutionRate,
        avgResolutionHours: _avgResolutionHours,
        slaCompliance: _slaCompliance,
        categories: _categoryBreakdown,
        last7Days: _last7Days,
        log: _reportLog(await _everyReportInRange()),
        overviewHeading: context.s.overview,
        performanceHeading: context.s.responsePerformance,
        categoriesHeading: context.s.topCategories,
        last7Heading: context.s.incidentsLast7Days,
      );

      final scope = barangayName
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      final fileName = 'analytics_report_${scope}_${manilaDate(now)}.${format.extension}';

      await downloadFile(
        fileName,
        format == ExportFormat.excel ? report.toXlsx() : report.toDocx(),
        mimeType: format.mimeType,
      );
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(context.s.analyticsReports),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const AnalyticsShimmer()
          : _total == 0
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bar_chart_rounded,
                          size: 56, color: AppColors.textTertiary),
                      const SizedBox(height: 12),
                      AppText(context.s.noDataYet,
                          style: AppTextStyles.body
                              .copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle('Overview'),
                        const SizedBox(height: 10),
                        _rangeSelector(),
                        const SizedBox(height: 14),
                        _summaryGrid(),
                        const SizedBox(height: 24),

                        // Charts pair up on a desktop (trend beside status,
                        // categories beside performance) and stack on a phone.
                        // Alone, each was a 1300px-wide strip with a few bars
                        // in the left corner and nothing to the right.
                        SideBySide(
                          first: _titled('Incidents — Last 7 Days', _trendChart()),
                          second: _titled('Status Distribution', _statusBars()),
                          gap: 24,
                        ),

                        SideBySide(
                          first: _titled('Top Categories', _categoryBars()),
                          second: _titled('Response Performance', _performanceCard()),
                          gap: 24,
                        ),

                        // Every report in the period: who reported it, when, who
                        // responded and how long it took. The same list the Excel
                        // and Word exports are built from.
                        _titled(
                          'Report log - every report, who reported it and how long it took',
                          ReportLogSection(
                            entries: _reportLog(_incidents),
                            onOpen: (e) => Navigator.pushNamed(
                              context,
                              incidentRouteForCurrentUser(context),
                              arguments: e.id,
                            ),
                          ),
                        ),

                        if (_userStats != null)
                          _titled(context.s.userStatistics, _userStatsCard(_userStats!)),
                        const SizedBox(height: 8),

                        // ── Export Button ─────────────────────────────
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: _isExporting ? null : _exportReport,
                            icon: _isExporting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.file_download_rounded),
                            label: Text(
                              _isExporting ? 'Preparing file...' : 'Export report (Excel / Word)',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppRadius.xl),
                              ),
                            ),
                          ),
                        ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  // ── Section title ───────────────────────────────────────────────────────────
  Widget _sectionTitle(String title) => AppText(title, style: AppTextStyles.heading3);

  /// A section: its title, a gap, the content, and the space below it.
  Widget _titled(String title, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(title),
          const SizedBox(height: 10),
          child,
          const SizedBox(height: 24),
        ],
      );

  // ── Summary grid — 2×2 on a phone, one row on a desktop ─────────────────────
  //
  // `childAspectRatio` is width ÷ height, so a fixed ratio makes card HEIGHT a
  // function of the width it is given. At a phone's ~175px per cell, 1.7 gives
  // a ~103px card. The same 1.7 inside the web dashboard's content column gives
  // each cell ~530px of width and therefore a ~310px card — four tiny numbers
  // floating in a screen of whitespace, which is what this looked like when the
  // web shell first rendered it.
  //
  // The breakpoint is on the constraints this grid is actually handed, not on
  // the window: a phone can never reach 640px here, so the mobile layout takes
  // the same branch and the same numbers it always has.
  Widget _summaryGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 640;
        return GridView.count(
          crossAxisCount: wide ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: wide ? 1.9 : 1.7,
          children: _summaryCards(),
        );
      },
    );
  }

  List<Widget> _summaryCards() {
    return [
        _summaryCard('Total Reports', _total, Icons.description_rounded,
            AppColors.primary),
        _summaryCard('Resolved', _resolved, Icons.check_circle_rounded,
            AppColors.statusResolved),
        _summaryCard('Overdue', _overdue, Icons.timer_off_rounded,
            AppColors.error),
        _summaryCard('Flagged', _flagged, Icons.flag_rounded,
            const Color(0xFFFF9500)),
    ];
  }

  Widget _summaryCard(String label, int value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppText(
                  '$value',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: color,
                    height: 1,
                  ),
                ),
                AppText(label, style: AppTextStyles.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 7-day bar chart ─────────────────────────────────────────────────────────
  Widget _trendChart() {
    final days = _last7Days;
    final maxY = (days.reduce((a, b) => a > b ? a : b) + 2).toDouble();
    final dayLabels = List.generate(7, (i) {
      final d = DateTime.now().subtract(Duration(days: 6 - i));
      const abbr = ['Mo','Tu','We','Th','Fr','Sa','Su'];
      return abbr[d.weekday - 1];
    });

    return Container(
      height: 200,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: BarChart(
        BarChartData(
          maxY: maxY == 2 ? 5 : maxY,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              tooltipBgColor: AppColors.primary,
              getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                '${rod.toY.toInt()} reports',
                const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, _) => Text(
                  dayLabels[v.toInt()],
                  style: AppTextStyles.caption,
                ),
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: maxY > 10 ? (maxY / 5).ceilToDouble() : 2,
                getTitlesWidget: (v, _) => AppText(
                  '${v.toInt()}',
                  style: AppTextStyles.caption,
                ),
              ),
            ),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppColors.divider,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(7, (i) {
            final val = days[i].toDouble();
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: val,
                  width: 18,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6)),
                  color: val == 0
                      ? AppColors.divider
                      : AppColors.primary,
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  // ── Status distribution bars ────────────────────────────────────────────────
  Widget _statusBars() {
    final items = [
      ('Pending', _pending, AppColors.statusPending),
      ('In Progress', _inProgress, AppColors.statusInProgress),
      ('Resolved', _resolved, AppColors.statusResolved),
      ('Flagged', _flagged, AppColors.statusFlagged),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: items.map((item) {
          final pct = _total > 0 ? item.$2 / _total : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: AppText(item.$1,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ))),
                    const Spacer(),
                    Text(
                      '${item.$2}  (${(pct * 100).toStringAsFixed(0)}%)',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 8,
                    backgroundColor: AppColors.background,
                    valueColor: AlwaysStoppedAnimation(item.$3),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Category breakdown ──────────────────────────────────────────────────────
  Widget _categoryBars() {
    final cats = _categoryBreakdown;
    if (cats.isEmpty) {
      return Text(context.s.noData, style: AppTextStyles.bodySmall);
    }
    final maxVal = cats.first.value;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: cats.asMap().entries.map((e) {
          final pct = maxVal > 0 ? e.value.value / maxVal : 0.0;
          final colors = [
            AppColors.primary,
            const Color(0xFF5856D6),
            const Color(0xFFFF9500),
            AppColors.error,
            AppColors.success,
            const Color(0xFFAF52DE),
            const Color(0xFF32ADE6),
            const Color(0xFFFF2D55),
          ];
          final color = colors[e.key % colors.length];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.value.key,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    AppText('${e.value.value}', style: AppTextStyles.caption),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 7,
                    backgroundColor: AppColors.background,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Performance card ────────────────────────────────────────────────────────

  /// §10 headline user counts.
  ///
  /// The "unknown" line is deliberate rather than hidden: DOB capture only
  /// began 2026-08-11, so most existing accounts have none. Showing the 45+
  /// figure without saying how many accounts are unaccounted for would present
  /// an undercount as though it were complete.
  Widget _userStatsCard(UserStats stats) {
    final unknown = _ageBrackets['unknown'] ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _statTile(
                  label: context.s.totalUsers,
                  value: stats.totalUsers,
                  icon: Icons.groups_rounded,
                  color: AppColors.primary,
                ),
              ),
              Expanded(
                child: _statTile(
                  label: context.s.residentsCount,
                  value: stats.residents,
                  icon: Icons.home_rounded,
                  color: AppColors.statusResolved,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _statTile(
                  label: context.s.personnelCount,
                  value: stats.personnel,
                  icon: Icons.badge_rounded,
                  color: AppColors.warning,
                ),
              ),
              Expanded(
                child: _statTile(
                  label: context.s.age45Plus,
                  value: stats.age45Plus,
                  icon: Icons.elderly_rounded,
                  color: AppColors.statusInProgress,
                ),
              ),
            ],
          ),
          if (unknown > 0) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 14, color: AppColors.textTertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: AppText(
                    '$unknown ${context.s.ageUnknownNote}',
                    style: AppTextStyles.caption,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statTile({
    required String label,
    required int value,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        AppText(
          '$value',
          style: AppTextStyles.heading2.copyWith(color: color),
        ),
        const SizedBox(height: 2),
        AppText(
          label,
          textAlign: TextAlign.center,
          style: AppTextStyles.caption,
        ),
      ],
    );
  }

  Widget _performanceCard() {
    final avgH = _avgResolutionHours;
    final sla = _slaCompliance;

    String avgLabel;
    if (avgH == 0) {
      avgLabel = 'N/A';
    } else if (avgH < 1) {
      avgLabel = '${(avgH * 60).toStringAsFixed(0)} min';
    } else {
      avgLabel = '${avgH.toStringAsFixed(1)} hrs';
    }

    Color slaColor;
    if (sla >= 80) {
      slaColor = AppColors.success;
    } else if (sla >= 50) {
      slaColor = const Color(0xFFFF9500);
    } else {
      slaColor = AppColors.error;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _perfRow(
            icon: Icons.timer_rounded,
            color: AppColors.primary,
            label: context.s.avgResolutionTime,
            value: avgLabel,
          ),
          const Divider(height: 20),
          _perfRow(
            icon: Icons.verified_rounded,
            color: slaColor,
            label: context.s.slaCompliance,
            value: '${sla.toStringAsFixed(0)}%',
            valueColor: slaColor,
          ),
          const Divider(height: 20),
          _perfRow(
            icon: Icons.check_circle_rounded,
            color: AppColors.statusResolved,
            label: context.s.resolutionRate,
            value: '${_resolutionRate.toStringAsFixed(0)}%',
            valueColor: _resolutionRate >= 70
                ? AppColors.success
                : _resolutionRate >= 40
                    ? const Color(0xFFFF9500)
                    : AppColors.error,
          ),
          const Divider(height: 20),
          _perfRow(
            icon: Icons.warning_rounded,
            color: AppColors.error,
            label: context.s.currentlyOverdue,
            value: '$_overdue report${_overdue == 1 ? '' : 's'}',
            valueColor: _overdue > 0 ? AppColors.error : AppColors.textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _perfRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AppText(label,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: AppColors.textSecondary,
              )),
        ),
        AppText(
          value,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
