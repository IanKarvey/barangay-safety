import 'package:flutter/material.dart';
import '../../models/audit_log_model.dart';
import '../../services/audit_service.dart';
import '../../utils/constants.dart';
import '../../l10n/app_strings.dart';
import '../../utils/helpers.dart';
import '../../widgets/widgets.dart';
import '../../widgets/app_text.dart';

class AuditLogScreen extends StatefulWidget {
  /// null = all logs; set to load incident-scoped or user-scoped logs
  final String? incidentId;
  final String? userId;
  final String title;

  const AuditLogScreen({
    super.key,
    this.incidentId,
    this.userId,
    this.title = 'Activity Log',
  });

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  final _auditService = AuditService();
  List<AuditLogModel> _allLogs = [];
  List<AuditLogModel> _filtered = [];
  bool _isLoading = true;
  String _selectedFilter = 'all';

  static const _filters = [
    ('all', 'All'),
    ('status_update', 'Status'),
    ('severity_change', 'Severity'),
    ('assign', 'Assignment'),
    ('verify_user', 'Verification'),
    ('lock_user', 'Account'),
    ('delete', 'Delete'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      List<AuditLogModel> logs;
      if (widget.incidentId != null) {
        logs = await _auditService.getIncidentLogs(widget.incidentId!);
      } else if (widget.userId != null) {
        logs = await _auditService.getUserLogs(widget.userId!);
      } else {
        logs = await _auditService.getAllLogs(limit: 200);
      }
      if (mounted) {
        setState(() {
          _allLogs = logs;
          _applyFilter();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilter() {
    if (_selectedFilter == 'all') {
      _filtered = List.from(_allLogs);
    } else if (_selectedFilter == 'lock_user') {
      _filtered = _allLogs
          .where((l) => l.action == 'lock_user' || l.action == 'unlock_user')
          .toList();
    } else {
      _filtered = _allLogs.where((l) => l.action == _selectedFilter).toList();
    }
  }

  void _setFilter(String filter) {
    setState(() {
      _selectedFilter = filter;
      _applyFilter();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: AppText(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
            tooltip: context.s.refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Filter chips ───────────────────────────────────────────────
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _filters.map((f) {
                  final isSelected = _selectedFilter == f.$1;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => _setFilter(f.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.background,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.divider,
                          ),
                        ),
                        child: Text(
                          f.$2,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // ── Log count ──────────────────────────────────────────────────
          if (!_isLoading)
            Container(
              color: AppColors.surface,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Text(
                    '${_filtered.length} ${_filtered.length == 1 ? 'entry' : 'entries'}',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),

          const Divider(height: 1),

          // ── Log list ───────────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const AuditLogShimmer()
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.history_rounded,
                                size: 48, color: AppColors.textTertiary),
                            const SizedBox(height: 12),
                            AppText(
                              'No activity found',
                              style: AppTextStyles.body
                                  .copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        // A log entry is a sentence. Across a 1300px window it
                        // becomes one long line with the time at the far edge,
                        // so on a desktop the list sits in a readable column.
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 860),
                            child: ListView.separated(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 16, 16, 32),
                              itemCount: _filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) =>
                                  _LogEntry(log: _filtered[index]),
                            ),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _LogEntry extends StatelessWidget {
  final AuditLogModel log;
  const _LogEntry({required this.log});

  static _ActionMeta _meta(AppStrings t, String action) {
    switch (action) {
      case 'status_update':
        return _ActionMeta(
          icon: Icons.autorenew_rounded,
          color: AppColors.primary,
          label: t.auditStatusUpdate,
        );
      case 'severity_change':
        return _ActionMeta(
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFFF9500),
          label: t.auditSeverityChanged,
        );
      case 'assign':
        return _ActionMeta(
          icon: Icons.person_add_rounded,
          color: const Color(0xFF5856D6),
          label: t.auditAssignment,
        );
      case 'verify_user':
        return _ActionMeta(
          icon: Icons.verified_rounded,
          color: AppColors.success,
          label: t.auditUserVerified,
        );
      case 'lock_user':
        return _ActionMeta(
          icon: Icons.lock_rounded,
          color: AppColors.error,
          label: t.auditAccountLocked,
        );
      case 'unlock_user':
        return _ActionMeta(
          icon: Icons.lock_open_rounded,
          color: AppColors.success,
          label: t.auditAccountUnlocked,
        );
      case 'delete':
        return _ActionMeta(
          icon: Icons.delete_rounded,
          color: AppColors.error,
          label: t.auditReportDeleted,
        );
      case 'flag':
        return _ActionMeta(
          icon: Icons.flag_rounded,
          color: const Color(0xFFFF9500),
          label: t.auditReportFlagged,
        );
      default:
        return _ActionMeta(
          icon: Icons.info_rounded,
          color: AppColors.textSecondary,
          label: action.replaceAll('_', ' '),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _meta(context.s, log.action);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Action icon circle
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: m.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(m.icon, color: m.color, size: 20),
          ),
          const SizedBox(width: 12),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name + timestamp row
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        log.userName ?? 'Unknown Official',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeAgo(log.createdAt),
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
                const SizedBox(height: 3),

                // Action label
                AppText(
                  m.label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: m.color,
                  ),
                ),

                // Details
                if (log.details != null && log.details!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  AppText(
                    log.details!,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],

                // Incident ID badge
                if (log.incidentId != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: AppText(
                      'Incident #${log.incidentId!.substring(0, 8).toUpperCase()}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],

                // Full timestamp
                const SizedBox(height: 6),
                Text(
                  formatDateTime(log.createdAt),
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionMeta {
  final IconData icon;
  final Color color;
  final String label;
  const _ActionMeta(
      {required this.icon, required this.color, required this.label});
}
