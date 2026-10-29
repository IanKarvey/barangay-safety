import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../l10n/app_strings.dart';
import '../../services/escalation_service.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import '../../widgets/loading_overlay.dart';

/// What the system has done on its own, in one place for officials.
///
/// Two lists. **Escalations** are reports that crossed a response-time line and
/// were pushed up the chain by the scheduled job. **Referrals** are people who
/// tried to report a fire or an accident and were told to call the right agency.
///
/// Both exist because the automation is otherwise invisible: an escalation shows
/// up as one notification to one person, and a referral by definition never
/// becomes an incident, so without this screen there is nowhere to see that
/// either happened, or how often.
class EscalationsScreen extends StatefulWidget {
  const EscalationsScreen({super.key, this.source});

  /// Where the data comes from; defaults to Supabase. Injectable for tests.
  final EscalationSource? source;

  @override
  State<EscalationsScreen> createState() => _EscalationsScreenState();
}

class _EscalationsScreenState extends State<EscalationsScreen> {
  late final EscalationSource _source = widget.source ?? SupabaseEscalationSource();
  late Future<(List<EscalationEntry>, List<ReferralEntry>)> _future = _load();

  Future<(List<EscalationEntry>, List<ReferralEntry>)> _load() async {
    final results = await Future.wait([_source.escalations(), _source.referrals()]);
    return (
      results[0] as List<EscalationEntry>,
      results[1] as List<ReferralEntry>,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Escalations & Referrals'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _refresh,
            ),
          ],
        ),
        body: FutureBuilder(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return EmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'Could not load',
                subtitle: 'Check your connection and pull to refresh.',
                action: TextButton(
                  onPressed: _refresh,
                  child: const Text('Try again'),
                ),
              );
            }
            final (escalations, referrals) = snap.data!;
            return Column(
              children: [
                // Summary, tabs and list share one column width so they line up
                // on a desktop; the white band behind the tabs still runs the
                // full width.
                _Narrow(
                  child: _Summary(escalations: escalations, referrals: referrals),
                ),
                Container(
                  color: AppColors.surface,
                  child: _Narrow(
                    child: TabBar(
                      labelColor: AppColors.primary,
                      unselectedLabelColor: AppColors.textSecondary,
                      indicatorColor: AppColors.primary,
                      tabs: [
                        Tab(text: 'Escalations (${escalations.length})'),
                        Tab(text: 'Referrals (${referrals.length})'),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _List(
                        onRefresh: _refresh,
                        empty: const EmptyState(
                          icon: Icons.verified_rounded,
                          title: 'Nothing escalated',
                          subtitle: 'Every report has been answered within its '
                              'time limit.',
                        ),
                        children: [
                          for (final (i, e) in escalations.indexed)
                            _EscalationTile(entry: e).animate(
                              delay: Duration(milliseconds: 40 * (i > 8 ? 8 : i)),
                            ).fadeIn(duration: 250.ms).slideY(
                                  begin: 0.08,
                                  end: 0,
                                  duration: 300.ms,
                                  curve: Curves.easeOutCubic,
                                ),
                        ],
                      ),
                      _List(
                        onRefresh: _refresh,
                        empty: const EmptyState(
                          icon: Icons.phone_in_talk_rounded,
                          title: 'No referrals yet',
                          subtitle: 'When someone tries to report a fire or an '
                              'accident, it is recorded here.',
                        ),
                        children: [
                          for (final (i, r) in referrals.indexed)
                            _ReferralTile(entry: r).animate(
                              delay: Duration(milliseconds: 40 * (i > 8 ? 8 : i)),
                            ).fadeIn(duration: 250.ms).slideY(
                                  begin: 0.08,
                                  end: 0,
                                  duration: 300.ms,
                                  curve: Curves.easeOutCubic,
                                ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One column width for everything on the screen. A row of text across a 1300px
/// window is harder to read than a phone's, not easier.
const double _kColumnWidth = 760;

class _Narrow extends StatelessWidget {
  const _Narrow({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kColumnWidth),
          child: child,
        ),
      );
}

/// The three tiers of an UNANSWERED report: nobody has acted on it.
({String label, Color color, IconData icon}) _unansweredStyle(int level) =>
    switch (level) {
      1 => (
          label: 'No response',
          color: AppColors.warning,
          icon: Icons.hourglass_top_rounded,
        ),
      2 => (
          label: 'Whole barangay',
          color: const Color(0xFFEA580C),
          icon: Icons.campaign_rounded,
        ),
      _ => (
          label: 'Last resort',
          color: AppColors.error,
          icon: Icons.crisis_alert_rounded,
        ),
    };

/// The three level colours, shared so the chip, the summary and the tile agree.
({String label, Color color, IconData icon}) _levelStyle(int level) =>
    switch (level) {
      1 => (
          label: 'Reminder',
          color: AppColors.warning,
          icon: Icons.notifications_active_rounded,
        ),
      2 => (
          label: 'Overdue',
          color: const Color(0xFFEA580C),
          icon: Icons.timer_off_rounded,
        ),
      _ => (
          label: 'City level',
          color: AppColors.error,
          icon: Icons.account_balance_rounded,
        ),
    };

class _Summary extends StatelessWidget {
  const _Summary({required this.escalations, required this.referrals});

  final List<EscalationEntry> escalations;
  final List<ReferralEntry> referrals;

  @override
  Widget build(BuildContext context) {
    int at(int level) => escalations
        .where((e) => !e.unanswered && e.level == level)
        .length;
    int atUnanswered(int level) => escalations
        .where((e) => e.unanswered && e.level == level)
        .length;

    Widget stat(String label, int value, Color color, IconData icon) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$value',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: color,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

    final l1 = _levelStyle(1), l2 = _levelStyle(2), l3 = _levelStyle(3);
    final u1 = _unansweredStyle(1), u2 = _unansweredStyle(2), u3 = _unansweredStyle(3);
    Widget caption(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(text, style: AppTextStyles.caption),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          caption('Nobody answered — 5 / 10 / 15 minutes'),
          Row(
            children: [
              stat(u1.label, atUnanswered(1), u1.color, u1.icon),
              const SizedBox(width: 10),
              stat(u2.label, atUnanswered(2), u2.color, u2.icon),
              const SizedBox(width: 10),
              stat(u3.label, atUnanswered(3), u3.color, u3.icon),
            ],
          ),
          const SizedBox(height: 12),
          caption('Taking too long — 24 / 48 / 72 hours'),
          Row(
            children: [
              stat(l1.label, at(1), l1.color, l1.icon),
              const SizedBox(width: 10),
              stat(l2.label, at(2), l2.color, l2.icon),
              const SizedBox(width: 10),
              stat(l3.label, at(3), l3.color, l3.icon),
            ],
          ),
        ],
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({
    required this.children,
    required this.empty,
    required this.onRefresh,
  });

  final List<Widget> children;
  final Widget empty;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return empty;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: Align(
        alignment: Alignment.topCenter,
        // A desktop browser gives this the whole window; a row of text across
        // 1300px is harder to read than a phone's, not easier.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kColumnWidth),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: children,
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.chip,
    required this.trailing,
    this.onTap,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final String chip;
  final String trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 21, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.heading3
                                  .copyWith(fontSize: 15),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              chip,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(trailing, style: AppTextStyles.caption),
                    if (onTap != null)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Icon(Icons.chevron_right_rounded,
                            size: 20, color: AppColors.textTertiary),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EscalationTile extends StatelessWidget {
  const _EscalationTile({required this.entry});

  final EscalationEntry entry;

  @override
  Widget build(BuildContext context) {
    final style = entry.unanswered
        ? _unansweredStyle(entry.level)
        : _levelStyle(entry.level);
    final where = entry.barangayName ?? 'Unknown barangay';
    final told = entry.recipients == 1 ? '1 official' : '${entry.recipients} officials';
    return _Tile(
      color: style.color,
      icon: style.icon,
      title: categoryLabel(context.s, entry.category),
      subtitle: '$where · $told notified',
      chip: style.label,
      trailing: timeAgo(entry.createdAt),
      // Straight to the report, so the person who got the alert can act on it.
      onTap: () => Navigator.pushNamed(
        context,
        '/incident-manage',
        arguments: entry.incidentId,
      ),
    );
  }
}

class _ReferralTile extends StatelessWidget {
  const _ReferralTile({required this.entry});

  final ReferralEntry entry;

  static const _agencies = {
    'fire': ('Fire Dept', Icons.local_fire_department_rounded, Color(0xFFDC2626)),
    'police': ('Police', Icons.local_police_rounded, Color(0xFF1D4ED8)),
    'medical': ('Medical', Icons.medical_services_rounded, Color(0xFFBE123C)),
    'disaster': ('CDRRMO', Icons.flood_rounded, Color(0xFF0E7490)),
    'lto': ('LTO', Icons.directions_car_rounded, Color(0xFF6D28D9)),
  };

  @override
  Widget build(BuildContext context) {
    final a = _agencies[entry.agency] ??
        ('Agency', Icons.phone_in_talk_rounded, AppColors.primary);
    return _Tile(
      color: a.$3,
      icon: a.$2,
      title: categoryLabel(context.s, entry.category),
      subtitle: '${entry.barangayName ?? 'Unknown barangay'} · sent to call '
          '${a.$1}',
      chip: a.$1,
      trailing: timeAgo(entry.createdAt),
    );
  }
}
