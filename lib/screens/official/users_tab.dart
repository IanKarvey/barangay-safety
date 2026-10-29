import 'dart:async';
import '../../utils/live_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/user_management_service.dart';
import '../../services/audit_service.dart';
import '../../models/user_model.dart';
import '../../utils/constants.dart';
import '../../utils/permissions.dart';
import '../../services/id_verification_service.dart';
import '../../services/notification_service.dart';
import '../../l10n/app_strings.dart';
import '../../utils/helpers.dart';
import '../../widgets/widgets.dart';
import '../../widgets/app_text.dart';
import '../../widgets/responsive_layout.dart';

class UsersTab extends StatefulWidget {
  const UsersTab({super.key});

  @override
  State<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab>
    with SingleTickerProviderStateMixin, LiveRefreshMixin {
  final _userService = UserManagementService();
  final _auditService = AuditService();
  late TabController _tabController;

  /// Realtime signal that a profile changed. See [subscribeToProfiles] — this
  /// is the fast path; [LiveRefreshMixin] is the floor under it.
  StreamSubscription? _profileSub;
  Timer? _profileDebounce;

  List<UserModel> _allUsers = [];

  /// Set when the fetch failed, so the list can say so rather than show an
  /// empty roster that looks like a barangay with no registered residents.
  String? _loadError;
  List<UserModel> _pendingVerifications = [];
  bool _isLoading = true;

  // Bulk selection state
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  bool _isBulkLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUsers();
    _watchProfiles();
    // Refreshes on app resume and on a slow tick, so the roster is current
    // even if realtime is not delivering. Officials were previously having to
    // log out and back in to see a newly registered or newly verified
    // resident.
    startLiveRefresh();
  }

