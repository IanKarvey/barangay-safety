import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/response_metric.dart';
import '../../providers/auth_provider.dart';
import '../../services/response_metrics_service.dart';
import '../../utils/constants.dart';
import '../../utils/file_download.dart';
import '../../widgets/export_format_sheet.dart';
import '../../utils/manila_time.dart';
import '../../utils/response_export.dart';
import '../../utils/response_stats.dart';

/// Response-time analytics: how fast the barangay answers, how often it had to
/// be chased, and how that compares with the old manual process.
///
/// Every number on this page is computed by [summarizeRows] from the SAME
/// filtered list that the export is built from, so a figure on screen and the
/// same figure in the Excel file cannot differ.
///
/// Personal data: the page and the export carry the resident's name and nothing
/// else about them — no location, phone, email, ID or photo exists in the data
/// this page reads (see the `report_response_metrics` view).
class ResponseAnalyticsScreen extends StatefulWidget {
  const ResponseAnalyticsScreen({
    super.key,
    this.source,
    this.today,
    this.downloader,
    this.canExport,
  });

  /// Where data comes from. Tests pass fixed data; the app uses the database.
  final ResponseDataSource? source;

  /// "Today" in Philippine time, for the default date range (tests fix it).
  final DateTime? today;

  /// Hands a finished file to the user. Defaults to a browser download; tests
  /// capture it instead.
  final Future<void> Function(String fileName, Uint8List bytes,
      {required String mimeType})? downloader;

  /// Whether the export buttons show. Defaults to "only where a file can be
  /// downloaded" (the web dashboard).
  final bool? canExport;

  @override
  State<ResponseAnalyticsScreen> createState() =>
      _ResponseAnalyticsScreenState();
}

class _ResponseAnalyticsScreenState extends State<ResponseAnalyticsScreen> {
  late final ResponseDataSource _source =
      widget.source ?? ResponseMetricsService();

  late DateTime _from;
  late DateTime _to;

  List<ResponseMetricRow> _all = const [];
  bool _loading = true;
  bool _truncated = false;
  String? _error;
  bool _exporting = false;

  // Filters applied on this side, so the cards, charts and export all read the
  // same list.
  String? _barangay;
  String? _category;
  int? _severity;
  String? _status;
  int? _minLevel;
  String? _responder;

