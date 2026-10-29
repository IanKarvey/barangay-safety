import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/non_resident_session_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/responder_location_provider.dart';
import '../../services/non_resident_service.dart';
import '../../utils/constants.dart';
import '../../l10n/app_strings.dart';
import '../../utils/helpers.dart';
import '../shared/photo_gallery_screen.dart';
import '../shared/live_tracking_screen.dart';
import '../../widgets/app_tile_layer.dart';
import '../../widgets/app_map_attribution.dart';
import '../../widgets/app_text.dart';

/// The barangay's live view of non-resident emergency reports.
///
/// This is the other half of §1 — a non-resident files a report and this is
/// where the Secretary sees it, watches their live location, and decides to
/// deploy or disregard.
class NonResidentQueueScreen extends StatefulWidget {
  const NonResidentQueueScreen({super.key});

  @override
  State<NonResidentQueueScreen> createState() =>
      _NonResidentQueueScreenState();
}

class _NonResidentQueueScreenState extends State<NonResidentQueueScreen> {
  final _service = NonResidentService();
  List<NonResidentSessionModel> _sessions = [];
  bool _isLoading = true;
  String? _error;

  /// Sessions whose proof this official has actually opened. Deploy stays
  /// disabled until then — the "review before deploying" rule is only real if
  /// the UI enforces it.
  final Set<String> _viewedProofs = {};

  /// Sessions sitting in a barangay with no official to see them. Only
  /// populated for superadmins, who are the ones able to intervene.
  Set<String> _orphanedIds = {};

  /// True when viewing every barangay rather than just one.
  bool _isCityWide = false;

  /// Supabase realtime push — the reporter's location lands here the moment
  /// they move, instead of being polled on a clock.
  StreamSubscription? _realtimeSub;

  /// Repaints the cards so "updated 8s ago" and the LOCATION LOST badge stay
  /// truthful even when no new data has arrived.
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _subscribeRealtime();
      _tickTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => mounted ? setState(() {}) : null,
      );
    });
  }

  void _subscribeRealtime() {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    // Superadmins watch every barangay; officials watch their own.
    if (!user.isSuperAdmin && user.barangayId == null) return;

    _realtimeSub = _service
        .subscribeToBarangaySessions(user.isSuperAdmin ? null : user.barangayId)
        .listen(
          (_) => _load(silent: true),
          onError: (e) =>
              debugPrint('NonResidentQueue: realtime error: $e'),
        );
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _tickTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;

    // Superadmins are city-wide, so a null barangay is expected for them and
    // means "all barangays" rather than an error.
    if (!user.isSuperAdmin && user.barangayId == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Your account has no barangay assigned.';
        });
      }
      return;
    }

    if (!silent && mounted) setState(() => _isLoading = true);

    try {
      final sessions = await _service
          .getActiveSessions(user.isSuperAdmin ? null : user.barangayId);
      // Reports sitting in barangays with no official to see them.
      final orphaned = user.isSuperAdmin
          ? await _service.getOrphanedSessions()
          : <NonResidentSessionModel>[];

      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _orphanedIds = orphaned.map((s) => s.id).toSet();
        _isCityWide = user.isSuperAdmin;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Could not load reports: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(context.s.nonResidentReports),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _load(),
            tooltip: context.s.refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          const _ShareLocationBar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Icon(Icons.error_outline_rounded,
              size: 48, color: AppColors.error.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: AppText(_error!,
                textAlign: TextAlign.center, style: AppTextStyles.bodySmall),
          ),
        ],
      );
    }

    if (_sessions.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 100),
          Icon(Icons.emergency_share_rounded,
              size: 56, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          AppText(context.s.noActiveNonResidentReports,
              textAlign: TextAlign.center, style: AppTextStyles.heading3),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Emergency reports from visitors in your barangay will appear '
              'here in real time.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall,
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      // +1 for the city-wide header when a superadmin is viewing.
      itemCount: _sessions.length + (_isCityWide ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
        if (_isCityWide && i == 0) return _buildCityWideBanner();
        final index = _isCityWide ? i - 1 : i;
        final session = _sessions[index];
        return _SessionCard(
          session: session,
          index: index,
          onChanged: _load,
          service: _service,
          proofViewed: _viewedProofs.contains(session.id),
          onProofViewed: () => setState(() => _viewedProofs.add(session.id)),
          isOrphaned: _orphanedIds.contains(session.id),
        );
      },
    );
  }

  /// Tells a superadmin they're seeing every barangay, and flags any reports
  /// that have landed somewhere with nobody to answer them.
  Widget _buildCityWideBanner() {
    final orphanCount = _orphanedIds.length;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: orphanCount > 0
            ? AppColors.error.withValues(alpha: 0.08)
            : AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: (orphanCount > 0 ? AppColors.error : AppColors.primary)
              .withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(
            orphanCount > 0
                ? Icons.report_problem_rounded
                : Icons.public_rounded,
            size: 19,
            color: orphanCount > 0 ? AppColors.error : AppColors.primary,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  orphanCount > 0
                      ? '$orphanCount report${orphanCount == 1 ? '' : 's'} with no official assigned'
                      : 'Viewing all barangays',
                  style: AppTextStyles.bodySmall
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  orphanCount > 0
                      ? 'Nobody in that barangay can see or act on these.'
                      : 'City-wide view — reports from every barangay.',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.2, end: 0);
  }
}