  /// Realtime on `profiles`, debounced.
  ///
  /// Supabase emits one event per changed row, so verifying five residents in
  /// a row would otherwise fire five full reloads.
  void _watchProfiles() {
    final barangayId = context.read<AuthProvider>().user?.barangayId;
    if (barangayId == null) return;
    _profileSub?.cancel();
    _profileSub =
        _userService.subscribeToProfiles(barangayId).listen((_) {
      _profileDebounce?.cancel();
      _profileDebounce = Timer(const Duration(milliseconds: 400), () {
        if (mounted) _loadUsers(silent: true);
      });
    }, onError: (e) {
      // Logged, not swallowed — but not recovered from here either: the
      // LiveRefreshMixin tick covers a dead stream.
      debugPrint('UsersTab: profile stream error: $e');
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

  /// [silent] skips the spinner — a background refresh must not blank a list
  /// the official is reading, or throw away their scroll position.
  Future<void> _loadUsers({bool silent = false}) async {
    final user = context.read<AuthProvider>().user;
    if (user?.barangayId == null) return;

    if (!silent) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      // In parallel — these are independent queries and were awaited one after
      // the other, so the tab took the sum of both round trips to appear.
      final results = await Future.wait([
        _userService.getUsersByBarangay(user!.barangayId!),
        _userService.getPendingVerifications(user.barangayId!),
      ]);
      if (!mounted) return;
      _allUsers = results[0];
      _pendingVerifications = results[1];
    } catch (e) {
      // Was swallowed silently, which rendered a failed fetch as "0 registered"
      // — a barangay official could conclude nobody had signed up.
      _loadError = 'Could not load residents. Check your connection and retry.';
      debugPrint('UsersTab: _loadUsers failed — $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

  void _selectAll(List<UserModel> users) {
    setState(() {
      if (_selectedIds.length == users.length) {
        _selectedIds.clear();
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.addAll(users.map((u) => u.id));
      }
    });
  }

  Future<void> _bulkToggleLock(bool lock) async {
    if (_selectedIds.isEmpty) return;
    final ids = List<String>.from(_selectedIds);
    final label = lock ? 'Lock' : 'Unlock';

    final confirm = await showFrostedConfirm(
      context,
      title: context.s.bulkAction(label),
      message:
          '$label ${ids.length} user account${ids.length == 1 ? '' : 's'}?',
      confirmLabel: label,
      destructive: lock,
      icon: lock ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
    );
    if (confirm != true || !mounted) return;

    setState(() => _isBulkLoading = true);
    final official = context.read<AuthProvider>().user!;
    int success = 0;

    // Bounded concurrency — see runBulk. The audit write stays paired with its
    // lock inside the same unit of work, so a locked account is never left
    // without a record of who locked it.
    final results = await runBulk(ids, (id) async {
      await _userService.toggleLockUser(id, lock);
      await _auditService.logAction(
        userId: official.id,
        action: lock ? 'lock_user' : 'unlock_user',
        details: 'Bulk ${lock ? 'locked' : 'unlocked'} user ID: $id',
      );
      return true;
    });
    success = results.where((ok) => ok).length;

    if (mounted) {
      setState(() => _isBulkLoading = false);
      _exitSelectionMode();
      await _loadUsers();
      showSuccessSnackbar(
        context,
        '$success account${success == 1 ? '' : 's'} ${lock ? 'locked' : 'unlocked'}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentList =
        _tabController.index == 0 ? _allUsers : _pendingVerifications;

    return SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AppText(context.s.userManagement,
                                    style: AppTextStyles.heading2),
                                const SizedBox(height: 4),
                                AppText(
                                  '${_allUsers.length} registered · long-press to select',
                                  style: AppTextStyles.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          // Hidden rather than disabled: a Tanod looking at
                          // the roster has no reason to be shown a control
                          // for appointing colleagues.
                          if (_canManagePositions)
                            IconButton(
                              icon: const Icon(Icons.person_add_alt_1_rounded,
                                  color: AppColors.primary),
                              tooltip: context.s.addStaff,
                              onPressed: _showAddStaff,
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    TabBar(
                      controller: _tabController,
                      labelColor: AppColors.primary,
                      unselectedLabelColor: AppColors.textSecondary,
                      indicatorColor: AppColors.primary,
                      onTap: (_) => setState(() {}),
                      tabs: [
                        Tab(text: 'All Users (${_allUsers.length})'),
                        Tab(
                            text:
                                'Pending (${_pendingVerifications.length})'),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const UserListShimmer()
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildUserList(_allUsers),
                          _buildUserList(_pendingVerifications,
                              isPending: true),
                        ],
                      ),
              ),
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
                    icon: Icons.lock_open_rounded,
                    label: context.s.unlock,
                    color: AppColors.success,
                    onTap: () => _bulkToggleLock(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _bulkButton(
                    icon: Icons.lock_rounded,
                    label: context.s.lock,
                    color: AppColors.error,
                    onTap: () => _bulkToggleLock(true),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _bulkButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final enabled = _selectedIds.isNotEmpty;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: enabled
              ? color.withValues(alpha: 0.1)
              : color.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: enabled
                ? color.withValues(alpha: 0.4)
                : color.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: enabled ? color : color.withValues(alpha: 0.35),
                size: 20),
            const SizedBox(width: 8),
            AppText(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: enabled ? color : color.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserList(List<UserModel> users, {bool isPending = false}) {
    // A failed fetch and a genuinely empty barangay are the same empty list,
    // and only one of them means "go and check your connection".
    if (_loadError != null) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load residents',
        subtitle: _loadError,
        action: OutlinedButton.icon(
          onPressed: _loadUsers,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(context.s.retry),
        ),
      );
    }
    if (users.isEmpty) {
      return EmptyState(
        icon: isPending ? Icons.hourglass_empty : Icons.people_outline,
        title: isPending ? 'No Pending Verifications' : 'No Users',
        subtitle: isPending
            ? 'All pending accounts have been reviewed.'
            : 'No users registered in your barangay yet.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadUsers,
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= kWideBreakpoint;

        Widget buildRow(BuildContext context, int index) {
          final user = users[index];
          final isSelected = _selectedIds.contains(user.id);

          return GestureDetector(
            onLongPress: () {
              if (!_selectionMode) _enterSelectionMode(user.id);
            },
            onTap: () {
              if (_selectionMode) {
                _toggleSelection(user.id);
              }
              // Normal tap does nothing extra — actions are in the card's popup menu
            },
            child: Stack(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.06)
                      : Colors.transparent,
                  child: _userCard(user, isPending),
                ),
                if (_selectionMode)
                  Positioned(
                    top: 16,
                    right: 16,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: isSelected
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
                                border: Border.all(
                                    color: AppColors.divider, width: 2),
                              ),
                            ),
                    ),
                  ),
              ],
            ),
          );
        }

        final padding =
            EdgeInsets.only(top: 8, bottom: _selectionMode ? 8 : 20);

        if (!wide) {
          return ListView.builder(
            padding: padding,
            itemCount: users.length,
            itemBuilder: buildRow,
          );
        }

        // Two cards per row on a desktop; each builder item is a pair so the
        // list stays lazy.
        final pairs = (users.length + 1) ~/ 2;
        return ListView.builder(
          padding: padding,
          itemCount: pairs,
          itemBuilder: (context, i) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: buildRow(context, i * 2)),
              Expanded(
                child: i * 2 + 1 < users.length
                    ? buildRow(context, i * 2 + 1)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _userCard(UserModel user, bool isPending) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: user.isLocked
              ? AppColors.error.withValues(alpha: 0.1)
              : AppColors.primary.withValues(alpha: 0.1),
          child: AppText(
            user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?',
            style: TextStyle(
              color: user.isLocked ? AppColors.error : AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: AppText(
                user.fullName,
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (!_selectionMode && user.falseReportStrikes > 0)
              _StrikeBadge(strikes: user.falseReportStrikes),
            if (!_selectionMode && user.falseReportStrikes > 0)
              const SizedBox(width: 6),
            if (!_selectionMode)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _badgeColor(user).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (user.hasPosition) ...[
                      Icon(positionIcon(user.position),
                          size: 11, color: _badgeColor(user)),
                      const SizedBox(width: 3),
                    ],
                    AppText(
                      userDisplayTitle(user),
                      style: TextStyle(
                        fontSize: 10,
                        color: _badgeColor(user),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(user.email, style: AppTextStyles.caption),
            AppText(user.phone, style: AppTextStyles.caption),
            if (user.isLocked)
              Text(
                'LOCKED',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        trailing: _selectionMode
            ? null
            : isPending
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // §8 - the ID the resident uploaded. An official asked
                      // to approve an identity they cannot look at is being
                      // asked to rubber-stamp it.
                      _IdBadgeButton(
                        user: user,
                        onOpen: () => _viewSubmittedId(user),
                      ),
                      // Disabled rather than hidden: a pending account still
                      // needs to be visibly awaiting someone's approval, even
                      // when this official is not that someone.
                      IconButton(
                        icon: Icon(Icons.check_circle,
                            color: _canVerify
                                ? AppColors.success
                                : AppColors.textTertiary),
                        onPressed: _canVerify
                            ? () => _verifyUser(user)
                            : () => _denied(Capability.verifyUser),
                        tooltip: _canVerify
                            ? context.s.verify
                            : capabilityBlockedReason(
                                _me, Capability.verifyUser),
                      ),
                      // Not a ban icon. The X asks for a better photo; a
                      // slashed circle reads as "you are barred", which is
                      // exactly the confusion this button used to cause.
                      IconButton(
                        icon: Icon(Icons.close_rounded,
                            color: _canVerify
                                ? AppColors.error
                                : AppColors.textTertiary),
                        onPressed: _canVerify
                            ? () => _rejectId(user)
                            : () => _denied(Capability.verifyUser),
                        tooltip: _canVerify
                            ? context.s.reject
                            : capabilityBlockedReason(_me, Capability.verifyUser),
                      ),
                    ],
                  )
                : PopupMenuButton<String>(
                    onSelected: (action) => _handleUserAction(action, user),
                    itemBuilder: (ctx) => [
                      if (!user.isVerified && _canVerify)
                        PopupMenuItem(
                            value: 'verify', child: AppText(ctx.s.verify)),
                      if (_canEditDetails)
                        PopupMenuItem(
                            value: 'edit', child: AppText(ctx.s.editDetails)),
                      // Hidden, not greyed: the reason is the target's rank
                      // relative to yours, which a disabled control cannot
                      // explain without naming someone else's seniority.
                      if (user.isOfficial && canSetPositionOf(_me, user))
                        PopupMenuItem(
                            value: 'position',
                            child: AppText(ctx.s.assignPosition)),
                      if (canLockAccount(_me, user))
                        PopupMenuItem(
                        value: user.isLocked ? 'unlock' : 'lock',
                        child: Text(
                            user.isLocked ? 'Unlock Account' : 'Lock Account'),
                      ),
                    ],
                  ),
        isThreeLine: true,
      ),
    );
  }

  /// Badge tint — position takes precedence over permission tier, so a
  /// Secretary reads as a Secretary rather than a generic "admin".
  Color _badgeColor(UserModel user) {
    switch (user.position) {
      case UserPosition.secretary:
        return Colors.indigo;
      case UserPosition.captain:
        return Colors.purple;
      case UserPosition.tanod:
        return AppColors.primary;
      case UserPosition.staff:
        return Colors.teal;
    }
    return _roleColor(user.role);
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'superadmin':
        return Colors.purple;
      case 'admin':
        return AppColors.primary;
      case 'resident':
        return AppColors.success;
      case 'non_resident':
        return AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }

  Future<void> _verifyUser(UserModel user) async {
    try {
      final official = context.read<AuthProvider>().user!;
      await _userService.verifyUser(user.id);
      await _auditService.logAction(
        userId: official.id,
        action: 'verify_user',
        details: 'Verified user: ${user.fullName}',
      );
      if (mounted) {
        showSuccessSnackbar(context, '${user.fullName} has been verified');
        _loadUsers();
      }
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Failed to verify user');
    }
  }

  Future<void> _lockUser(UserModel user, bool lock) async {
    try {
      final official = context.read<AuthProvider>().user!;
      await _userService.toggleLockUser(user.id, lock);
      await _auditService.logAction(
        userId: official.id,
        action: lock ? 'lock_user' : 'unlock_user',
        details: '${lock ? 'Locked' : 'Unlocked'} user: ${user.fullName}',
      );
      if (mounted) {
        showSuccessSnackbar(
          context,
          '${user.fullName} has been ${lock ? 'locked' : 'unlocked'}',
        );
        _loadUsers();
      }
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Failed to update user');
    }
  }

  /// Correct a resident's name, phone or address.
  ///
  /// Shared with the superadmin roster - see [showEditUserDetailsSheet].
  Future<void> _showEditDetails(UserModel user) async {
    final saved = await showEditUserDetailsSheet(context, user);
    if (saved && mounted) _loadUsers();
  }

  /// Appoint a registered resident to a barangay hall position.
  ///
  /// Not account creation - see [UserManagementService.promoteToStaff] for why
  /// an official does not get to invent someone else's password. This lists
  /// people who already signed up and are verified.
  Future<void> _showAddStaff() async {
    final eligible = _allUsers
        .where((u) => !u.isOfficial && !u.isLocked && u.isVerified)
        .toList();

    final picked = await showModalBottomSheet<UserModel>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(ctx.s.addStaff, style: AppTextStyles.heading3),
              const SizedBox(height: 4),
              AppText(ctx.s.addStaffSubtitle, style: AppTextStyles.bodySmall),
              const SizedBox(height: 12),
              Expanded(
                child: eligible.isEmpty
                    ? EmptyState(
                        icon: Icons.person_search_rounded,
                        title: ctx.s.noEligibleAccounts,
                        subtitle: ctx.s.noEligibleAccountsHint,
                      )
                    : ListView.separated(
                        controller: scrollCtrl,
                        itemCount: eligible.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final u = eligible[i];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor:
                                  AppColors.primary.withValues(alpha: 0.12),
                              child: AppText(
                                u.fullName.isEmpty
                                    ? '?'
                                    : u.fullName.trim()[0].toUpperCase(),
                                style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                            title: AppText(u.fullName),
                            subtitle:
                                AppText(u.email, overflow: TextOverflow.ellipsis),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => Navigator.pop(ctx, u),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );

    if (picked == null || !mounted) return;

    final position = await showModalBottomSheet<String>(
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
            AppText(ctx.s.pickPosition, style: AppTextStyles.heading3),
            const SizedBox(height: 4),
            AppText(picked.fullName, style: AppTextStyles.bodySmall),
            const SizedBox(height: 10),
            ...assignablePositions(_me).map(
              (pos) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading:
                    const Icon(Icons.badge_outlined, color: AppColors.primary),
                title: AppText(UserPosition.label(pos)),
                onTap: () => Navigator.pop(ctx, pos),
              ),
            ),
          ],
        ),
      ),
    );

    if (position == null || !mounted) return;
    await _promote(picked, position);
  }

  Future<void> _promote(UserModel user, String position) async {
    final official = context.read<AuthProvider>().user;
    if (official == null) return;

    final ok = await showFrostedConfirm(
      context,
      title: context.s.promoteTitle,
      message: '${user.fullName} -> ${UserPosition.label(position)}'
          '\n\n${context.s.promoteBody}',
      confirmLabel: context.s.promoteConfirm,
      icon: Icons.person_add_alt_1_rounded,
    );
    if (ok != true || !mounted) return;

    try {
      await _userService.promoteToStaff(user.id, position);

      await NotificationService().send(
        userId: user.id,
        title: context.s.promotedNotifTitle,
        body: context.s.promotedNotifBody,
        type: 'role_granted',
      );

      // Granting authority is the most sensitive thing on this screen - it is
      // logged with both names so it can never be quietly reassigned.
      await _auditService.logAction(
        userId: official.id,
        action: 'staff_added',
        details: '${official.fullName} made ${user.fullName} '
            'a ${UserPosition.label(position)}',
      );

      if (!mounted) return;
      showSuccessSnackbar(context, context.s.promoted);
      _loadUsers();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not grant role: $e');
    }
  }

  /// §8 - the X on a pending account.
  ///
  /// Previously this locked the account, which conflated two unrelated things:
  /// "your photo was unreadable" and "you are barred from the app". A resident
  /// whose ID came out blurry was locked out with no explanation and no way
  /// back. Now it clears the submission and tells them what to fix; locking
  /// remains available in the menu for the cases that actually warrant it.
  Future<void> _rejectId(UserModel user) async {
    final official = context.read<AuthProvider>().user;
    if (official == null) return;

    final ok = await showFrostedConfirm(
      context,
      title: context.s.rejectIdTitle,
      message: context.s.rejectIdBody,
      confirmLabel: context.s.rejectIdConfirm,
      icon: Icons.refresh_rounded,
    );
    if (ok != true || !mounted) return;

    try {
      await _userService.rejectIdSubmission(user.id);

      // Told, not left guessing. A silent rejection looks identical to nobody
      // having looked at it yet.
      await NotificationService().send(
        userId: user.id,
        title: context.s.idRejectedNotifTitle,
        body: context.s.idRejectedNotifBody,
        type: 'id_rejected',
      );

      await _auditService.logAction(
        userId: official.id,
        action: 'id_rejected',
        details: 'Asked ${user.fullName} to re-upload their ID',
      );

      if (!mounted) return;
      showSuccessSnackbar(context, context.s.idRejected);
      _loadUsers();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not reject: $e');
    }
  }

  /// §8 - opens the resident's ID submission: front, back, and the selfie.
  ///
  /// All three in one place because they only mean anything together. The
  /// front says who they claim to be, the back says the document is real, and
  /// the selfie says the person holding it is the person on it. Reviewing them
  /// one at a time - or reviewing only the front, as this screen used to -
  /// invites approving on the weakest of the three.
  ///
  /// Signed URLs are fetched per photo and expire in an hour: the bucket is
  /// private because a government ID is sensitive personal information under
  /// RA 10173, and a link that never expires would quietly undo that.
  Future<void> _viewSubmittedId(UserModel user) async {
    final svc = IdVerificationService();

    // Fetched together so the reviewer does not watch three separate spinners.
    //
    // This loop used to `await` inside itself, so despite the comment the three
    // signing requests ran one after another and opening an ID review took
    // three round trips instead of one.
    final paths = <(IdSlot, String?)>[
      (IdSlot.front, user.idPhotoUrl),
      (IdSlot.back, user.idBackUrl),
      (IdSlot.selfie, user.idSelfieUrl),
    ];
    final signed = await Future.wait([
      for (final (_, path) in paths)
        path == null ? Future<String?>.value() : svc.signedUrlFor(path),
    ]);
    final entries = <(IdSlot, String?)>[
      for (var i = 0; i < paths.length; i++) (paths[i].$1, signed[i]),
    ];

    if (!mounted) return;

    // Every slot that exists failed to sign - almost certainly the storage
    // policy declining (an official of another barangay). Say so plainly
    // rather than showing three broken image frames.
    final anySubmitted = entries.any((e) => e.$2 != null);
    if (!anySubmitted) {
      showErrorSnackbar(context, 'You do not have access to these photos.');
      return;
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: ListView(
            controller: scrollCtrl,
            children: [
              AppText(user.fullName, style: AppTextStyles.heading3),
              const SizedBox(height: 2),
              AppText(
                IdType.label(user.idType),
                style: AppTextStyles.bodySmall
                    .copyWith(fontWeight: FontWeight.w600),
              ),

              // §8 minors - a school ID means the guardian block is part of
              // the review, not an afterthought.
              if (user.isMinor) ...[
                const SizedBox(height: 10),
                _GuardianBlock(user: user),
              ],

              const SizedBox(height: 14),
              for (final (slot, url) in entries) ...[
                Text(
                  switch (slot) {
                    IdSlot.front => ctx.s.idFrontTitle,
                    IdSlot.back => ctx.s.idBackTitle,
                    IdSlot.selfie => ctx.s.idSelfieTitle,
                  },
                  style: AppTextStyles.bodySmall
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                if (url == null)
                  Container(
                    height: 90,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.3)),
                    ),
                    child: AppText(ctx.s.notSubmittedYet,
                        style: AppTextStyles.bodySmall),
                  )
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: InteractiveViewer(
                      maxScale: 4,
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        // ID photos are captured at up to 1600px. Decoded at
                        // full size that is ~10MB of ARGB per photo, and the
                        // reviewer opens three of them per applicant. Capping
                        // the decode at 1080 keeps it sharp at 4x zoom on a
                        // phone screen and cuts the memory by more than half.
                        cacheWidth: 1080,
                        errorBuilder: (_, __, ___) => Container(
                          height: 90,
                          alignment: Alignment.center,
                          color: AppColors.background,
                          child: const Text('Could not load this photo.'),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
              ],
              SizedBox(height: MediaQuery.of(ctx).padding.bottom + 12),
            ],
          ),
        ),
      ),
    );
  }

  UserModel? get _me => context.read<AuthProvider>().user;
  bool get _canVerify => can(_me, Capability.verifyUser);
  bool get _canManagePositions => can(_me, Capability.managePositions);
  bool get _canEditDetails => can(_me, Capability.editUserDetails);

  void _denied(Capability capability) {
    HapticFeedback.heavyImpact();
    final reason = capabilityBlockedReason(_me, capability);
    if (reason != null) showErrorSnackbar(context, reason);
  }

  void _handleUserAction(String action, UserModel user) {
    switch (action) {
      case 'verify':
        _verifyUser(user);
        break;
      case 'lock':
        _lockUser(user, true);
        break;
      case 'unlock':
        _lockUser(user, false);
        break;
      case 'edit':
        _showEditDetails(user);
        break;
      case 'position':
        _showPositionSheet(user);
        break;
    }
  }

  /// Frosted bottom sheet for picking a barangay hall position.
  void _showPositionSheet(UserModel user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
            0, 12, 0, MediaQuery.of(ctx).padding.bottom + 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: AppText(context.s.assignPosition,
                        style: AppTextStyles.heading3),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AppText(user.fullName, style: AppTextStyles.caption),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.divider),
            ...assignablePositions(_me).map((pos) {
              final selected = user.position == pos;
              return ListTile(
                leading: Icon(positionIcon(pos),
                    color: selected ? AppColors.primary : AppColors.textSecondary),
                title: AppText(UserPosition.label(pos)),
                trailing: selected
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _assignPosition(user, pos);
                },
              );
            }),
            if (user.hasPosition &&
                // Clearing a position hands out FULL access through the
                // `!hasPosition => true` fallback in permissions.dart, so it
                // is a promotion in disguise and gated at Captain rank.
                canSetPositionOf(_me, user,
                    newPosition: null, checkNewPosition: true)) ...[
              const Divider(height: 1, color: AppColors.divider),
              ListTile(
                leading: const Icon(Icons.person_remove_rounded,
                    color: AppColors.error),
                title: Text(context.s.removePosition,
                    style: TextStyle(color: AppColors.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  _assignPosition(user, null);
                },
              ),
            ],
          ],
        ),
      ).animate().slideY(
          begin: 0.18, end: 0, duration: 380.ms, curve: Curves.easeOutBack),
    );
  }

  Future<void> _assignPosition(UserModel user, String? position) async {
    try {
      final official = context.read<AuthProvider>().user!;
      await _userService.setUserPosition(user.id, position);
      await _auditService.logAction(
        userId: official.id,
        action: 'set_position',
        details: position == null
            ? 'Removed position from ${user.fullName}'
            : 'Assigned ${UserPosition.label(position)} to ${user.fullName}',
      );
      if (!mounted) return;
      HapticFeedback.lightImpact();
      showSuccessSnackbar(
        context,
        position == null
            ? 'Position removed'
            : '${user.fullName} is now ${UserPosition.label(position)}',
      );
      _loadUsers();
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      showErrorSnackbar(context, 'Could not update position: $e');
    }
  }
}