  @override
  void initState() {
    super.initState();
    final nowManila = (widget.today ?? DateTime.now().toUtc().add(kManilaOffset));
    _to = DateTime(nowManila.year, nowManila.month, nowManila.day);
    _from = _to.subtract(const Duration(days: 29));
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _source.fetchRows(from: _from, to: _to);
      if (!mounted) return;
      setState(() {
        _all = result.rows;
        _truncated = result.truncated;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load response times. Check the connection and try again.';
        _loading = false;
      });
    }
  }

  List<ResponseMetricRow> get _filtered => _all.where((r) {
        if (_barangay != null && r.barangayName != _barangay) return false;
        if (_category != null && r.category != _category) return false;
        if (_severity != null && r.severity != _severity) return false;
        if (_status != null && r.finalStatus != _status) return false;
        if (_minLevel != null && r.escalationLevel < _minLevel!) return false;
        if (_responder != null && r.responderName != _responder) return false;
        return true;
      }).toList();

  List<String> _distinct(String? Function(ResponseMetricRow) f) =>
      (_all.map(f).whereType<String>().toSet().toList()..sort());

  bool get _anyFilter =>
      _barangay != null ||
      _category != null ||
      _severity != null ||
      _status != null ||
      _minLevel != null ||
      _responder != null;

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2026, 1, 1),
      lastDate: _to.add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked == null) return;
    _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
    _to = DateTime(picked.end.year, picked.end.month, picked.end.day);
    await _load();
  }

  ExportFilters _exportFilters() {
    final names = _distinct((r) => r.barangayName);
    return ExportFilters(
      from: _from,
      to: _to,
      // An admin only ever receives their own barangay, so name it even though
      // they never picked it.
      barangayName: _barangay ?? (names.length == 1 ? names.first : null),
      category: _category,
      severity: _severity,
      status: _status,
      escalationLevel: _minLevel,
      responder: _responder,
    );
  }

  Future<void> _export(String format) async {
    final user = context.read<AuthProvider>().user;
    final rows = _filtered;
    if (user == null || rows.isEmpty || _exporting) return;

    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ids = rows.map((r) => r.reportId).toList();
      final logs = await _source.fetchStatusLogs(ids);
      final events = await _source.fetchEscalations(ids);
      final filters = _exportFilters();
      final export = ResponseExport(
        rows: rows,
        statusLogs: logs,
        escalations: events,
        filters: filters,
      );

      // Record it BEFORE handing over the file. If the record cannot be written
      // the export does not happen: an export nobody can account for is worse
      // than one that has to be retried.
      await _source.logExport(
        userId: user.id,
        userName: user.fullName,
        barangayId: user.isSuperAdmin ? null : user.barangayId,
        format: format,
        filters: filters,
        rowCount: rows.length,
      );

      final (bytes, mime) = switch (format) {
        'xlsx' => (export.buildXlsx(), ExportFormat.excel.mimeType),
        'docx' => (export.buildDocx(), ExportFormat.word.mimeType),
        _ => (export.buildCsv(), 'text/csv;charset=utf-8'),
      };
      await (widget.downloader ?? downloadFile)(
        export.fileName(format),
        bytes,
        mimeType: mime,
      );
      messenger.showSnackBar(SnackBar(
        content: Text('Exported ${rows.length} reports (${format.toUpperCase()}).'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      debugPrint('ResponseAnalytics: export failed — $e');
      messenger.showSnackBar(const SnackBar(
        content: Text('The export could not be completed or recorded. Nothing was downloaded — please try again.'),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _filterBar(),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _message(Icons.cloud_off_rounded, _error!, action: ('Try again', _load))
            else
              ..._body(),
          ],
        ),
      ),
    );
  }

  List<Widget> _body() {
    final rows = _filtered;
    if (_all.isEmpty) {
      return [
        _message(
          Icons.timer_outlined,
          'No reports in this date range yet. Response times appear here as '
          'reports come in — reports filed before tracking began are not estimated.',
        ),
      ];
    }
    if (rows.isEmpty) {
      return [_message(Icons.filter_alt_off_rounded, 'No reports match these filters.')];
    }

    final s = summarizeRows(rows);
    return [
      if (_truncated)
        _notice('Showing the newest ${ResponseMetricsService.maxRows} reports. Narrow the date range to see the rest.'),
      _summaryCards(s),
      const SizedBox(height: 14),
      _baselineCard(s),
      const SizedBox(height: 14),
      _trendCard(rows),
      const SizedBox(height: 14),
      LayoutBuilder(builder: (context, c) {
        final cards = [
          _barsCard('Median first response by barangay', _medianBars(rows, (r) => r.barangayName ?? '(unknown)')),
          _barsCard('Median first response by category', _medianBars(rows, (r) => r.category)),
          _barsCard('Median first response by severity',
              _medianBars(rows, (r) => '${4 - r.severity} ${severityName(r.severity)}', trimSortKey: true)),
          _barsCard('Escalated reports per barangay', _escalationBars(rows), unit: 'reports', isCount: true),
        ];
        if (c.maxWidth < 760) {
          return Column(children: [
            for (final w in cards) ...[w, const SizedBox(height: 14)],
          ]);
        }
        return Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 14),
            Expanded(child: cards[1]),
          ]),
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: cards[2]),
            const SizedBox(width: 14),
            Expanded(child: cards[3]),
          ]),
        ]);
      }),
    ];
  }

  // ── Filters + export ──────────────────────────────────────────────────────
  Widget _filterBar() {
    final user = context.watch<AuthProvider>().user;
    final rows = _filtered;
    return _card(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: _loading ? null : _pickRange,
            icon: const Icon(Icons.date_range_rounded, size: 18),
            label: Text('${manilaDate(_from)}  to  ${manilaDate(_to)}'),
          ),
          if (user?.isSuperAdmin ?? false)
            _dropdown<String>('Barangay', _barangay, _distinct((r) => r.barangayName),
                (v) => setState(() => _barangay = v), (v) => v),
          _dropdown<String>('Category', _category, _distinct((r) => r.category),
              (v) => setState(() => _category = v), (v) => v),
          _dropdown<int>('Severity', _severity, const [4, 3, 2, 1],
              (v) => setState(() => _severity = v), severityName),
          _dropdown<String>('Status', _status, _distinct((r) => r.finalStatus),
              (v) => setState(() => _status = v), (v) => v),
          _dropdown<int>('Escalation', _minLevel, const [1, 2, 3],
              (v) => setState(() => _minLevel = v), (v) => 'Level $v+'),
          _dropdown<String>('Responder', _responder, _distinct((r) => r.responderName),
              (v) => setState(() => _responder = v), (v) => v),
          if (_anyFilter)
            TextButton(
              onPressed: () => setState(() {
                _barangay = _category = _status = _responder = null;
                _severity = _minLevel = null;
              }),
              child: const Text('Reset'),
            ),
          const SizedBox(width: 6),
          if (widget.canExport ?? kCanDownloadFiles) ...[
            FilledButton.icon(
              onPressed: rows.isEmpty || _exporting ? null : () => _export('xlsx'),
              icon: _exporting
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.table_chart_rounded, size: 18),
              label: const Text('Export Excel'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
              onPressed: rows.isEmpty || _exporting ? null : () => _export('docx'),
              icon: const Icon(Icons.description_rounded, size: 18),
              label: const Text('Export Word'),
            ),
            OutlinedButton.icon(
              onPressed: rows.isEmpty || _exporting ? null : () => _export('csv'),
              icon: const Icon(Icons.table_rows_outlined, size: 18),
              label: const Text('Export CSV'),
            ),
          ] else
            Text('Export is available on the web dashboard.',
                style: AppTextStyles.caption),
        ],
      ),
    );
  }

  Widget _dropdown<T>(
    String label,
    T? value,
    List<T> options,
    ValueChanged<T?> onChanged,
    String Function(T) text,
  ) {
    return SizedBox(
      width: 168,
      child: DropdownButtonFormField<T>(
        // A form field only reads initialValue once; the key makes Reset (and
        // any other change made from outside) actually show.
        key: ValueKey('$label-$value'),
        initialValue: value,
        isExpanded: true,
        isDense: true,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        ),
        items: [
          DropdownMenuItem<T>(value: null, child: Text('All', style: AppTextStyles.bodySmall)),
          for (final o in options)
            DropdownMenuItem<T>(
              value: o,
              child: Text(text(o), overflow: TextOverflow.ellipsis, style: AppTextStyles.bodySmall),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }

  // ── Cards ─────────────────────────────────────────────────────────────────
  Widget _summaryCards(ResponseSummary s) {
    String t(double? secs) => secs == null ? '—' : formatMinSec(secs);
    String pct(double? v) => v == null ? '—' : '${v.toStringAsFixed(0)}%';
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final perRow = w >= 1100 ? 4 : (w >= 760 ? 3 : 2);
      final cardW = (w - 12 * (perRow - 1)) / perRow;
      Widget stat(String title, String value, String sub, Color color, {IconData? icon}) =>
          SizedBox(
            width: cardW,
            child: _StatCard(title: title, value: value, sub: sub, color: color, icon: icon),
          );
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          stat('Reports', '${s.total}', '${s.answered} answered · ${s.unansweredNow} waiting now',
              AppColors.primary, icon: Icons.assignment_rounded),
          stat('Average first response', t(s.firstResponse.average),
              '${s.firstResponse.count} reports counted', AppColors.accent,
              icon: Icons.timer_outlined),
          stat('Median first response', t(s.firstResponse.median),
              '90th percentile ${t(s.firstResponse.p90)}', AppColors.accent,
              icon: Icons.speed_rounded),
          stat('Answered within 5 min', pct(s.percentWithin5),
              '${s.within5} of ${s.answered} answered', const Color(0xFF16A34A),
              icon: Icons.bolt_rounded),
          stat('Answered within 10 min', pct(s.percentWithin10),
              '${s.within10} of ${s.answered} answered', const Color(0xFFCA8A04),
              icon: Icons.bolt_rounded),
          stat('Answered within 15 min', pct(s.percentWithin15),
              '${s.within15} of ${s.answered} answered', const Color(0xFFEA580C),
              icon: Icons.bolt_rounded),
          stat('Escalated reports', '${s.escalated}',
              'Level 2 or higher: ${s.reachedLevel2}', AppColors.warning,
              icon: Icons.trending_up_rounded),
          stat('Level 3 — Unattended', '${s.reachedLevel3}',
              'reached the last resort', AppColors.error,
              icon: Icons.crisis_alert_rounded),
        ],
      );
    });
  }

  Widget _baselineCard(ResponseSummary s) {
    final median = s.dispatch.median;
    final fast = s.dispatchImprovementVs(kManualBaselineMinMinutes);
    final slow = s.dispatchImprovementVs(kManualBaselineMaxMinutes);
    final maxMin = [
      kManualBaselineMaxMinutes.toDouble(),
      if (median != null) median / 60,
    ].reduce((a, b) => a > b ? a : b);

    Widget bar(String label, double minutes, Color color, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(width: 170, child: Text(label, style: AppTextStyles.bodySmall)),
              Expanded(
                child: LayoutBuilder(builder: (context, c) => Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 18,
                    width: (c.maxWidth * (minutes / maxMin)).clamp(4.0, c.maxWidth),
                    decoration: BoxDecoration(
                        color: color, borderRadius: BorderRadius.circular(5)),
                  ),
                )),
              ),
              SizedBox(
                width: 84,
                child: Text(text, textAlign: TextAlign.right,
                    style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Compared with the manual process', style: AppTextStyles.heading3),
          const SizedBox(height: 4),
          Text(
            'Report to dispatch. Before this system, getting a responder sent '
            'took an estimated $kManualBaselineMinMinutes–$kManualBaselineMaxMinutes minutes.',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 12),
          bar('Manual (best case)', kManualBaselineMinMinutes.toDouble(),
              AppColors.textTertiary, '$kManualBaselineMinMinutes min'),
          bar('Manual (worst case)', kManualBaselineMaxMinutes.toDouble(),
              AppColors.textTertiary, '$kManualBaselineMaxMinutes min'),
          if (median != null)
            bar('This system (median)', median / 60, AppColors.success, formatMinSec(median))
          else
            Text('No dispatches recorded in this range yet.',
                style: AppTextStyles.bodySmall),
          if (fast != null && slow != null) ...[
            const SizedBox(height: 6),
            Text(
              fast >= 0
                  ? '${fast.toStringAsFixed(0)}% faster than the best manual case, '
                      '${slow.toStringAsFixed(0)}% faster than the worst.'
                  : 'Slower than the best manual case by ${(-fast).toStringAsFixed(0)}%.',
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }

  Widget _trendCard(List<ResponseMetricRow> rows) {
    final points = dailyTrend(rows);
    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        if (points[i].medianFirstResponseSecs != null)
          FlSpot(i.toDouble(), points[i].medianFirstResponseSecs! / 60),
    ];
    final maxY = chartMax(spots.map((s) => s.y)) * 1.2;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Median first response over time', style: AppTextStyles.heading3),
          Text('Minutes, by the day the report was filed (Philippine time).',
              style: AppTextStyles.caption),
          const SizedBox(height: 12),
          if (spots.length < 2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  spots.isEmpty
                      ? 'No answered reports in this range yet.'
                      : 'A trend needs at least two days with answered reports.',
                  style: AppTextStyles.bodySmall,
                ),
              ),
            )
          else
            SizedBox(
              height: 200,
              child: LineChart(LineChartData(
                minY: 0,
                maxY: maxY,
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: AppColors.divider, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 38,
                      getTitlesWidget: (v, _) => Text(v.toStringAsFixed(v < 10 ? 1 : 0),
                          style: AppTextStyles.caption),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      interval: (points.length / 6).ceilToDouble().clamp(1, 1000),
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= points.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(points[i].day.substring(5), style: AppTextStyles.caption),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: AppColors.primary,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.primary.withValues(alpha: 0.10),
                    ),
                  ),
                ],
              )),
            ),
        ],
      ),
    );
  }

  List<_Bar> _medianBars(
    List<ResponseMetricRow> rows,
    String Function(ResponseMetricRow) key, {
    bool trimSortKey = false,
  }) {
    final groups = groupSummaries(rows, key);
    return [
      for (final g in groups)
        _Bar(
          trimSortKey ? g.key.substring(2) : g.key,
          g.summary.firstResponse.median == null ? null : g.summary.firstResponse.median! / 60,
          '${g.summary.total} reports',
        ),
    ];
  }

  List<_Bar> _escalationBars(List<ResponseMetricRow> rows) {
    final groups = groupSummaries(rows, (r) => r.barangayName ?? '(unknown)');
    return [
      for (final g in groups)
        _Bar(g.key, g.summary.escalated.toDouble(),
            '${g.summary.reachedLevel3} reached level 3'),
    ];
  }

  Widget _barsCard(String title, List<_Bar> bars,
      {String unit = 'min', bool isCount = false}) {
    final max = chartMax(bars.map((b) => b.value));
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.heading3),
          const SizedBox(height: 10),
          if (bars.isEmpty)
            Text('Nothing to show.', style: AppTextStyles.bodySmall)
          else
            for (final b in bars)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(b.label,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall),
                    ),
                    Expanded(
                      child: LayoutBuilder(builder: (context, c) => Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 16,
                          width: b.value == null
                              ? 0
                              : (c.maxWidth * (b.value! / max)).clamp(3.0, c.maxWidth),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      )),
                    ),
                    SizedBox(
                      width: 96,
                      child: Text(
                        b.value == null
                            ? 'no data'
                            : isCount
                                ? '${b.value!.toInt()} ${b.value!.toInt() == 1 ? 'report' : unit}'
                                : formatMinSec(b.value! * 60),
                        textAlign: TextAlign.right,
                        style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  // ── Small pieces ──────────────────────────────────────────────────────────
  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.divider),
        ),
        child: child,
      );

  Widget _message(IconData icon, String text, {(String, VoidCallback)? action}) =>
      _card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Column(
            children: [
              Icon(icon, size: 40, color: AppColors.textTertiary),
              const SizedBox(height: 10),
              Text(text, textAlign: TextAlign.center, style: AppTextStyles.body),
              if (action != null) ...[
                const SizedBox(height: 12),
                FilledButton(onPressed: action.$2, child: Text(action.$1)),
              ],
            ],
          ),
        ),
      );

  Widget _notice(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
          ),
          child: Text(text, style: AppTextStyles.bodySmall),
        ),
      );
}

class _Bar {
  const _Bar(this.label, this.value, this.note);
  final String label;
  final double? value;
  final String note;
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.sub,
    required this.color,
    this.icon,
  });

  final String title;
  final String value;
  final String sub;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
