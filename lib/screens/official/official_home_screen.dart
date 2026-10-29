import '../../utils/helpers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/incident_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/responder_location_provider.dart';
import '../../widgets/animated_bottom_nav_bar.dart';
import '../../widgets/lazy_indexed_stack.dart';
import '../../widgets/activity_toast.dart';
import '../../l10n/app_strings.dart';
import 'dashboard_tab.dart';
import 'map_tab.dart';
import 'incidents_tab.dart';
import 'users_tab.dart';

class OfficialHomeScreen extends StatefulWidget {
  const OfficialHomeScreen({super.key});

  @override
  State<OfficialHomeScreen> createState() => _OfficialHomeScreenState();
}

class _OfficialHomeScreenState extends State<OfficialHomeScreen> {
  int _currentIndex = 0;

  late IncidentProvider _incidentProvider;
  bool _toastInitialized = false;
  int _lastIncidentCount = 0;
  String? _lastTopId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
      _subscribeRealtime();
      context.read<NotificationProvider>().subscribe();
      // A killed app leaves is_sharing_location = true with stale coordinates
      // still published — a frozen pin the reporter reads as live help. This
      // now RESUMES the broadcast rather than switching it off, which removes
      // the stale pin by publishing a fresh fix instead of by going dark. See
      // ResponderLocationProvider.reconcileOnStartup.
      final me = context.read<AuthProvider>().user;
      if (me != null) {
        _reconcileSharing(me.id, me.isSharingLocation);
      }
      _incidentProvider = context.read<IncidentProvider>();
      _incidentProvider.addListener(_onIncidentsChanged);
    });
  }

  /// Resumes a broadcast the official left on, and says so.
  ///
  /// Resuming silently would be the wrong trade: they opted in and never opted
  /// out, but a position being published again is worth one line on screen.
  Future<void> _reconcileSharing(String userId, bool wasSharing) async {
    if (!wasSharing) return;
    final provider = context.read<ResponderLocationProvider>();
    await provider.reconcileOnStartup(userId: userId, wasSharing: wasSharing);
    if (!mounted) return;

    if (provider.resumedOnStartup) {
      provider.consumeResumeNotice();
      showSuccessSnackbar(context, context.s.locationSharingResumed);
    } else if (provider.resumeFailed) {
      provider.consumeResumeFailure();
      showErrorSnackbar(context, context.s.locationSharingCouldNotResume);
    }
  }

  // Establishes the realtime channel once per session — _loadData() is
  // reused as a refresh callback (pull-to-refresh, navigation return), and
  // re-subscribing on every one of those calls was tearing down and
  // recreating the Supabase realtime channel far more than necessary.
  void _subscribeRealtime() {
    final user = context.read<AuthProvider>().user;
    if (user != null && user.barangayId != null) {
      context.read<IncidentProvider>().subscribeToBarangay(user.barangayId!);
    }
  }

  @override
  void dispose() {
    _incidentProvider.removeListener(_onIncidentsChanged);
    super.dispose();
  }

  void _onIncidentsChanged() {
    final incidents = _incidentProvider.incidents;

    if (!_toastInitialized) {
      // Wait until loading finishes to set baseline — avoids toasting on initial load
      if (!_incidentProvider.isLoading) {
        _lastIncidentCount = incidents.length;
        _lastTopId = incidents.isNotEmpty ? incidents.first.id : null;
        _toastInitialized = true;
      }
      return;
    }

    if (incidents.isNotEmpty &&
        incidents.length > _lastIncidentCount &&
        incidents.first.id != _lastTopId) {
      final newest = incidents.first;
      _lastTopId = newest.id;
      _lastIncidentCount = incidents.length;
      if (mounted) {
        ActivityToastManager.show(
          context,
          category: newest.category,
          severityLevel: newest.severityLevel,
          onTap: () => Navigator.pushNamed(
            context,
            '/incident-manage',
            arguments: newest.id,
          ).then((_) => _loadData()),
        );
      }
    } else {
      _lastIncidentCount = incidents.length;
      if (incidents.isNotEmpty) _lastTopId = incidents.first.id;
    }
  }

  void _loadData() {
    final user = context.read<AuthProvider>().user;
    if (user != null && user.barangayId != null) {
      final incidentProvider = context.read<IncidentProvider>();
      incidentProvider.loadBarangayIncidents(user.barangayId!);
      incidentProvider.loadStats(user.barangayId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LazyIndexedStack(
        index: _currentIndex,
        children: [
          DashboardTab(onRefresh: _loadData, onViewAll: () => setState(() => _currentIndex = 2)),
          const MapTab(),
          IncidentsTab(onRefresh: _loadData),
          const UsersTab(),
        ],
      ),
      bottomNavigationBar: AnimatedBottomNavBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: [
          AnimatedNavItem(icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard_rounded, label: context.s.dashboard),
          AnimatedNavItem(icon: Icons.map_outlined, activeIcon: Icons.map_rounded, label: context.s.map),
          AnimatedNavItem(icon: Icons.list_alt_outlined, activeIcon: Icons.list_alt_rounded, label: context.s.incidents),
          AnimatedNavItem(icon: Icons.people_outline, activeIcon: Icons.people_rounded, label: context.s.users),
        ],
      ),
    );
  }
}