// ── Share-my-location toggle ────────────────────────────────────────────────
/// Opt-in control for broadcasting the official's position to reporters.
///
/// Placed here rather than in settings because this is where an official acts
/// on an emergency — the moment sharing is actually useful. It is never on by
/// default: an official should not be tracked just for being logged in.
class _ShareLocationBar extends StatelessWidget {
  const _ShareLocationBar();

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final provider = context.watch<ResponderLocationProvider>();
    if (user == null) return const SizedBox.shrink();

    final sharing = provider.isSharing;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: sharing
            ? AppColors.success.withValues(alpha: 0.09)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: sharing
              ? AppColors.success.withValues(alpha: 0.4)
              : AppColors.divider,
        ),
      ),
      child: Row(
        children: [
          Icon(
            sharing
                ? Icons.share_location_rounded
                : Icons.location_disabled_rounded,
            size: 20,
            color: sharing ? AppColors.success : AppColors.textSecondary,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sharing ? 'Sharing your location' : 'Share your location',
                  style: AppTextStyles.bodySmall
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  sharing
                      ? 'Reporters can see you approaching'
                      : 'Let reporters see help is on the way',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          if (provider.isBusy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch(
              value: sharing,
              activeThumbColor: AppColors.success,
              onChanged: (_) async {
                HapticFeedback.selectionClick();
                final ok = await provider.toggle(user.id);
                if (!context.mounted) return;
                if (!ok && provider.error != null) {
                  showErrorSnackbar(context, provider.error!);
                  provider.clearError();
                }
              },
            ),
        ],
      ),
    );
  }
}

