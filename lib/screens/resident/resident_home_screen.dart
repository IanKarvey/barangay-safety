import '../../services/location_service.dart';
import 'package:geolocator/geolocator.dart';
import '../../utils/live_refresh.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../providers/incident_provider.dart';
import '../../providers/notification_provider.dart';
import '../../services/connectivity_service.dart';
import '../../services/offline_queue_service.dart';
import '../../utils/animations.dart';
import '../../utils/constants.dart';
import '../../l10n/app_strings.dart';
import '../../utils/helpers.dart';
import '../../widgets/widgets.dart';
import '../../widgets/app_text.dart';
import '../../widgets/how_to_report_button.dart';
import '../../services/tutorial_service.dart';

class ResidentHomeScreen extends StatefulWidget {
  const ResidentHomeScreen({super.key});

  @override
  State<ResidentHomeScreen> createState() => _ResidentHomeScreenState();
}

class _ResidentHomeScreenState extends State<ResidentHomeScreen>
    with TickerProviderStateMixin, LiveRefreshMixin {
  int _currentIndex = 0;
  StreamSubscription<bool>? _connectivitySub;

  late final AnimationController _fabController;
  late final Animation<double> _fabScaleAnim;
  late final ScrollController _homeScrollCtrl;

  final LocationService _locationService = LocationService();

  @override
  void initState() {
    super.initState();
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fabScaleAnim = CurvedAnimation(
      parent: _fabController,
      curve: Curves.elasticOut,
    );
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _fabController.forward();
    });
    _homeScrollCtrl = ScrollController();
    // Deferred to after the first frame — calling this synchronously here
    // made IncidentProvider.loadMyIncidents() call notifyListeners() while
    // this screen's own initial build was still in progress, which throws
    // "setState() or markNeedsBuild() called during build".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
      context.read<NotificationProvider>().subscribe();

      // Residents had no incident subscription at all, so an official's
      // update never reached this screen — only tapping the push notification
      // refreshed anything.
      final me = context.read<AuthProvider>().user;
      if (me != null) {
        context.read<IncidentProvider>().subscribeToMyIncidents(me.id);
      }
      startLiveRefresh();
      _showTutorialOnFirstVisit();
    });
    _connectivitySub = ConnectivityService.onStatusChange.listen((isOnline) {
      if (isOnline) _flushOfflineQueue();
    });
  }

  /// Shows "How to Report" once, the first time this person reaches the home
  /// screen after signing in. After that it is only the button.
  ///
  /// It is marked as shown BEFORE it opens, so a crash or a force-close during
  /// the tutorial can never put someone in a loop of seeing it on every launch.
  Future<void> _showTutorialOnFirstVisit() async {
    final me = context.read<AuthProvider>().user;
    if (me == null) return;
    if (await TutorialService.hasSeen(me.id)) return;
    await TutorialService.markSeen(me.id);
    if (!mounted) return;
    Navigator.pushNamed(
      context,
      '/report-tutorial',
      arguments: {'source': 'auto', 'step': 0},
    );
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _fabController.dispose();
    _homeScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _flushOfflineQueue() async {
    final queue = OfflineQueueService();
    final pending = await queue.getQueue();
    if (pending.isEmpty) return;
    if (!mounted) return;

    final provider = context.read<IncidentProvider>();
    for (final report in pending) {
      final result = await provider.createIncident(
        reporterId: report.reporterId,
        barangayId: report.barangayId,
        category: report.category,
        description: report.description,
        severityLevel: report.severityLevel,
        latitude: report.latitude,
        longitude: report.longitude,
        address: report.address,
        landmark: report.landmark,
        photos: report.photoPaths.map((p) => File(p)).toList(),
        videos: report.videoPaths.map((p) => File(p)).toList(),
      );
      if (result != null) await queue.remove(report.localId);
    }
    if (mounted) {
      _loadData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.s.offlineReportsSubmitted),
          backgroundColor: Color(0xFF34C759),
        ),
      );
    }
  }

  /// Floor under the realtime subscription — see LiveRefreshMixin.
  ///
  /// Realtime on `incidents` is the fast path; this catches the case where the
  /// socket is dead and the reporter would otherwise sit on a stale status.
  @override
  Future<void> onLiveRefresh() async {
    final me = context.read<AuthProvider>().user;
    if (me == null) return;
    await context.read<IncidentProvider>().loadMyIncidents(me.id, silent: true);
  }

  /// Opens the report form, but only for somebody inside the coverage area.
  ///
  /// ## Why the check moved here
  ///
  /// It used to run in the form's own `initState`, which meant the form opened
  /// first and *then* announced that it could not be used. Every route forward
  /// was blocked, so the screen sat there dead — the reported "stuck on a
  /// locked screen" (2026-09-15). Checking before navigating means an
  /// out-of-area user is told once, on a screen they can leave.
  ///
  /// ## Why a slow GPS must not block this
  ///
  /// This is the button somebody presses during an emergency. Waiting on a
  /// cold GPS fix before letting them report would be a worse bug than the one
  /// being fixed, so the lookup is given a short budget and **any** failure —
  /// timeout, permission, no signal — opens the form anyway. The form still
  /// has its own check, so a reporter is never blocked by this gate; they are
  /// only ever spared a dead screen when the answer arrives in time.
  Future<void> _openReportForm() async {
    if (!mounted) return;

    Position? position;
    try {
      position = await _locationService
          .getCurrentPosition()
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      position = null;
    }
    if (!mounted) return;

    if (position != null) {
      final distKm = lipaCityDistanceKm(position.latitude, position.longitude);
      if (distKm > 20.0) {
        HapticFeedback.heavyImpact();
        // Dismissible, and it returns to this screen rather than replacing it.
        await showOutsideCitySheet(context, distKm);
        return;
      }
    }

    if (!mounted) return;
    await Navigator.pushNamed(context, '/report-form');
    if (mounted) _loadData();
  }

  void _loadData() {
    final user = context.read<AuthProvider>().user;
    if (user != null) {
      context.read<IncidentProvider>().loadMyIncidents(user.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: LazyIndexedStack(
          index: _currentIndex,
          children: [
            _buildHomeTab(),
            _buildMyReportsTab(),
            _buildProfileTab(),
          ],
        ),
        bottomNavigationBar: AnimatedBottomNavBar(
          currentIndex: _currentIndex,
          onTap: (i) {
            final switchingToHome = i == 0 && _currentIndex != 0;
            setState(() => _currentIndex = i);
            if (switchingToHome && _homeScrollCtrl.hasClients) {
              _homeScrollCtrl.jumpTo(0);
            }
          },
          items: [
            AnimatedNavItem(icon: Icons.house_outlined, activeIcon: Icons.house_rounded, label: context.s.home),
            AnimatedNavItem(icon: Icons.list_alt_outlined, activeIcon: Icons.list_alt_rounded, label: context.s.myReports),
            AnimatedNavItem(icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, label: context.s.profile),
          ],
        ),
        floatingActionButton: _currentIndex == 0
            ? ScaleTransition(
                scale: _fabScaleAnim,
                child: FloatingActionButton(
                  onPressed: _openReportForm,
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 4,
                  shape: const CircleBorder(),
                  child: const Icon(Icons.add_rounded, size: 28),
                ),
              )
            : null,
      ),
    );
  }

  // ── Home Tab ─────────────────────────────────────────────────────────────
  Widget _buildHomeTab() {
    final user = context.watch<AuthProvider>().user;
    final firstName = user?.fullName.split(' ').first ?? 'Resident';

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Fixed dark header ───────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF001245), Color(0xFF0D2272), Color(0xFF001A6E)],
                stops: [0.0, 0.55, 1.0],
              ),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF001245).withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Greeting text
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppText(
                            'Good ${_greeting()},',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              color: Colors.white60,
                            ),
                          ).animate().fadeIn(duration: 400.ms),
                          AppText(
                            firstName,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.6,
                              height: 1.1,
                            ),
                          ).animate(delay: 60.ms).fadeIn(duration: 400.ms).slideX(begin: -0.05, end: 0, curve: Curves.easeOut),
                        ],
                      ),
                    ),
                    // Safety map — lets residents see which areas around them
                    // report the most incidents, so awareness isn't limited to
                    // officials.
                    GestureDetector(
                      onTap: () => Navigator.pushNamed(context, '/heatmap',
                          arguments: false),
                      child: Container(
                        width: 44,
                        height: 44,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 1),
                        ),
                        child: const Icon(Icons.local_fire_department_rounded,
                            color: Colors.white, size: 22),
                      ),
                    ),

                    // Notification bell
                    Consumer<NotificationProvider>(
                      builder: (ctx, np, _) => GestureDetector(
                        onTap: () async {
                          await Navigator.pushNamed(context, '/notifications');
                          if (mounted) _loadData();
                        },
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1),
                              ),
                              child: const Icon(Icons.notifications_outlined, color: Colors.white, size: 22),
                            ),
                            if (np.unreadCount > 0)
                              Positioned(
                                right: -2,
                                top: -2,
                                child: Container(
                                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFFF3B30),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: AppText(
                                      np.unreadCount > 9 ? '9+' : '${np.unreadCount}',
                                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Avatar
                    GestureDetector(
                      onTap: () => setState(() => _currentIndex = 2),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.5),
                        ),
                        child: Center(
                          child: AppText(
                            firstName.isNotEmpty ? firstName[0].toUpperCase() : '?',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ).animate(delay: 80.ms).fadeIn(duration: 400.ms),
                  ],
                ),
                if (user?.barangayName != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded, size: 13, color: Colors.white54),
                      const SizedBox(width: 4),
                      AppText(
                        user!.barangayName!,
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white54),
                      ),
                    ],
                  ).animate(delay: 120.ms).fadeIn(duration: 400.ms),
                ],
              ],
            ),
          ).animate().fadeIn(duration: 500.ms).slideY(begin: -0.04, end: 0, duration: 500.ms, curve: Curves.easeOut),

          // ── Scrollable content ──────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _loadData(),
              child: ListView(
                controller: _homeScrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
                children: [
                  // ── Report CTA ──────────────────────────────────────────
                  Pressable(
                    onTap: _openReportForm,
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0056B3), AppColors.primary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.shield_rounded, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Report an Incident',
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'File a safety report with GPS location',
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                            child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                          ),
                        ],
                      ),
                    ),
                  ).animate(delay: 150.ms).fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOut),

                  // ── "How to Report" — for anyone who has forgotten ──────
                  const SizedBox(height: 14),
                  HowToReportButton(
                    onTap: () => Navigator.pushNamed(
                      context,
                      '/report-tutorial',
                      arguments: {'source': 'button', 'step': 0},
                    ),
                  ).animate(delay: 200.ms).fadeIn(duration: 400.ms),

                  const SizedBox(height: 24),

                  // ── Community Map ───────────────────────────────────────
                  AppText(
                    context.s.communityMap,
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: -0.4),
                  ).animate(delay: 200.ms).fadeIn(duration: 350.ms),
                  const SizedBox(height: 10),
                  RepaintBoundary(child: _CommunityMapCard())
                      .animate(delay: 220.ms).fadeIn(duration: 400.ms),

                  const SizedBox(height: 24),


                  // ── Recent Reports ──────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(child: AppText(
                        context.s.recentReports,
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: -0.4),
                      )),
                      TextButton(
                        onPressed: () => setState(() => _currentIndex = 1),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        ),
                        child: Text(context.s.viewAll, style: const TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ).animate(delay: 260.ms).fadeIn(duration: 350.ms),
                  const SizedBox(height: 8),

                  // ── Incidents consumer ──────────────────────────────────
                  Consumer<IncidentProvider>(
                    builder: (context, provider, _) {
                      final recentReports = provider.myIncidents.take(5).toList();
                      if (provider.myIncidentsLoading && recentReports.isEmpty) {
                        return const IncidentListShimmer(count: 4);
                      }
                      if (recentReports.isEmpty) {
                        return SizedBox(
                          height: 240,
                          child: EmptyState(
                            icon: Icons.shield_outlined,
                            title: context.s.noReportsYet,
                            subtitle: context.s.noReportsHomeSubtitle,
                          ),
                        );
                      }
                      return Column(
                        children: [
                          for (int i = 0; i < recentReports.length; i++)
                            _animatedItem(
                              index: i,
                              child: IncidentCard(
                                key: ValueKey(recentReports[i].id),
                                incident: recentReports[i],
                                // Reload on return: an official may have
                                // advanced the status while the detail screen
                                // was open, leaving this card stale.
                                onTap: () => Navigator.pushNamed(
                                  context,
                                  '/report-detail',
                                  arguments: recentReports[i].id,
                                ).then((_) {
                                  if (mounted) _loadData();
                                }),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── My Reports Tab ────────────────────────────────────────────────────────
  Widget _buildMyReportsTab() {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppText(
                  'My Reports',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Swipe left on a pending report to delete',
                  style: AppTextStyles.footnote,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Consumer<IncidentProvider>(
              builder: (context, provider, _) {
                if (provider.myIncidentsLoading) {
                  return const IncidentListShimmer(count: 6);
                }
                if (provider.myIncidents.isEmpty) {
                  return EmptyState(
                    icon: Icons.shield_outlined,
                    title: context.s.noReportsYet,
                    subtitle: context.s.noReportsListSubtitle,
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _loadData(),
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: provider.myIncidents.length,
                    itemBuilder: (context, index) {
                      final incident = provider.myIncidents[index];
                      return _animatedItem(
                        index: index,
                        child: Dismissible(
                          key: ValueKey(incident.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 28),
                            margin: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.error,
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                            ),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.delete_sweep_rounded,
                                    color: Colors.white, size: 24),
                                SizedBox(height: 4),
                                Text(
                                  'Delete',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          confirmDismiss: (_) async {
                            if (incident.status != 'pending') {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text(context.s.onlyPendingDeletable),
                                ),
                              );
                              return false;
                            }
                            return await showFrostedConfirm(
                              context,
                              title: context.s.deleteReport,
                              message: 'Are you sure? This cannot be undone.',
                              confirmLabel: 'Delete',
                              destructive: true,
                              icon: Icons.delete_outline_rounded,
                            );
                          },
                          onDismissed: (_) async {
                            final success =
                                await provider.deleteIncident(incident.id);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(success
                                    ? 'Report deleted'
                                    : provider.error ?? 'Failed to delete'),
                                backgroundColor:
                                    success ? AppColors.success : AppColors.error,
                              ));
                            }
                          },
                          child: IncidentCard(
                            key: ValueKey('card_${incident.id}'),
                            incident: incident,
                            onTap: () => Navigator.pushNamed(
                              context,
                              '/report-detail',
                              arguments: incident.id,
                            ).then((_) {
                              if (mounted) _loadData();
                            }),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Profile Tab ───────────────────────────────────────────────────────────
  Widget _buildProfileTab() {
    final user = context.watch<AuthProvider>().user;

    final initials = (user?.fullName ?? '')
        .split(' ')
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0].toUpperCase())
        .join();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          // ── Dark navy header ─────────────────────────────────────────────
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF001245), Color(0xFF0D2272), Color(0xFF001A6E)],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
                child: Column(
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4A90E2), Color(0xFF001245)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Center(
                        child: AppText(
                          initials.isEmpty ? '?' : initials,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppText(
                      user?.fullName ?? '',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AppText(
                      user?.email ?? '',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                    ),
                    if (user?.barangayName != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.circular),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                        child: AppText(
                          user!.barangayName!,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

            const SizedBox(height: 20),

            // Account section
            _sectionCard([
              _settingsTile(
                icon: Icons.person_rounded,
                iconColor: AppColors.primary,
                title: context.s.editProfile,
                onTap: () => Navigator.pushNamed(context, '/edit-profile')
                    .then((_) => setState(() {})),
              ),
              _divider(),
              _settingsTile(
                icon: Icons.phone_rounded,
                iconColor: AppColors.textSecondary,
                title: user?.phone ?? 'No phone set',
                onTap: null,
              ),
              _divider(),
              _settingsTile(
                icon: Icons.home_rounded,
                iconColor: AppColors.textSecondary,
                title: user?.address ?? 'No address set',
                onTap: null,
              ),
            ]).animate(delay: 80.ms).fadeIn(duration: 350.ms).slideY(begin: 0.06, end: 0, duration: 350.ms, curve: Curves.easeOutCubic),

            const SizedBox(height: 12),

            // Support section
            _sectionCard([
              _settingsTile(
                icon: Icons.help_rounded,
                iconColor: AppColors.primary,
                title: context.s.helpSupport,
                onTap: () => Navigator.pushNamed(context, '/help-support'),
              ),
              _divider(),
              _settingsTile(
                icon: Icons.info_rounded,
                iconColor: AppColors.textSecondary,
                title: context.s.about,
                onTap: () => Navigator.pushNamed(context, '/about'),
              ),
              _divider(),
              _settingsTile(
                icon: Icons.privacy_tip_rounded,
                iconColor: AppColors.textSecondary,
                title: context.s.privacyNotice,
                onTap: () => Navigator.pushNamed(context, '/privacy'),
              ),
              _divider(),
              // Sits under the notice that explains the right it exercises,
              // rather than buried beside Sign Out where it reads as a
              // second, scarier logout.
              _settingsTile(
                icon: Icons.delete_forever_rounded,
                iconColor: AppColors.error,
                title: user?.dataDeletionRequestedAt != null
                    ? context.s.deletionAlreadyRequested
                    : context.s.requestDeletion,
                titleColor: AppColors.error,
                showChevron: user?.dataDeletionRequestedAt == null,
                onTap: user?.dataDeletionRequestedAt != null
                    ? null
                    : () => _requestDeletion(),
              ),
              _divider(),
              _settingsTile(
                icon: Icons.translate_rounded,
                iconColor: AppColors.primary,
                title: context.s.language,
                showChevron: false,
                trailing: const LanguageToggle(),
                onTap: null,
              ),
            ]).animate(delay: 160.ms).fadeIn(duration: 350.ms).slideY(begin: 0.06, end: 0, duration: 350.ms, curve: Curves.easeOutCubic),

            const SizedBox(height: 12),

            // Sign out
            _sectionCard([
              _settingsTile(
                icon: Icons.logout_rounded,
                iconColor: AppColors.error,
                title: context.s.signOut,
                titleColor: AppColors.error,
                showChevron: false,
                onTap: () async {
                  context.read<IncidentProvider>().resetForLogout();
                  context.read<NotificationProvider>().unsubscribe();
                  await context.read<AuthProvider>().signOut();
                  if (mounted) {
                    Navigator.pushReplacementNamed(context, '/login');
                  }
                },
              ),
            ]),

            const SizedBox(height: 40),
          ],
        ),
      );
  }

  Widget _sectionCard(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
      child: Column(children: children),
    );
  }


  /// RA 10173 right to erasure. Confirms first and states the limit plainly:
  /// incident reports survive, personal details do not. Promising full deletion
  /// and then not doing it would be a worse compliance failure than explaining
  /// the boundary up front.
  Future<void> _requestDeletion() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;

    final ok = await showFrostedConfirm(
      context,
      title: context.s.requestDeletionTitle,
      message: context.s.requestDeletionBody,
      confirmLabel: context.s.requestDeletion,
      destructive: true,
      icon: Icons.delete_forever_rounded,
    );
    if (ok != true || !mounted) return;

    try {
      await AuthService().requestDataDeletion(user.id);
      if (!mounted) return;
      showSuccessSnackbar(context, context.s.deletionRequested);
      setState(() {});
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not send request: $e');
    }
  }

  Widget _settingsTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    Color? titleColor,
    bool showChevron = true,
    Widget? trailing,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: AppText(
                title,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: titleColor ?? AppColors.textPrimary,
                ),
              ),
            ),
            if (trailing != null)
              trailing
            else if (showChevron && onTap != null)
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _divider() => const Padding(
        padding: EdgeInsets.only(left: 62),
        child: Divider(height: 0.5, thickness: 0.5),
      );

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    return 'evening';
  }

  Widget _animatedItem({required int index, required Widget child}) {
    return child
        .animate(delay: AppAnimations.stagger(index))
        .fadeIn(duration: AppAnimations.normal, curve: AppAnimations.smooth)
        .slideY(
          begin: 0.08,
          end: 0,
          duration: AppAnimations.normal,
          curve: AppAnimations.spring,
        );
  }
}

// ── Community Map with radar sweep ───────────────────────────────────────────
class _CommunityMapCard extends StatefulWidget {
  const _CommunityMapCard();

  @override
  State<_CommunityMapCard> createState() => _CommunityMapCardState();
}

class _CommunityMapCardState extends State<_CommunityMapCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _radarCtrl;

  // Lipa City center
  static const _center = LatLng(13.9411, 121.1634);

  @override
  void initState() {
    super.initState();
    _radarCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _radarCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.08),
            blurRadius: 24,
            spreadRadius: -2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: SizedBox(
          height: 190,
          child: Stack(
            children: [
              // Base map — non-interactive preview
              FlutterMap(
                options: const MapOptions(
                  initialCenter: _center,
                  initialZoom: 14.5,
                  interactionOptions: InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  const ColoredBox(color: Color(0xFFAAD3DF)),
                  const AppTileLayer(),
                  const AppMapAttribution(),
                ],
              ),

              // Radar sweep overlay
              AnimatedBuilder(
                animation: _radarCtrl,
                builder: (_, __) => CustomPaint(
                  size: Size.infinite,
                  painter: _RadarPainter(
                    progress: _radarCtrl.value,
                    color: AppColors.primary,
                  ),
                ),
              ),

              // Top gradient for label legibility
              Positioned(
                top: 0, left: 0, right: 0,
                child: Container(
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.45),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // LIVE badge + label
              Positioned(
                top: 12,
                left: 14,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius:
                            BorderRadius.circular(AppRadius.circular),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _PulsingDot(),
                          const SizedBox(width: 5),
                          const Text(
                            'LIVE',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Lipa City',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black54,
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
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

// ── Pulsing dot for LIVE badge ───────────────────────────────────────────────
class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ── Radar sweep CustomPainter ────────────────────────────────────────────────
class _RadarPainter extends CustomPainter {
  final double progress;
  final Color color;

  _RadarPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final center = Offset(cx, cy);
    final radius = size.width * 0.42;
    final angle = progress * 2 * pi;
    const sweepWidth = pi / 2.5;

    // Sweep sector gradient
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        startAngle: angle - sweepWidth,
        endAngle: angle,
        colors: [
          Colors.transparent,
          color.withValues(alpha: 0.08),
          color.withValues(alpha: 0.30),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      angle - sweepWidth,
      sweepWidth,
      true,
      sweepPaint,
    );

    // Leading edge line
    final edgePaint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      center,
      Offset(center.dx + radius * cos(angle), center.dy + radius * sin(angle)),
      edgePaint,
    );

    // Concentric range rings
    final ringPaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, radius * (i / 3), ringPaint);
    }

    // Center crosshair dot
    canvas.drawCircle(
      center,
      3,
      Paint()..color = color.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.progress != progress;
}
