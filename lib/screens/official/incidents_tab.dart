import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../providers/incident_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/audit_service.dart';
import '../../config/app_config.dart';
import '../../models/incident_model.dart';
import '../../utils/constants.dart';
import '../../utils/permissions.dart';
import '../../utils/date_range.dart';
import '../../l10n/app_strings.dart';
import '../../utils/helpers.dart';
import '../../widgets/widgets.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/app_text.dart';

class IncidentsTab extends StatefulWidget {
  final VoidCallback onRefresh;

  const IncidentsTab({super.key, required this.onRefresh});

  @override
  State<IncidentsTab> createState() => _IncidentsTabState();
}

class _IncidentsTabState extends State<IncidentsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedCategory;
  String _searchQuery = '';
  ReportRange _range = ReportRange.allTime;
  final _searchController = TextEditingController();

  bool _isSearchExpanded = false;
  final _searchFocus = FocusNode();

  // Bulk selection state
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  bool _isBulkLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _enterSelectionMode(String firstId) {
    HapticFeedback.mediumImpact();
    setState(() {
      _selectionMode = true;
      _selectedIds.add(firstId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll(List<IncidentModel> incidents) {
    setState(() {
      if (_selectedIds.length == incidents.length) {
        _selectedIds.clear();
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.addAll(incidents.map((i) => i.id));
      }
    });
  }

  List<IncidentModel> _applyFilters(List<IncidentModel> incidents) {
    // A Tanod only ever sees cases assigned to them. Applied before the user's
    // own filters so no combination of chips can reveal someone else's case.
    incidents = visibleIncidents(context.read<AuthProvider>().user, incidents);

    // Same ReportRange the analytics export uses, so the two screens can never
    // disagree about what "last 30 days" covers.
    incidents =
        incidents.where((i) => _range.includes(i.createdAt)).toList();

    return incidents.where((i) {
      if (_selectedCategory != null && i.category != _selectedCategory) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesDesc = i.description.toLowerCase().contains(q);
        final matchesCat = i.category.toLowerCase().contains(q);
        final matchesReporter = (i.reporterName ?? '').toLowerCase().contains(q);
        final matchesAddress = (i.address ?? '').toLowerCase().contains(q);
        if (!matchesDesc && !matchesCat && !matchesReporter && !matchesAddress) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  String? get _bulkBlocked => capabilityBlockedReason(
      context.read<AuthProvider>().user, Capability.bulkAction);

  Future<void> _bulkUpdateStatus(String newStatus) async {
    if (_selectedIds.isEmpty) return;
    final ids = List<String>.from(_selectedIds);
    final label = newStatus == 'resolved' ? 'Resolved' : 'Closed';

    final confirm = await showFrostedConfirm(
      context,
      title: context.s.bulkAction(label),
      message: 'Mark ${ids.length} report${ids.length == 1 ? '' : 's'} as $label?',
      confirmLabel: label,
      icon: newStatus == 'resolved'
          ? Icons.check_circle_outline_rounded
          : Icons.lock_outline_rounded,
    );
    if (confirm != true || !mounted) return;

    setState(() => _isBulkLoading = true);
    final provider = context.read<IncidentProvider>();
    final official = context.read<AuthProvider>().user!;
    int success = 0;

    // A few at a time rather than one after another — see runBulk. Twenty
    // reports used to mean twenty sequential status writes plus twenty audit
    // writes, which read on screen as a frozen app.
    final results = await runBulk(
      ids,
      (id) => provider.updateStatus(id, newStatus, officialId: official.id),
    );
    success = results.where((ok) => ok).length;

    try {
      await AuditService().logAction(
        userId: official.id,
        action: 'bulk_status_update',
        details:
            'Bulk $label: $success/${ids.length} reports updated to $newStatus',
      );
    } catch (e) {
      // The reports were updated; only the audit entry failed. Worth a log —
      // a missing audit trail is the sort of gap that matters later and is
      // impossible to reconstruct.
      debugPrint('IncidentsTab: bulk audit log failed — $e');
    }

    if (mounted) {
      setState(() => _isBulkLoading = false);
      _exitSelectionMode();
      widget.onRefresh();
      showSuccessSnackbar(
        context,
        '$success report${success == 1 ? '' : 's'} marked as $label',
      );
    }
  }

  Future<void> _bulkDelete() async {
    if (_selectedIds.isEmpty) return;
    final ids = List<String>.from(_selectedIds);

    final confirm = await showFrostedConfirm(
      context,
      title: context.s.bulkDelete,
      message:
          'Permanently delete ${ids.length} report${ids.length == 1 ? '' : 's'}? This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (confirm != true || !mounted) return;

    setState(() => _isBulkLoading = true);
    final provider = context.read<IncidentProvider>();
    int success = 0;

    final results = await runBulk(ids, provider.deleteIncident);
    success = results.where((ok) => ok).length;

    if (mounted) {
      setState(() => _isBulkLoading = false);
      _exitSelectionMode();
      widget.onRefresh();
      showSuccessSnackbar(
        context,
        '$success report${success == 1 ? '' : 's'} deleted',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IncidentProvider>();
    final all = _applyFilters(provider.incidents);
    final pending =
        _applyFilters(provider.incidents.where((i) => i.isPending).toList());
    final active =
        _applyFilters(provider.incidents.where((i) => i.isInProgress).toList());
    final resolved =
        _applyFilters(provider.incidents.where((i) => i.isResolved).toList());

    // Determine which list is currently visible for Select All
    final currentList = [all, pending, active, resolved][_tabController.index];

    return SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              // Header
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Selection mode header OR normal header
                    if (_selectionMode)
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: _exitSelectionMode,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppText(
                              '${_selectedIds.length} selected',
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _selectAll(currentList),
                            child: Text(
                              _selectedIds.length == currentList.length
                                  ? 'Deselect All'
                                  : 'Select All',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      )
                    else ...[
                      // Title row + animated search icon
                      Row(
                        children: [
                          // Title fades out when search is open
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: _isSearchExpanded
                                ? const SizedBox.shrink()
                                : Column(
                                    key: const ValueKey('title'),
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      AppText(context.s.incidentManagement,
                                          style: AppTextStyles.heading2),
                                      const SizedBox(height: 2),
                                      AppText(
                                        '${provider.incidents.length} total · long-press to select',
                                        style: AppTextStyles.bodySmall,
                                      ),
                                    ],
                                  ),
                          ),
                          const Spacer(),
                          // Search icon ↔ close icon
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            transitionBuilder: (child, anim) =>
                                ScaleTransition(scale: anim, child: child),
                            child: _isSearchExpanded
                                ? IconButton(
                                    key: const ValueKey('close'),
                                    icon: const Icon(Icons.close_rounded),
                                    color: AppColors.textSecondary,
                                    onPressed: () {
                                      _searchController.clear();
                                      _searchFocus.unfocus();
                                      setState(() {
                                        _searchQuery = '';
                                        _isSearchExpanded = false;
                                      });
                                    },
                                  )
                                : IconButton(
                                    key: const ValueKey('search'),
                                    icon: const Icon(Icons.search_rounded),
                                    color: AppColors.textSecondary,
                                    onPressed: () {
                                      setState(
                                          () => _isSearchExpanded = true);
                                      _searchFocus.requestFocus();
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),

                    if (!_selectionMode) ...[
                      // Expanding search bar
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                        height: _isSearchExpanded ? 46 : 0,
                        child: ClipRect(
                          child: OverflowBox(
                            maxHeight: 46,
                            alignment: Alignment.topCenter,
                            child: TextField(
                              controller: _searchController,
                              focusNode: _searchFocus,
                              onChanged: (v) =>
                                  setState(() => _searchQuery = v),
                              decoration: InputDecoration(
                                hintText: context.s.searchIncidentsHint,
                                hintStyle: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary),
                                prefixIcon: const Icon(Icons.search_rounded,
                                    size: 20, color: AppColors.textSecondary),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.close_rounded,
                                            size: 18),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() => _searchQuery = '');
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: AppColors.background,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                      color: AppColors.divider),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                      color: AppColors.divider),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                      color: AppColors.primary, width: 1.5),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_isSearchExpanded) const SizedBox(height: 8),

                      // Category filter chips with animated fill
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _rangeChip(),
                            const SizedBox(width: 6),
                            Container(
                              width: 1,
                              height: 20,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              color: AppColors.divider,
                            ),
                            const SizedBox(width: 2),
                            _categoryChip(context.s.all, _selectedCategory == null,
                                () => setState(
                                    () => _selectedCategory = null)),
                            // Label is translated; `cat` stays the canonical
                            // value the filter actually compares against.
                            ...AppConfig.incidentCategories.map(
                              (cat) => _categoryChip(
                                categoryLabel(context.s, cat),
                                _selectedCategory == cat,
                                () => setState(() => _selectedCategory =
                                    _selectedCategory == cat ? null : cat),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    TabBar(
                      controller: _tabController,
                      labelColor: AppColors.primary,
                      unselectedLabelColor: AppColors.textSecondary,
                      indicatorColor: AppColors.primary,
                      labelStyle: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                      unselectedLabelStyle: const TextStyle(fontSize: 13),
                      onTap: (_) => setState(() {}),
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

              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildList(all),
                    _buildList(pending),
                    _buildList(active),
                    _buildList(resolved),
                  ],
                ),
              ),

              // Spacer for bulk action bar
              if (_selectionMode) const SizedBox(height: 80),
            ],
          ),

          // Bulk action bottom bar
          if (_selectionMode)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBulkActionBar(),
            ),
        ],
      ),
    );
  }

  Widget _buildBulkActionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: _isBulkLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(),
              ),
            )
          : Row(
              children: [
                Expanded(
                  child: _bulkButton(
                    icon: Icons.check_circle_outline_rounded,
                    label: context.s.resolve,
                    color: AppColors.success,
                    onTap: () => _bulkUpdateStatus('resolved'),
                    blockedReason: _bulkBlocked,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _bulkButton(
                    icon: Icons.lock_outline_rounded,
                    label: context.s.close,
                    color: AppColors.textSecondary,
                    onTap: () => _bulkUpdateStatus('closed'),
                    blockedReason: _bulkBlocked,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _bulkButton(
                    icon: Icons.delete_outline_rounded,
                    label: context.s.delete,
                    color: AppColors.error,
                    onTap: _bulkDelete,
                    // Deleting is superadmin-only at the database, so this is
                    // checked separately from the other two.
                    blockedReason: capabilityBlockedReason(
                        context.read<AuthProvider>().user,
                        Capability.deleteIncident),
                  ),
                ),
              ],
            ),
    );
  }

  /// [blockedReason] non-null greys the action and, on tap, names who can do
  /// it. Distinct from the "nothing selected" disabled state below: one is a
  /// permission, the other is a step the user has not taken yet, and conflating
  /// them would tell someone to go find the Captain when they simply need to
  /// tick a checkbox.
  Widget _bulkButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    String? blockedReason,
  }) {
    final blocked = blockedReason != null;
    if (blocked) color = AppColors.textTertiary;

    return GestureDetector(
      onTap: blocked
          ? () {
              HapticFeedback.heavyImpact();
              showErrorSnackbar(context, blockedReason);
            }
          : (_selectedIds.isEmpty ? null : onTap),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: _selectedIds.isEmpty
              ? color.withValues(alpha: 0.05)
              : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _selectedIds.isEmpty
                ? color.withValues(alpha: 0.2)
                : color.withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: _selectedIds.isEmpty
                    ? color.withValues(alpha: 0.4)
                    : color,
                size: 20),
            const SizedBox(height: 2),
            AppText(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _selectedIds.isEmpty
                    ? color.withValues(alpha: 0.4)
                    : color,
              ),
            ),
          ],
        ),
      ),
    );
  }


  /// Cycles through the windows rather than adding four more chips: this row
  /// already scrolls horizontally through every incident category, and four
  /// more would push the categories off-screen on a phone.
  Widget _rangeChip() {
    final t = context.s;
    final active = _range != ReportRange.allTime;

    return GestureDetector(
      onTap: () {
        const values = ReportRange.values;
        final next = values[(values.indexOf(_range) + 1) % values.length];
        HapticFeedback.selectionClick();
        setState(() => _range = next);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_rounded,
                size: 12,
                color: active ? Colors.white : AppColors.textSecondary),
            const SizedBox(width: 5),
            Text(
              _range.labelFor(t),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryChip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.divider,
              width: 1.2,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : [],
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
            child: AppText(label),
          ),
        ),
      ),
    );
  }

  Widget _buildList(List<IncidentModel> incidents) {
    if (incidents.isEmpty) {
      return EmptyState(
        icon: Icons.inbox_rounded,
        title: context.s.noIncidents,
        subtitle: context.s.noIncidentsMatchFilters,
      );
    }

    return RefreshIndicator(
      onRefresh: () async => widget.onRefresh(),
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= kWideBreakpoint;

        Widget buildRow(BuildContext context, int index) {
          final incident = incidents[index];
          final isSelected = _selectedIds.contains(incident.id);

          return _SwipeableIncidentRow(
            key: ValueKey(incident.id),
            incident: incident,
            selectionMode: _selectionMode,
            isSelected: isSelected,
            animIndex: index,
            onTap: () {
              if (_selectionMode) {
                _toggleSelection(incident.id);
              } else {
                Navigator.pushNamed(
                  context,
                  '/incident-manage',
                  arguments: incident.id,
                ).then((_) => widget.onRefresh());
              }
            },
            onLongPress: () {
              if (!_selectionMode) _enterSelectionMode(incident.id);
            },
            onStatusUpdate: (status) async {
              final provider = context.read<IncidentProvider>();
              final official = context.read<AuthProvider>().user!;
              final ok = await provider.updateStatus(
                incident.id,
                status,
                officialId: official.id,
              );
              if (ok && mounted) {
                widget.onRefresh();
                final label =
                    status == 'resolved' ? 'Resolved' : 'Dispatched';
                showSuccessSnackbar(
                  context,
                  '${incident.category} marked as $label',
                );
              }
              return ok;
            },
          );
        }

        final padding =
            EdgeInsets.only(top: 8, bottom: _selectionMode ? 8 : 20);

        if (!wide) {
          return ListView.builder(
            padding: padding,
            itemCount: incidents.length,
            itemBuilder: buildRow,
          );
        }

        // Two cards per row on a desktop. The list stays lazy: each builder
        // item is a PAIR, so only the visible pairs are ever built. (Pairs
        // rather than two independent columns because this is scrollable up
        // to 100 rows, and one scroll position cannot drive two lists.)
        final pairs = (incidents.length + 1) ~/ 2;
        return ListView.builder(
          padding: padding,
          itemCount: pairs,
          itemBuilder: (context, i) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: buildRow(context, i * 2)),
              Expanded(
                child: i * 2 + 1 < incidents.length
                    ? buildRow(context, i * 2 + 1)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ── Swipeable incident row ───────────────────────────────────────────────────
class _SwipeableIncidentRow extends StatefulWidget {
  final IncidentModel incident;
  final bool selectionMode;
  final bool isSelected;
  final int animIndex;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Future<bool> Function(String status) onStatusUpdate;

  const _SwipeableIncidentRow({
    super.key,
    required this.incident,
    required this.selectionMode,
    required this.isSelected,
    required this.animIndex,
    required this.onTap,
    required this.onLongPress,
    required this.onStatusUpdate,
  });

  @override
  State<_SwipeableIncidentRow> createState() => _SwipeableIncidentRowState();
}

class _SwipeableIncidentRowState extends State<_SwipeableIncidentRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _snapCtrl;
  double _offset = 0;
  double _animFrom = 0;
  double _animTo = 0;
  bool _triggered = false;

  static const _threshold = 100.0;
  static const _maxDrag = 130.0;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    )..addListener(_onSnapTick);
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  void _onSnapTick() {
    final t =
        Curves.easeOutBack.transform(_snapCtrl.value.clamp(0.0, 1.0));
    if (mounted) setState(() => _offset = _animFrom + (_animTo - _animFrom) * t);
  }

  void _snapTo(double target) {
    _snapCtrl.stop();
    _animFrom = _offset;
    _animTo = target;
    _snapCtrl.value = 0;
    _snapCtrl.animateTo(1.0);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (widget.selectionMode || _triggered) return;
    _snapCtrl.stop();
    setState(() {
      _offset = (_offset + d.delta.dx).clamp(-_maxDrag, _maxDrag);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    if (widget.selectionMode || _triggered) return;
    if (_offset.abs() >= _threshold) {
      final goRight = _offset > 0;
      _triggered = true;
      HapticFeedback.mediumImpact();
      _performAction(
        goRight ? 'resolved' : 'in_progress',
        goRight ? _maxDrag : -_maxDrag,
      );
    } else {
      _snapTo(0);
    }
  }

  Future<void> _performAction(String action, double peekTarget) async {
    _snapTo(peekTarget);
    await Future.delayed(const Duration(milliseconds: 380));
    if (!mounted) return;
    await widget.onStatusUpdate(action);
    if (!mounted) return;
    _snapTo(0);
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) setState(() => _triggered = false);
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_offset.abs() / _maxDrag).clamp(0.0, 1.0);
    final isRight = _offset > 0;
    final isLeft = _offset < 0;

    final cardContent = Stack(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? AppColors.primary.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: IncidentCard(
            incident: widget.incident,
            showReporter: true,
            // Must be the row's handler, not null. The card has its own tap detector,
            // and with two nested detectors only the INNER one ever fires — so a null
            // here swallowed every tap and the row's own onTap below was dead code.
            onTap: widget.onTap,
          ),
        ),
        if (widget.selectionMode)
          Positioned(
            top: 12,
            right: 20,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: widget.isSelected
                  ? Container(
                      key: const ValueKey('checked'),
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: Colors.white, size: 16),
                    )
                  : Container(
                      key: const ValueKey('unchecked'),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: AppColors.divider, width: 2),
                      ),
                    ),
            ),
          ),
      ],
    );

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Stack(
        children: [
          // Resolve background (swipe right)
          if (isRight)
            Positioned.fill(
              child: Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 20),
                child: Opacity(
                  opacity: progress,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: Colors.white, size: 26),
                      SizedBox(height: 3),
                      Text(
                        'Resolve',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Dispatch background (swipe left)
          if (isLeft)
            Positioned.fill(
              child: Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.warning,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: Opacity(
                  opacity: progress,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt_rounded,
                          color: Colors.white, size: 26),
                      SizedBox(height: 3),
                      Text(
                        'Dispatch',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Card offset by drag
          Transform.translate(
            offset: Offset(_offset, 0),
            child: cardContent,
          ),
        ],
      ),
    )
        .animate(
          delay: Duration(milliseconds: (35 * widget.animIndex).clamp(0, 210)),
        )
        .fadeIn(duration: const Duration(milliseconds: 280))
        .slideY(
          begin: 0.06,
          end: 0,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
  }
}
