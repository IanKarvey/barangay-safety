import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/incident_provider.dart';
import '../../providers/notification_provider.dart';
import '../../utils/constants.dart';
import '../../widgets/app_text.dart';
import '../official/dashboard_tab.dart';
import '../official/incidents_tab.dart';
import '../official/map_tab.dart';
import '../official/users_tab.dart';
import '../shared/analytics_screen.dart';
import '../shared/audit_log_screen.dart';
import '../shared/emergency_contacts_screen.dart';
import '../shared/escalations_screen.dart';
import '../shared/heatmap_screen.dart';
import '../shared/response_analytics_screen.dart';
import '../superadmin/barangay_coordinates_screen.dart';
import 'web_build.dart';
import 'web_page_frame.dart';
import 'web_login_screen.dart';

/// One destination in the sidebar.
class _Dest {
  const _Dest(this.icon, this.label, this.build);

  final IconData icon;
  final String label;
  final Widget Function() build;
}

/// The desktop admin shell — sidebar navigation instead of a bottom bar.
///
/// ## Why this reuses the mobile screens rather than reimplementing them
///
/// `DashboardTab`, `IncidentsTab`, `UsersTab`, `MapTab`, `AnalyticsScreen`,
/// `HeatmapScreen` and `AuditLogScreen` already hold every rule that matters:
/// which incidents an official may see, what a Tanod may do that a Secretary
/// may not, how a status change is written and audited. Rebuilding those for
/// the browser would mean maintaining two copies of the same authorisation
/// logic, and the first time they disagreed the web copy would quietly be the
/// wrong one.
///
/// So they are reused untouched. Only the chrome around them is new.
///
/// ## Why the superadmin's set is built here rather than reused
///
/// `superadmin_home_screen.dart` keeps its four sections as library-private
/// classes (`_SuperAdminDashboard`, `_SuperAdminMapView`, …), so they cannot
/// be imported. Rather than make them public purely to satisfy this file —
/// which would widen that file's API for a reason unrelated to it — the web
/// superadmin is composed from the same *public* screens the mobile superadmin
/// reaches from its header: analytics, heat map, audit log and barangay
/// coordinates, each already taking an `isSuperAdmin` flag where scope
/// differs. The data scoping itself is not duplicated: it comes from
/// [_loadData] calling `loadAllIncidents()` for a superadmin and
/// `loadBarangayIncidents()` for an admin, exactly as the mobile screens do.
///
/// ## The width cap is deliberate
///
/// These screens were laid out for a phone. Stretched across a 2560px monitor
/// a list row becomes one line of text with a kilometre of whitespace after
/// it, which is harder to read than the phone version, not easier. Capping the
/// content column keeps line lengths readable while the sidebar uses the width
/// the bigger screen actually buys.
class WebShell extends StatefulWidget {
  const WebShell({super.key});

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> {
  int _index = 0;
  bool _booted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  /// Restores an existing Supabase session on a page refresh.
  ///
  /// A browser reload tears down all Dart state, so without this an admin is
  /// bounced to the login screen on every F5 even though their session is
  /// still perfectly valid.
  Future<void> _boot() async {
    final auth = context.read<AuthProvider>();
    await auth.initialize();
    if (!mounted) return;
    setState(() => _booted = true);
    if (auth.user != null) _startSession();
  }

  /// Loads data and opens the realtime channels, the same pair the mobile home
  /// screens open in their own `initState`.
  ///
  /// Without the subscriptions the dashboard is a snapshot that only changes
  /// when somebody presses Refresh — an incident filed while an official is
  /// looking at the screen would simply not appear. On a wall-mounted browser
  /// at the hall that is the difference between a dashboard and a screenshot.
  void _startSession() {
    _loadData();
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    final incidents = context.read<IncidentProvider>();
    // Mirrors superadmin_home_screen (subscribeToAll) and
    // official_home_screen (subscribeToBarangay) respectively.
    if (user.isSuperAdmin) {
      incidents.subscribeToAll();
    } else if (user.barangayId != null) {
      incidents.subscribeToBarangay(user.barangayId!);
    }
    context.read<NotificationProvider>().subscribe();
  }

  void _loadData() {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    final incidents = context.read<IncidentProvider>();
    // Superadmins are city-wide; an admin is scoped to their own barangay.
    // Mirrors official_home_screen._loadData and the superadmin equivalent, so
    // both surfaces load the same data for the same person.
    if (user.isSuperAdmin) {
      incidents.loadAllIncidents();
      incidents.loadStats(null);
    } else if (user.barangayId != null) {
      incidents.loadBarangayIncidents(user.barangayId!);
      incidents.loadStats(user.barangayId);
    }
  }

  /// The sidebar for this role.
  ///
  /// A superadmin keeps every destination an official has — they oversee the
  /// same work — and adds the city-wide ones. Ordering puts the daily screens
  /// first and the oversight tools below, so the common path stays at the top
  /// for both roles.
  List<_Dest> _destinations(UserModel user) {
    final superAdmin = user.isSuperAdmin;

    return [
      _Dest(Icons.dashboard_rounded, 'Dashboard', () {
        return DashboardTab(
          onRefresh: _loadData,
          onViewAll: () => setState(() => _index = 1),
        );
      }),
      _Dest(
        Icons.report_rounded,
        superAdmin ? 'All Reports' : 'Incidents',
        () => IncidentsTab(onRefresh: _loadData),
      ),
      _Dest(
        Icons.map_rounded,
        superAdmin ? 'City Map' : 'Map',
        () => const MapTab(),
      ),
      _Dest(
        Icons.people_alt_rounded,
        superAdmin ? 'User Management' : 'Users',
        () => const UsersTab(),
      ),
      _Dest(
        Icons.bar_chart_rounded,
        'Analytics',
        () => AnalyticsScreen(isSuperAdmin: superAdmin),
      ),
      _Dest(
        Icons.local_fire_department_rounded,
        'Heat Map',
        () => HeatmapScreen(isSuperAdmin: superAdmin),
      ),
      _Dest(
        Icons.history_rounded,
        'Activity Log',
        () => const AuditLogScreen(title: 'Activity Log'),
      ),
      _Dest(
        Icons.trending_up_rounded,
        'Escalations',
        () => const EscalationsScreen(),
      ),
      _Dest(
        Icons.timer_rounded,
        'Response Times',
        () => const ResponseAnalyticsScreen(),
      ),
      _Dest(
        Icons.contact_phone_rounded,
        'Emergency Numbers',
        () => const EmergencyContactsScreen(),
      ),
      // City-wide configuration — the superadmin's alone. An admin editing
      // another barangay's coordinates would silently re-route other
      // barangays' reports.
      if (superAdmin)
        _Dest(
          Icons.location_city_rounded,
          'Barangay Coordinates',
          () => const BarangayCoordinatesScreen(),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!_booted) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final user = context.watch<AuthProvider>().user;

    if (user == null) {
      return WebLoginScreen(onSignedIn: _startSession);
    }

    // Residents have no business in the admin dashboard, and the mobile app is
    // where their features actually live (camera, GPS, push). Saying so is
    // kinder than an empty dashboard they cannot action anything from.
    if (!user.isAdmin && !user.isSuperAdmin) {
      return _NotAnAdmin(name: user.fullName);
    }

    final destinations = _destinations(user);
    // A role change between builds (or a shorter list after sign-out/sign-in
    // as a different role) must not leave the index pointing past the end.
    final index = _index.clamp(0, destinations.length - 1);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          _Sidebar(
            destinations: destinations,
            index: index,
            onSelect: (i) => setState(() => _index = i),
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  title: destinations[index].label,
                  onRefresh: _loadData,
                ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: kWebContentWidth),
                      // Built on demand rather than as an IndexedStack: the
                      // map, heat map and analytics screens each start their
                      // own tile fetches and queries on mount, and mounting
                      // all eight at once is the same mistake that caused the
                      // mobile ANR fixed by LazyIndexedStack on 2026-08-11.
                      child: KeyedSubtree(
                        key: ValueKey(index),
                        child: destinations[index].build(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.destinations,
    required this.index,
    required this.onSelect,
  });

  final List<_Dest> destinations;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final superAdmin = user?.isSuperAdmin ?? false;

    return Container(
      width: 252,
      color: AppColors.primaryDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 10),
            child: Row(
              children: [
                const Icon(Icons.shield_rounded, color: Colors.white, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: AppText.heading3(
                    AppConfig.appName,
                    style: AppTextStyles.heading3.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // The scope badge is not decoration: an official and a superadmin see
          // the same screens here, and only this says whether the numbers on
          // them cover one barangay or the whole city.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: superAdmin
                    ? Colors.amber.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    superAdmin
                        ? Icons.verified_rounded
                        : Icons.location_on_rounded,
                    size: 13,
                    color: superAdmin ? Colors.amber : Colors.white70,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: AppText.caption(
                      superAdmin
                          ? 'City-wide access'
                          : (user?.barangayName ?? 'Barangay'),
                      maxLines: 1,
                      style: AppTextStyles.caption.copyWith(
                        color: superAdmin ? Colors.amber : Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    _NavItem(
                      icon: destinations[i].icon,
                      label: destinations[i].label,
                      selected: index == i,
                      onTap: () => onSelect(i),
                    ),
                ],
              ),
            ),
          ),
          const Divider(color: Colors.white24, height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText.bodySmall(
                  user?.fullName ?? '',
                  maxLines: 1,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                AppText.caption(
                  superAdmin
                      ? 'City Administrator'
                      : (user?.position ?? 'Barangay Official'),
                  maxLines: 1,
                  style: AppTextStyles.caption.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () => context.read<AuthProvider>().signOut(),
                    icon: const Icon(Icons.logout_rounded,
                        size: 18, color: Colors.white70),
                    label: const Text('Sign out',
                        style: TextStyle(color: Colors.white70)),
                  ),
                ),
                const SizedBox(height: 4),
                // Which bundle is actually running — see web_build.dart.
                AppText.caption(
                  'build $kBuildId',
                  maxLines: 1,
                  style: AppTextStyles.caption
                      .copyWith(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color:
          selected ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          child: Row(
            children: [
              Icon(icon,
                  size: 20, color: selected ? Colors.white : Colors.white70),
              const SizedBox(width: 12),
              Expanded(
                child: AppText.body(
                  label,
                  maxLines: 1,
                  style: AppTextStyles.body.copyWith(
                    color: selected ? Colors.white : Colors.white70,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.onRefresh});

  final String title;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<NotificationProvider>().unreadCount;

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(child: AppText.heading3(title, maxLines: 1)),
          if (unread > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Chip(
                avatar: const Icon(Icons.notifications_active_rounded,
                    size: 16, color: AppColors.primary),
                label: Text('$unread unread'),
                backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                side: BorderSide.none,
              ),
            ),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}

class _NotAnAdmin extends StatelessWidget {
  const _NotAnAdmin({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.phone_android_rounded,
                  size: 56, color: AppColors.textTertiary),
              const SizedBox(height: 20),
              AppText.heading2(
                'Signed in as $name',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              AppText.body(
                'This dashboard is for barangay officials and administrators. '
                'Reporting an incident needs your camera and location, so '
                'residents use the mobile app instead.',
                textAlign: TextAlign.center,
                style:
                    AppTextStyles.body.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => context.read<AuthProvider>().signOut(),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
