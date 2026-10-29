import 'package:flutter/material.dart';

import '../utils/constants.dart';
import '../utils/helpers.dart' show severityColor;
import '../utils/manila_time.dart';
import '../utils/report_log.dart';
import '../utils/response_stats.dart';

enum _LogFilter { all, open, finished }

/// Every report in the chosen period, one card each: what it was, who reported
/// it, when, who responded, and how long it took to finish — or how long it has
/// been waiting. This is the on-screen twin of the "All Reports" sheet in the
/// Excel and Word exports, built from the same [ReportLogEntry] list, so what an
/// official reads here is exactly what they export.
///
/// Shows the newest first, 15 at a time, with a search box and Open / Finished
/// filters. The export always contains every report, whatever is filtered here.
class ReportLogSection extends StatefulWidget {
  const ReportLogSection({
    super.key,
    required this.entries,
    this.onOpen,
    this.pageSize = 15,
  });

  final List<ReportLogEntry> entries;

  /// Called with a report when its card is tapped.
  final void Function(ReportLogEntry entry)? onOpen;
  final int pageSize;

  @override
  State<ReportLogSection> createState() => _ReportLogSectionState();
}

class _ReportLogSectionState extends State<ReportLogSection> {
  _LogFilter _filter = _LogFilter.all;
  String _query = '';
  late int _shown = widget.pageSize;

  List<ReportLogEntry> get _matching {
    final q = _query.trim().toLowerCase();
    return widget.entries.where((e) {
      final byFilter = switch (_filter) {
        _LogFilter.all => true,
        _LogFilter.open => e.isOpen,
        _LogFilter.finished => e.isFinishedStatus,
      };
      if (!byFilter) return false;
      if (q.isEmpty) return true;
      return e.reporterName.toLowerCase().contains(q) ||
          e.category.toLowerCase().contains(q) ||
          (e.responderName ?? '').toLowerCase().contains(q) ||
          e.shortId.toLowerCase().contains(q) ||
          e.statusLabel.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final stats = ReportLogStats.from(widget.entries);
    final matching = _matching;
    final visible = matching.take(_shown).toList();

    String avg(DurationSummary d) => d.average == null
        ? '-'
        : humanDuration(Duration(seconds: d.average!.round()));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Headline numbers ────────────────────────────────────────────
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Stat('${stats.total}', 'reports', AppColors.primary),
              _Stat('${stats.finished}', 'finished', AppColors.success),
              _Stat('${stats.open}', 'still open', AppColors.warning),
              _Stat(avg(stats.timeToFinish), 'avg time to finish', AppColors.accent),
              _Stat(avg(stats.timeToFirstResponse), 'avg first response', AppColors.accent),
            ],
          ),
          const SizedBox(height: 12),

          // ── Search + filter ─────────────────────────────────────────────
          TextField(
            onChanged: (v) => setState(() {
              _query = v;
              _shown = widget.pageSize;
            }),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search by name, category, responder or report ID',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final f in _LogFilter.values)
                ChoiceChip(
                  label: Text(switch (f) {
                    _LogFilter.all => 'All (${widget.entries.length})',
                    _LogFilter.open => 'Open (${stats.open})',
                    _LogFilter.finished => 'Finished (${stats.finished})',
                  }),
                  selected: _filter == f,
                  onSelected: (_) => setState(() {
                    _filter = f;
                    _shown = widget.pageSize;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (matching.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  widget.entries.isEmpty
                      ? 'No reports in this period.'
                      : 'No reports match.',
                  style: AppTextStyles.bodySmall,
                ),
              ),
            )
          else ...[
            for (final e in visible) ...[
              ReportLogTile(entry: e, onTap: widget.onOpen == null ? null : () => widget.onOpen!(e)),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Showing ${visible.length} of ${matching.length}',
                    style: AppTextStyles.caption,
                  ),
                ),
                if (visible.length < matching.length)
                  TextButton(
                    onPressed: () => setState(() => _shown += widget.pageSize),
                    child: Text('Show ${matching.length - visible.length < widget.pageSize ? matching.length - visible.length : widget.pageSize} more'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, this.color);
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: AppTextStyles.caption),
          ],
        ),
      );
}

/// One report.
class ReportLogTile extends StatelessWidget {
  const ReportLogTile({super.key, required this.entry, this.onTap});

  final ReportLogEntry entry;
  final VoidCallback? onTap;

  Color get _outcomeColor {
    if (entry.isFlagged) return AppColors.textSecondary;
    if (entry.isFinishedStatus) return AppColors.success;
    return entry.overdue ? AppColors.error : AppColors.warning;
  }

  IconData get _outcomeIcon {
    if (entry.isFlagged) return Icons.flag_rounded;
    if (entry.isFinishedStatus) return Icons.check_circle_rounded;
    return Icons.hourglass_top_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final sev = severityColor(entry.severity);
    final firstResponse = entry.timeToFirstResponse;

    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: sev, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ),
                  _Pill(entry.severityWord, sev),
                  const SizedBox(width: 6),
                  _Pill(entry.statusLabel, AppColors.primary),
                ],
              ),
              const SizedBox(height: 8),
              _Line(
                Icons.person_rounded,
                'Reported by',
                entry.reporterName,
                trailing: entry.reporterIsResident ? null : 'Walk-in',
              ),
              _Line(Icons.event_rounded, 'Reported', formatManilaFriendly(entry.reportedAt)),
              _Line(
                Icons.directions_run_rounded,
                'Responder',
                entry.responderName ?? 'Nobody yet',
                muted: entry.responderName == null,
              ),
              if (firstResponse != null)
                _Line(Icons.bolt_rounded, 'First response', 'after ${humanDuration(firstResponse)}'),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: _outcomeColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  children: [
                    Icon(_outcomeIcon, size: 18, color: _outcomeColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.outcome,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: _outcomeColor,
                            ),
                          ),
                          if (entry.isFinished)
                            Text('Finished ${formatManilaFriendly(entry.finishedAt)}',
                                style: AppTextStyles.caption),
                        ],
                      ),
                    ),
                    Text('#${entry.shortId}',
                        style: AppTextStyles.caption.copyWith(fontFamily: 'monospace')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: color)),
      );
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.label, this.value, {this.trailing, this.muted = false});

  final IconData icon;
  final String label;
  final String value;
  final String? trailing;
  final bool muted;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            SizedBox(
              width: 92,
              child: Text(label, style: AppTextStyles.caption),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: muted ? FontWeight.w500 : FontWeight.w700,
                  color: muted ? AppColors.textSecondary : AppColors.textPrimary,
                ),
              ),
            ),
            if (trailing != null)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(trailing!,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      );
}
