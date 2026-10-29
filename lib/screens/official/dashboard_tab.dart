import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/incident_provider.dart';
import '../../providers/notification_provider.dart';
import '../../models/incident_model.dart';
import '../../utils/constants.dart';
import '../../utils/permissions.dart';
import '../../utils/animations.dart';
import '../../widgets/widgets.dart';
import '../../l10n/app_strings.dart';
import '../../utils/severity.dart';
import '../../widgets/app_text.dart';
import '../../widgets/responsive_layout.dart';

class DashboardTab extends StatelessWidget {
  final VoidCallback onRefresh;
  final VoidCallback? onViewAll;

  const DashboardTab({super.key, required this.onRefresh, this.onViewAll});

  String _greeting(AppStrings s) {
    final h = DateTime.now().hour;
    if (h < 12) return s.goodMorning;
    if (h < 17) return s.goodAfternoon;
    return s.goodEvening;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final provider = context.watch<IncidentProvider>();
    final stats = provider.stats;

    final total = stats['total'] ?? 0;
    final pending = stats['pending'] ?? 0;
    final inProgress = stats['in_progress'] ?? 0;
    final resolved = stats['resolved'] ?? 0;
    final flagged = stats['flagged'] ?? 0;
    final resolutionRate = total > 0 ? (resolved / total * 100).round() : 0;

    // Everything on this dashboard reads from `incidents`, so scoping once
    // here covers the urgent list, the severity chart and Recent Incidents.
    final incidents = visibleIncidents(user, provider.incidents);

    final urgentIncidents = incidents
        .where((i) =>
            (i.isPending || i.isInProgress) &&
            Severity.isUrgent(i.severityLevel))
        .take(3)
        .toList();

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async => onRefresh(),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            // ── Enhanced Header ───────────────────────────────────────────
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primaryDark, AppColors.primary, Color(0xFF1976D2)],
                  ),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon row (bell + 4 actions) is now BELOW the identity
                    // block, directly as this Column's own children — no
                    // wrapping Row, no Expanded, no sibling of any kind. A
                    // prior pass moved the 5 IconButtons to their own row but
                    // left LanguageToggle sharing this space with the
                    // Expanded text column; confirmed on-device 2026-09-16
                    // that the ~110px toggle plus its gap was STILL enough to
                    // starve "Administrator" at 22px bold below its legal
                    // word-boundary break point. The toggle now lives in the
                    // controls row below, with everything else.
                    AppText(
                      '${_greeting(context.s)},',
                      style: AppTextStyles.body.copyWith(color: Colors.white70),
                    )
                        .animate()
                        .fadeIn(duration: 280.ms)
                        .slideX(begin: -0.08, end: 0, duration: 300.ms, curve: Curves.easeOutCubic),
                    SplitText(
                      user?.fullName.split(' ').first ?? 'Official',
                      style: AppTextStyles.heading2.copyWith(color: Colors.white),
                      baseDelay: const Duration(milliseconds: 80),
                      charDelay: const Duration(milliseconds: 40),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: Colors.white60, size: 13),
                        const SizedBox(width: 3),
                        Flexible(
                          child: AppText(
                            user?.barangayName ?? 'Barangay',
                            style: AppTextStyles.bodySmall.copyWith(color: Colors.white70),
                            overflow: TextOverflow.ellipsis,
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
                            arguments: false,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.bar_chart_rounded, color: Colors.white70),
                          tooltip: context.s.analytics,
                          onPressed: () => Navigator.pushNamed(
                            context,
                            '/analytics',
                            arguments: false,
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
                    if (pending > 0 || flagged > 0) ...[
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: onViewAll,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.notifications_active_rounded,
                                  color: Colors.white, size: 16),
                              const SizedBox(width: 10),
                              Expanded(
                                child: AppText(
                                  flagged > 0
                                      ? context.s.flaggedNeedReview(flagged)
                                      : context.s.awaitingAction(pending),
                                  style: AppTextStyles.body.copyWith(
                                      color: Colors.white, fontSize: 13),
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios,
                                  color: Colors.white60, size: 12),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── Non-Resident Emergency Reports ────────────────────────────
            SliverToBoxAdapter(
              child: StaleCasePrompt(onResolved: onRefresh),
            ),

            SliverToBoxAdapter(
              child: ScrollReveal(
                delay: const Duration(milliseconds: 100),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.pushNamed(
                          context, '/non-resident-queue'),
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
                                color:
                                    AppColors.error.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                  Icons.emergency_share_rounded,
                                  color: AppColors.error,
                                  size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  AppText(context.s.nonResidentReports,
                                      style: AppTextStyles.body.copyWith(
                                          fontWeight: FontWeight.w700)),
                                  Text(context.s.emergencyFromVisitors,
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
            ),

            // What the system did on its own: reports pushed up the chain, and
            // people sent to call the fire department. Static on purpose — it
            // loads nothing, so opening the dashboard costs no extra query.
            SliverToBoxAdapter(
              child: ScrollReveal(
                delay: const Duration(milliseconds: 120),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.pushNamed(context, '/escalations'),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: AppColors.warning.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.trending_up_rounded,
                                  color: AppColors.warning, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AppText('Escalations & Referrals',
                                      style: AppTextStyles.body.copyWith(
                                          fontWeight: FontWeight.w700)),
                                  Text(
                                      'Overdue reports and calls sent to the right agency',
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
            ),

            // ── Stat Cards (horizontal scroll) ────────────────────────────
            SliverToBoxAdapter(
              child: ScrollReveal(
                delay: const Duration(milliseconds: 140),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 0, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: AppText(context.s.overview, style: AppTextStyles.heading3),
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(builder: (context, c) {
                        final stats = [
                          ('Total', total, Icons.description_rounded, AppColors.primary),
                          ('Pending', pending, Icons.schedule_rounded, AppColors.statusPending),
                          ('In Progress', inProgress, Icons.autorenew_rounded, AppColors.statusInProgress),
                          ('Resolved', resolved, Icons.check_circle_rounded, AppColors.statusResolved),
                          ('Flagged', flagged, Icons.flag_rounded, AppColors.error),
                        ];
                        // On a phone five fixed-width chips scroll sideways. On
                        // a desktop that leaves them huddled at the left of an
                        // empty strip, so they share the width evenly instead.
                        if (c.maxWidth >= kWideBreakpoint) {
                          return SizedBox(
                            height: 112,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 16),
                              child: Row(
                                children: [
                                  for (final (i, st) in stats.indexed) ...[
                                    if (i > 0) const SizedBox(width: 12),
                                    Expanded(
                                      child: _statChip(st.$1, st.$2, st.$3, st.$4, i, fill: true),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }
                        return SizedBox(
                          height: 112,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.only(right: 16),
                            children: [
                              for (final (i, st) in stats.indexed)
                                _statChip(st.$1, st.$2, st.$3, st.$4, i),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),

            // ── Resolution Rate + Severity Breakdown ──────────────────────
            // Stacked on a phone; side by side on a desktop, where each alone
            // would be a 1300px-wide strip with a single number in it.
            if (total > 0 || incidents.isNotEmpty)
              SliverToBoxAdapter(
                child: ScrollReveal(
                  delay: const Duration(milliseconds: 260),
                  child: LayoutBuilder(builder: (context, c) {
                    final wide = c.maxWidth >= kWideBreakpoint;
                    // In a Row each card needs only a 16px outer edge, not the
                    // 16px-per-side that would make a 32px gap between them.
                    const phone = EdgeInsets.fromLTRB(16, 8, 16, 4);
                    final resolution = total > 0
                        ? _buildResolutionCard(
                            context.s, resolutionRate, resolved, total,
                            margin: wide ? const EdgeInsets.fromLTRB(16, 8, 0, 4) : phone)
                        : null;
                    final severity = incidents.isNotEmpty
                        ? _buildSeverityChart(
                            context.s, incidents,
                            margin: wide ? const EdgeInsets.fromLTRB(0, 8, 16, 4) : phone)
                        : null;
                    if (wide && resolution != null && severity != null) {
                      // start, NOT stretch: this sits in a scroll view, where height is
                      // unbounded, and a stretching Row there asks its children for
                      // infinite height. That threw and took every sliver below it off
                      // the screen (found 2026-10-14, reproduced in a test).
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: resolution),
                          const SizedBox(width: 16),
                          Expanded(child: severity),
                        ],
                      );
                    }
                    return Column(children: [
                      if (resolution != null) resolution,
                      if (severity != null) severity,
                    ]);
                  }),
                ),
              ),

            // ── Urgent Attention ──────────────────────────────────────────
            if (urgentIncidents.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: ScrollReveal(
                  delay: const Duration(milliseconds: 160),
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
                        AppText(context.s.needsAttention,
                            style: AppTextStyles.heading3),
                      ],
                    ),
                  ),
                ),
              ),
              // Two columns on a desktop, one on a phone. Not lazy, which is
              // fine: both lists are short (urgent cases, and recent capped
              // at 10), and TwoColumnFlow needs every child to split them.
              SliverToBoxAdapter(
                child: TwoColumnFlow(
                  children: [
                    for (final incident in urgentIncidents)
                      IncidentCard(
                        incident: incident,
                        showReporter: true,
                        onTap: () => Navigator.pushNamed(
                          context,
                          '/incident-manage',
                          arguments: incident.id,
                        ).then((_) => onRefresh()),
                      ),
                  ],
                ),
              ),
            ],

            // ── Recent Incidents ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: ScrollReveal(
                delay: const Duration(milliseconds: 80),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(child: AppText(context.s.recentIncidents, style: AppTextStyles.heading3)),
                      if (incidents.length > 5)
                        TextButton(
                          onPressed: onViewAll,
                          child: Text(context.s.viewAll),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            if (provider.isLoading)
              const SliverToBoxAdapter(child: IncidentListShimmer(count: 4))
            else if (incidents.isEmpty)
              SliverFillRemaining(
                child: EmptyState(
                  icon: Icons.inbox_rounded,
                  title: context.s.noIncidents,
                  subtitle: context.s.noIncidentsSubtitle,
                ),
              )
            else
              SliverToBoxAdapter(
                child: TwoColumnFlow(
                  children: [
                    for (final (index, incident)
                        in incidents.take(10).toList().indexed)
                      IncidentCard(
                        incident: incident,
                        showReporter: true,
                        onTap: () => Navigator.pushNamed(
                          context,
                          '/incident-manage',
                          arguments: incident.id,
                        ).then((_) => onRefresh()),
                      )
                          .animate(delay: AppAnimations.stagger(index))
                          .fadeIn(duration: AppAnimations.normal, curve: AppAnimations.smooth)
                          .slideY(begin: 0.06, end: 0, duration: AppAnimations.normal, curve: AppAnimations.smooth),
                  ],
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  // ── Stat chip card ────────────────────────────────────────────────────
  Widget _statChip(String label, int value, IconData icon, Color color, int index,
      {bool fill = false}) {
    return Container(
      width: fill ? null : 112,
      margin: EdgeInsets.only(right: fill ? 0 : 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 20,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: value),
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => AppText(
              '$v',
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                height: 1.0,
                letterSpacing: -0.5,
              ),
            ),
          ),
          Text(
            label,
            style: AppTextStyles.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    )
        .animate(delay: AppAnimations.stagger(index, base: 100, step: 70))
        .fadeIn(duration: AppAnimations.normal, curve: AppAnimations.smooth)
        .slideX(begin: 0.2, end: 0, duration: AppAnimations.normal, curve: AppAnimations.smooth);
  }

  // ── Resolution rate card ──────────────────────────────────────────────
  Widget _buildResolutionCard(AppStrings t, int rate, int resolved, int total,
      {EdgeInsets margin = const EdgeInsets.fromLTRB(16, 8, 16, 4)}) {
    final Color rateColor = rate >= 70
        ? AppColors.statusResolved
        : rate >= 40
            ? AppColors.warning
            : AppColors.error;

    return Container(
      margin: margin,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up_rounded,
                  color: AppColors.statusResolved, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: AppText(t.resolutionRate, style: AppTextStyles.heading3),
              ),
              TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: rate),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => Text(
                  '$v%',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: rateColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: rate / 100),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: v,
                backgroundColor: AppColors.divider,
                valueColor: AlwaysStoppedAnimation(rateColor),
                minHeight: 8,
              ),
            ),
          ),
          const SizedBox(height: 7),
          AppText(
            '$resolved of $total reports resolved',
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }

  // ── Severity breakdown bar chart ──────────────────────────────────────
  Widget _buildSeverityChart(AppStrings t, List<IncidentModel> incidents,
      {EdgeInsets margin = const EdgeInsets.fromLTRB(16, 8, 16, 4)}) {
    final labels = ['Critical', 'High', 'Medium', 'Low'];
    final colors = [
      AppColors.severityCritical,
      AppColors.severityHigh,
      AppColors.severityMedium,
      AppColors.severityLow,
    ];
    final counts = List.generate(
      4,
      (i) => incidents
          .where((inc) => inc.severityLevel == i + 1 && inc.status != 'resolved')
          .length,
    );
    final maxCount = counts.fold(0, (a, b) => a > b ? a : b);
    if (maxCount == 0) return const SizedBox.shrink();

    return Container(
      margin: margin,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded,
                  color: AppColors.primary, size: 18),
              const SizedBox(width: 6),
              AppText(t.activeBySeverity, style: AppTextStyles.heading3),
              const Spacer(),
              Text(
                'Unresolved only',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 130,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (maxCount + 1).toDouble(),
                barGroups: List.generate(
                  4,
                  (i) => BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: counts[i].toDouble(),
                        color: colors[i],
                        width: 34,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, _) => Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          labels[value.toInt()],
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: colors[value.toInt()],
                          ),
                        ),
                      ),
                    ),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (value, _) {
                        final c = counts[value.toInt()];
                        return AppText(
                          '$c',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
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