// ── Pulsing strike badge ──────────────────────────────────────────────────────
class _StrikeBadge extends StatefulWidget {
  final int strikes;
  const _StrikeBadge({required this.strikes});

  @override
  State<_StrikeBadge> createState() => _StrikeBadgeState();
}

class _StrikeBadgeState extends State<_StrikeBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    final speed = widget.strikes >= 3
        ? const Duration(milliseconds: 600)
        : widget.strikes == 2
            ? const Duration(milliseconds: 900)
            : const Duration(milliseconds: 1300);
    _ctrl = AnimationController(vsync: this, duration: speed)..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _color {
    if (widget.strikes >= 3) return AppColors.error;
    if (widget.strikes == 2) return const Color(0xFFF59E0B);
    return const Color(0xFFEAB308);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Opacity(
        opacity: _pulse.value,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _color.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, size: 11, color: _color),
              const SizedBox(width: 3),
              AppText(
                '${widget.strikes}',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// The ID button on a pending row.
///
/// Shows how many of the three photographs have arrived, because "some photos
/// submitted" and "a complete submission" call for different actions: the
/// first is waiting on the resident, the second is waiting on the official.
/// A single badge icon could not tell those apart.
class _IdBadgeButton extends StatelessWidget {
  final UserModel user;
  final VoidCallback onOpen;

  const _IdBadgeButton({required this.user, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final done = [user.idPhotoUrl, user.idBackUrl, user.idSelfieUrl]
        .where((p) => p != null)
        .length;

    final color = switch (done) {
      0 => AppColors.textTertiary,
      3 => AppColors.primary,
      _ => AppColors.warning,
    };

    return IconButton(
      tooltip: done == 0
          ? context.s.noIdSubmitted
          : '${context.s.viewSubmittedId} ($done/3)',
      onPressed: done == 0 ? null : onOpen,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.badge_outlined, color: color),
          if (done > 0 && done < 3)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: AppColors.warning,
                  shape: BoxShape.circle,
                ),
                child: AppText(
                  '$done',
                  style: const TextStyle(
                      fontSize: 8,
                      color: Colors.white,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Guardian details for an under-18 account (§8, RA 10173).
///
/// Rendered as a warning when consent is missing rather than being hidden:
/// approving a minor with no guardian on record is the mistake this block
/// exists to prevent, and a reviewer cannot avoid a problem they cannot see.
class _GuardianBlock extends StatelessWidget {
  final UserModel user;

  const _GuardianBlock({required this.user});

  @override
  Widget build(BuildContext context) {
    final missing = user.needsGuardianConsent;
    final color = missing ? AppColors.error : AppColors.success;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                missing
                    ? Icons.warning_amber_rounded
                    : Icons.verified_user_rounded,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  missing
                      ? context.s.guardianMissing
                      : context.s.guardianOnRecord,
                  style: AppTextStyles.bodySmall
                      .copyWith(fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ],
          ),
          if (!missing) ...[
            const SizedBox(height: 6),
            AppText(
              '${user.guardianName ?? "—"}'
              '${user.guardianRelationship != null ? " (${user.guardianRelationship})" : ""}',
              style: AppTextStyles.bodySmall,
            ),
            if (user.guardianPhone != null)
              AppText(user.guardianPhone!, style: AppTextStyles.caption),
          ],
        ],
      ),
    );
  }
}