/// Inline warning strip used for coverage and assignment problems.
class _WarningRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _WarningRow({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: AppText(text,
                style: AppTextStyles.caption
                    .copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ── Session card ────────────────────────────────────────────────────────────
class _SessionCard extends StatelessWidget {
  final NonResidentSessionModel session;
  final int index;
  final VoidCallback onChanged;
  final NonResidentService service;

  /// Whether this official has opened the proof for this session.
  final bool proofViewed;
  final VoidCallback onProofViewed;

  /// True when this report landed in a barangay with no official assigned.
  final bool isOrphaned;

  const _SessionCard({
    required this.session,
    required this.index,
    required this.onChanged,
    required this.service,
    required this.proofViewed,
    required this.onProofViewed,
    this.isOrphaned = false,
  });

  /// Location older than this means we may have lost the reporter.
  static const _staleThreshold = Duration(minutes: 2);

  @override
  Widget build(BuildContext context) {
    final stale = session.locationStaleAfter(_staleThreshold);
    final (statusLabel, statusColor) = _statusDisplay(session.status);

    // Evidence exists but hasn't been opened — Deploy stays locked. Once
    // already deployed, this no longer applies (the button becomes
    // "Mark Resolved").
    final deployBlocked =
        session.proofUrl != null && !proofViewed && !session.isDeployed;

    final coverageKm = session.distanceFromCoverageKm;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: AppText(
                    statusLabel,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
                const Spacer(),
                if (session.isOutsideCoverage)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'OUTSIDE AREA',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                if (stale)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'LOCATION LOST',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Text(timeAgo(session.createdAt),
                    style: AppTextStyles.caption),
              ],
            ),
          ),

          // Identity
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  child: const Icon(Icons.person_rounded,
                      color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(session.fullName,
                          style: AppTextStyles.body
                              .copyWith(fontWeight: FontWeight.w700)),
                      AppText(session.phone, style: AppTextStyles.caption),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.phone_rounded,
                      color: AppColors.success),
                  tooltip: context.s.callReporter,
                  onPressed: () => _call(context, session.phone),
                ),
              ],
            ),
          ),

          // Live location map
          if (session.hasLocation) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 150,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(0)),
                child: IgnorePointer(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter:
                          LatLng(session.lastLat!, session.lastLng!),
                      initialZoom: 16.0,
                      interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.none),
                    ),
                    children: [
                      const AppTileLayer(),
                      const AppMapAttribution(),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(
                                session.lastLat!, session.lastLng!),
                            width: 40,
                            height: 40,
                            child: Container(
                              decoration: BoxDecoration(
                                color: (stale
                                        ? AppColors.error
                                        : AppColors.success)
                                    .withValues(alpha: 0.25),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: stale
                                      ? AppColors.error
                                      : AppColors.success,
                                  width: 3,
                                ),
                              ),
                              child: Icon(Icons.person_pin_circle_rounded,
                                  size: 20,
                                  color: stale
                                      ? AppColors.error
                                      : AppColors.success),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.schedule_rounded,
                      size: 13,
                      color: stale
                          ? AppColors.error
                          : AppColors.textSecondary),
                  const SizedBox(width: 5),
                  Expanded(
                    child: AppText(
                      session.lastLocationAt != null
                          ? 'Location updated ${timeAgo(session.lastLocationAt!)}'
                          : 'No location received',
                      style: AppTextStyles.caption.copyWith(
                        color: stale ? AppColors.error : null,
                        fontWeight: stale ? FontWeight.w600 : null,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.my_location_rounded, size: 15),
                    label: Text(context.s.trackLive),
                    onPressed: () => _openLiveTracking(context),
                  ),
                ],
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(context.s.noLocationYet,
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.error)),
            ),

          // ── Reporter could not call ──────────────────────────────────
          // Shown prominently: the Secretary would otherwise be waiting for
          // a call that is never coming.
          if (session.callFailed) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _WarningRow(
                icon: Icons.phone_disabled_rounded,
                color: AppColors.error,
                text: switch (session.callFailedReason) {
                  'no_credits' =>
                    'Reporter has no load and CANNOT call. Phone them on '
                        '${session.phone}.',
                  'no_signal' =>
                    'Reporter has no signal. They may be unreachable — rely on '
                        'their live location.',
                  'dialer_failed' =>
                    'The reporter\'s dialer failed. Phone them on '
                        '${session.phone}.',
                  _ => 'Reporter could not call. Phone them on '
                      '${session.phone}.',
                },
              ),
            ),
          ],

          // ── Coverage / assignment warnings ───────────────────────────
          if (isOrphaned || session.isOutsideCoverage) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  if (isOrphaned)
                    _WarningRow(
                      icon: Icons.person_off_rounded,
                      color: AppColors.error,
                      text:
                          'No official is assigned to ${session.barangayName ?? 'this barangay'}. '
                          'Nobody there can see or act on this report.',
                    ),
                  if (isOrphaned && session.isOutsideCoverage)
                    const SizedBox(height: 8),
                  if (session.isOutsideCoverage)
                    _WarningRow(
                      icon: Icons.wrong_location_rounded,
                      color: AppColors.warning,
                      text: coverageKm != null
                          ? 'Reporter has left the coverage area — now '
                              '${coverageKm.round()} km from Lipa City centre.'
                          : 'Reporter has left the coverage area.',
                    ),
                ],
              ),
            ),
          ],

          // ── Proof ────────────────────────────────────────────────────
          // The whole point of the proof_ready gate: an official must be able
          // to SEE the evidence before deciding to send anyone.
          if (session.proofUrl != null) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.verified_rounded,
                      size: 15, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(context.s.evidenceSubmitted,
                      style: AppTextStyles.caption
                          .copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GestureDetector(
                onTap: () => _viewProof(context),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CachedNetworkImage(
                        imageUrl: session.proofUrl!,
                        height: 170,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        // A preview strip in a scrolling queue; full-size
                        // decode here multiplied by the number of pending
                        // sessions on screen.
                        memCacheWidth: 720,
                        placeholder: (_, __) => Container(
                          height: 170,
                          color: AppColors.surfaceSecondary,
                          child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          height: 170,
                          color: AppColors.surfaceSecondary,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.broken_image_rounded,
                                    color: AppColors.textTertiary),
                                SizedBox(height: 6),
                                Text(context.s.proofNotLoaded,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Affordance so it reads as tappable
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.zoom_in_rounded,
                                size: 15, color: Colors.white),
                            SizedBox(width: 5),
                            Text(context.s.tapToInspect,
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ] else if (session.hasCalled || session.isReported) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.hourglass_top_rounded,
                        size: 15, color: AppColors.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No evidence submitted yet — deploy with caution.',
                        style: AppTextStyles.caption,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const Divider(height: 24),

          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: Text(
                        session.assignedOfficialId == null ? 'Assign' : 'Reassign'),
                    onPressed: () => _assignOfficial(context),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    icon: const Icon(Icons.cancel_rounded, size: 18),
                    label: Text(context.s.disregard),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.error),
                    onPressed: () => _confirmDisregard(context),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(
                        deployBlocked
                            ? Icons.lock_rounded
                            : Icons.local_shipping_rounded,
                        size: 18),
                    label: Text(
                      deployBlocked
                          ? 'Review proof'
                          : session.isDeployed
                              ? 'Mark Resolved'
                              : 'Deploy',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: session.isDeployed
                          ? AppColors.success
                          : AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.textTertiary,
                      disabledForegroundColor: Colors.white,
                    ),
                    onPressed:
                        deployBlocked ? null : () => _advance(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: 60 + index * 60))
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic);
  }

  (String, Color) _statusDisplay(String status) => switch (status) {
        'active' => ('SIGNED IN', AppColors.textSecondary),
        'reported' => ('REPORTED', AppColors.error),
        'called' => ('CALLED', AppColors.warning),
        'proof_ready' => ('PROOF READY', AppColors.primary),
        'deployed' => ('DEPLOYED', AppColors.success),
        _ => (status.toUpperCase(), AppColors.textSecondary),
      };

  Future<void> _call(BuildContext context, String phone) async {
    try {
      await launchUrl(Uri.parse('tel:$phone'));
    } catch (_) {
      if (context.mounted) {
        showErrorSnackbar(context, 'Could not open the dialer.');
      }
    }
  }

  /// Full-screen proof inspection — pinch-zoom, swipe to dismiss.
  void _viewProof(BuildContext context) {
    if (session.proofUrl == null) return;
    onProofViewed();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoGalleryScreen(photoUrls: [session.proofUrl!]),
      ),
    );
  }

  /// Live tracking inside our own app rather than handing off to Google Maps,
  /// which would lose the live updates and the distance readout.
  void _openLiveTracking(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveTrackingScreen(
          title: session.fullName,
          callNumber: session.phone,
          initialPoints: [_asTrackedPoint(session)],
          pointsStream: service
              .watchSession(session.id)
              .map((s) => s == null ? <TrackedPoint>[] : [_asTrackedPoint(s)]),
        ),
      ),
    );
  }

  static TrackedPoint _asTrackedPoint(NonResidentSessionModel s) {
    return TrackedPoint(
      id: s.id,
      label: s.fullName,
      sublabel: s.phone,
      lat: s.lastLat ?? 0,
      lng: s.lastLng ?? 0,
      updatedAt: s.lastLocationAt,
      color: AppColors.error,
      icon: Icons.emergency_share_rounded,
      pulsing: true,
    );
  }

  Future<void> _advance(BuildContext context) async {
    final next = session.isDeployed ? 'completed' : 'deployed';
    HapticFeedback.mediumImpact();
    try {
      await service.setStatus(session.id, next);
      if (context.mounted) {
        showSuccessSnackbar(
            context, next == 'deployed' ? 'Responders deployed' : 'Marked resolved');
      }
      onChanged();
    } catch (e) {
      if (context.mounted) showErrorSnackbar(context, 'Could not update: $e');
    }
  }

  /// Picks the official who will actually go. The reporter then sees their
  /// name and can ring them directly, instead of only knowing "someone" was
  /// dispatched.
  Future<void> _assignOfficial(BuildContext context) async {
    final barangayId = session.barangayId;
    if (barangayId == null) {
      showErrorSnackbar(context, 'This report has no barangay assigned.');
      return;
    }

    List<ResponderContact> officials;
    try {
      officials = await service.getAssignableOfficials(barangayId);
    } catch (e) {
      if (context.mounted) {
        showErrorSnackbar(context, 'Could not load officials: $e');
      }
      return;
    }

    if (!context.mounted) return;
    if (officials.isEmpty) {
      showErrorSnackbar(
          context, 'No officials are assigned to this barangay.');
      return;
    }

    final picked = await showModalBottomSheet<ResponderContact?>(
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
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AppText(context.s.whoIsResponding,
                    style: AppTextStyles.heading3),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AppText(
                  '${session.fullName} will see their name and be able to call them.',
                  style: AppTextStyles.caption,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.divider),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final o in officials)
                    ListTile(
                      leading: Icon(positionIcon(o.position),
                          color: AppColors.primary),
                      title: AppText(o.fullName),
                      subtitle: AppText(
                        [
                          UserPosition.label(o.position),
                          if (o.phone != null && o.phone!.isNotEmpty) o.phone!,
                        ].join(' · '),
                      ),
                      trailing: session.assignedOfficialId == o.id
                          ? const Icon(Icons.check_rounded,
                              color: AppColors.primary)
                          : null,
                      onTap: () => Navigator.pop(ctx, o),
                    ),
                  if (session.assignedOfficialId != null) ...[
                    const Divider(height: 1, color: AppColors.divider),
                    ListTile(
                      leading: const Icon(Icons.person_remove_rounded,
                          color: AppColors.error),
                      title: Text(context.s.removeAssignment,
                          style: TextStyle(color: AppColors.error)),
                      onTap: () => Navigator.pop(ctx, null),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ).animate().slideY(
          begin: 0.18, end: 0, duration: 380.ms, curve: Curves.easeOutBack),
    );

    // Distinguish "picked nobody" (sheet dismissed) from "chose to unassign".
    if (!context.mounted) return;

    try {
      await service.assignOfficial(session.id, picked?.id);
      if (context.mounted) {
        HapticFeedback.lightImpact();
        showSuccessSnackbar(
          context,
          picked == null
              ? 'Assignment removed'
              : '${picked.fullName} assigned — the reporter can now see and call them',
        );
      }
      onChanged();
    } catch (e) {
      if (context.mounted) {
        showErrorSnackbar(context, 'Could not assign: $e');
      }
    }
  }

  Future<void> _confirmDisregard(BuildContext context) async {
    final ok = await showFrostedConfirm(
      context,
      title: context.s.disregardThisReport,
      message:
          'Use this for bogus reports, or when the reporter has vanished. '
          'Their session ends immediately and they can report again after '
          'the 7-day window.',
      confirmLabel: 'Disregard',
      destructive: true,
      icon: Icons.cancel_rounded,
    );
    if (ok != true) return;

    HapticFeedback.heavyImpact();
    try {
      await service.disregard(session.id, 'Disregarded by barangay official');
      if (context.mounted) showSuccessSnackbar(context, 'Report disregarded');
      onChanged();
    } catch (e) {
      if (context.mounted) showErrorSnackbar(context, 'Could not update: $e');
    }
  }
}
