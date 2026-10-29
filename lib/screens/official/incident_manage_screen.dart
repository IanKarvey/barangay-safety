import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../providers/incident_provider.dart';
import '../../services/audit_service.dart';
import '../../services/duplicate_detection_service.dart';
import '../../services/responder_ranking_service.dart';
import '../../services/trust_score_service.dart';
import '../../services/comment_service.dart';
import '../../services/notification_service.dart';
import '../../services/user_management_service.dart';
import '../../services/full_blast_service.dart';
import '../../services/response_service.dart';
import '../../l10n/response_strings.dart';
import '../../widgets/wait_timer.dart';
import '../../widgets/volunteer_button.dart';
import '../../utils/escalation_clock.dart';
import '../../models/incident_model.dart';
import '../../models/comment_model.dart';
import '../../models/user_model.dart';
import '../../models/audit_log_model.dart';
import '../../utils/constants.dart';
import '../../utils/permissions.dart';
import '../../l10n/app_strings.dart';
import '../../utils/helpers.dart';
import '../../widgets/widgets.dart';
import '../shared/photo_gallery_screen.dart';
import '../../widgets/app_text.dart';

class IncidentManageScreen extends StatefulWidget {
  final String incidentId;

  const IncidentManageScreen({super.key, required this.incidentId});

  @override
  State<IncidentManageScreen> createState() => _IncidentManageScreenState();
}

class _IncidentManageScreenState extends State<IncidentManageScreen> {
  final _notesController = TextEditingController();
  final _commentController = TextEditingController();
  final _auditService = AuditService();
  final _commentService = CommentService();
  final _notifService = NotificationService();
  final _userService = UserManagementService();
  final _responseService = ResponseService();
  bool _claiming = false;
  List<AuditLogModel> _auditLogs = [];
  List<CommentModel> _comments = [];
  StreamSubscription? _commentsSub;
  List<UserModel> _officials = [];
  bool _isPostingComment = false;

  @override
  void initState() {
    super.initState();
    // Deferred to after the first frame — loadIncident() calls
    // notifyListeners() synchronously, which throws "setState() called
    // during build" if fired while this screen's own initial build is
    // still in progress.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<IncidentProvider>().loadIncident(widget.incidentId);
      // §4.2 — after the incident is on screen, never before. A suggestion
      // query must not delay an official reaching a live emergency.
      if (!mounted) return;
      final loaded = context.read<IncidentProvider>().selectedIncident;
      if (loaded != null) _loadDuplicates(loaded);
      // Opening a report is recorded (response-time tracking) but is NOT an
      // action: it does not stop the escalation clock.
      unawaited(_responseService.markSeen(widget.incidentId));
    });
    _loadAuditLogs();
    _loadOfficials();
    _watchComments();
  }

  // §4.2 — possible duplicates of this report, and the reports already folded
  // into it. Both empty until loaded; neither blocks the screen.
  List<DuplicateCandidate> _dupCandidates = const [];
  List<IncidentModel> _linkedReports = const [];
  final _dupService = DuplicateDetectionService();

  // §4.4 / §4.5 — both are annotations on decisions the official still makes.
  List<RankedResponder> _rankedResponders = const [];
  TrustScore? _reporterTrust;
  final _rankingService = ResponderRankingService();
  final _trustService = TrustScoreService();

  /// Ranks who to send and summarises the reporter's history.
  ///
  /// Neither result gates anything: assignment stays a free choice over every
  /// official, and no report is ever hidden or deprioritised by a score.
  Future<void> _loadSuggestions(IncidentModel incident) async {
    final ranked = await _rankingService.rank(
      incident: incident,
      officials: _officials,
    );
    final trust = await _trustService.forUser(incident.reporterId);
    if (!mounted) return;
    setState(() {
      _rankedResponders = ranked;
      _reporterTrust = trust;
    });
  }

  /// Loads duplicate suggestions and confirmed links.
  ///
  /// Fires after the incident itself is on screen and never gates it: an
  /// official must be able to work a live emergency whether or not a
  /// suggestion query succeeded.
  Future<void> _loadDuplicates(IncidentModel incident) async {
    // Already ruled on, either way — do not ask again. A suggestion that keeps
    // coming back is one officials learn to dismiss without reading.
    final candidates = incident.duplicateReviewed || incident.isDuplicate
        ? <DuplicateCandidate>[]
        : await _dupService.findCandidatesFor(incident);
    final linked = await _dupService.linkedReports(incident.id);

    if (!mounted) return;
    setState(() {
      _dupCandidates = candidates;
      _linkedReports = linked;
    });
  }

  Future<void> _confirmDuplicate(
      IncidentModel incident, DuplicateCandidate candidate) async {
    final official = context.read<AuthProvider>().user;
    if (official == null) return;

    final ok = await showFrostedConfirm(
      context,
      title: context.s.linkDuplicateTitle,
      message: context.s.linkDuplicateBody,
      confirmLabel: context.s.linkDuplicateConfirm,
      icon: Icons.merge_type_rounded,
    );
    if (ok != true || !mounted) return;

    try {
      // The NEWER report becomes the child. Folding the original into the copy
      // would bury the first person who called it in, along with the earliest
      // timestamp the response time is measured from.
      final older = incident.createdAt.isBefore(candidate.incident.createdAt)
          ? incident
          : candidate.incident;
      final newer = identical(older, incident) ? candidate.incident : incident;

      await _dupService.linkAsDuplicate(
        duplicateId: newer.id,
        originalId: older.id,
      );

      await _auditService.logAction(
        userId: official.id,
        action: 'duplicate_linked',
        incidentId: newer.id,
        details: 'Linked as a duplicate of ${older.id}',
      );

      if (!mounted) return;
      showSuccessSnackbar(context, context.s.duplicateLinked);
      await context.read<IncidentProvider>().loadIncident(widget.incidentId);
      if (!mounted) return;
      final reloaded = context.read<IncidentProvider>().selectedIncident;
      if (reloaded != null) _loadDuplicates(reloaded);
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not link: $e');
    }
  }

  Future<void> _dismissDuplicate(IncidentModel incident) async {
    try {
      await _dupService.dismissSuggestion(incident.id);
      if (!mounted) return;
      setState(() => _dupCandidates = const []);
      showSuccessSnackbar(context, context.s.duplicateDismissed);
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not dismiss: $e');
    }
  }

  Future<void> _loadOfficials() async {
    try {
      final user = context.read<AuthProvider>().user;
      if (user?.barangayId == null) return;
      final all = await _userService.getUsersByBarangay(user!.barangayId!);
      if (mounted) {
        setState(() {
          _officials = all.where((u) => u.isOfficial).toList();
        });
        // Ranking needs the roster, so it waits for it rather than racing it.
        final incident = context.read<IncidentProvider>().selectedIncident;
        if (incident != null) _loadSuggestions(incident);
      }
    } catch (e) {
      // The assign dropdown will be empty. Logged rather than silent, because
      // "no officials to assign" and "the roster query failed" look identical
      // on screen.
      debugPrint('IncidentManage: could not load officials — $e');
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    _commentController.dispose();
    _commentsSub?.cancel();
    super.dispose();
  }

  /// Live thread — an official sees a resident's reply arrive without
  /// reopening the screen.
  void _watchComments() {
    _commentsSub?.cancel();
    _commentsSub = _commentService.watchComments(widget.incidentId).listen(
      (comments) {
        if (mounted) setState(() => _comments = comments);
      },
      onError: (e) {
        debugPrint('IncidentManage: comment stream error: $e');
      },
      cancelOnError: false,
    );
  }

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    final user = context.read<AuthProvider>().user!;
    final incident = context.read<IncidentProvider>().selectedIncident;
    setState(() => _isPostingComment = true);
    try {
      await _commentService.postComment(
        incidentId: widget.incidentId,
        authorId: user.id,
        authorName: user.fullName,
        authorRole: user.role,
        message: text,
      );
      _commentController.clear();
      // No local append — the live stream delivers it.
      // Notify the resident
      // Non-resident reports have no account to notify — they are tracked
      // through their session, not a profile.
      if (incident != null && incident.reporterId != null) {
        await _notifService.send(
          userId: incident.reporterId!,
          title: 'New update on your report',
          body: '${user.fullName}: $text',
          type: 'comment',
          incidentId: widget.incidentId,
        );
      }
    } catch (_) {
      if (mounted) showErrorSnackbar(context, 'Failed to post update');
    } finally {
      if (mounted) setState(() => _isPostingComment = false);
    }
  }

  /// §14 — manual mass alert.
  ///
  /// Confirmed first, and worded so the cost is explicit: this interrupts
  /// everyone regardless of assignment. An alert people learn to dismiss is
  /// worse than no alert, so it must stay rare enough to mean something.
  Future<void> _raiseFullBlast() async {
    final incident = context.read<IncidentProvider>().selectedIncident;
    final me = context.read<AuthProvider>().user;
    if (incident == null || me == null) return;

    final ok = await showFrostedConfirm(
      context,
      title: context.s.fullBlastConfirmTitle,
      message: context.s.fullBlastConfirmBody,
      confirmLabel: context.s.fullBlast,
      destructive: true,
      icon: Icons.campaign_rounded,
    );
    if (ok != true || !mounted) return;

    HapticFeedback.heavyImpact();
    final reached = await FullBlastService().raise(
      barangayId: incident.barangayId,
      incident: incident,
      reason: 'Raised by ${me.fullName}',
    );
    if (!mounted) return;

    if (reached == 0) {
      showErrorSnackbar(context, context.s.fullBlastNobody);
      return;
    }

    // Audited: a mass interruption should always be traceable to whoever
    // decided it was warranted.
    await _auditService.logAction(
      userId: me.id,
      action: 'full_blast',
      incidentId: incident.id,
      details: 'Alerted $reached barangay personnel',
    );
    if (mounted) {
      showSuccessSnackbar(context, context.s.fullBlastSent(reached));
      _loadAuditLogs();
    }
  }

  Future<void> _loadAuditLogs() async {
    try {
      final logs = await _auditService.getIncidentLogs(widget.incidentId);
      if (mounted) setState(() => _auditLogs = logs);
    } catch (e) {
      debugPrint('IncidentManage: could not load audit logs — $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.s.manageIncident),
        actions: [
          Consumer<IncidentProvider>(
            builder: (context, provider, _) => PopupMenuButton<String>(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              onSelected: (val) => _handleMenuAction(val),
              // Flagging a report fraudulent puts a strike on the reporter and
              // can suspend their account. Omitted entirely rather than shown
              // disabled: an accusation of lying is not a control an official
              // should be invited to reach for and then told off about.
              itemBuilder: (ctx) {
                final mayStrike = can(
                    context.read<AuthProvider>().user,
                    Capability.flagFalseReport);

                final mayBlast = can(context.read<AuthProvider>().user,
                    Capability.raiseFullBlast);

                return [
                  if (mayBlast)
                    PopupMenuItem(
                      value: 'full_blast',
                      child: Row(
                        children: [
                          const Icon(Icons.campaign_rounded,
                              color: AppColors.error, size: 18),
                          const SizedBox(width: 12),
                          Text(context.s.fullBlast),
                        ],
                      ),
                    ),
                  if (mayStrike)
                    PopupMenuItem(
                      value: 'flag',
                      child: Row(
                        children: [
                          const Icon(Icons.flag_rounded,
                              color: AppColors.warning, size: 18),
                          const SizedBox(width: 12),
                          Text(context.s.flagAsFraudulent),
                        ],
                      ),
                    ),
                  if (mayStrike)
                    const PopupMenuItem(
                      value: 'false_report',
                      child: Row(
                        children: [
                          Icon(Icons.gavel_rounded,
                              color: AppColors.error, size: 18),
                          SizedBox(width: 12),
                          Text(
                            'Mark as False Report',
                            style: TextStyle(color: AppColors.error),
                          ),
                        ],
                      ),
                    ),
                  // Superadmin-only at the database. Hidden rather than
                  // disabled: an admin has no route to gaining it, so showing
                  // it would only advertise something permanently out of reach.
                  if (can(context.read<AuthProvider>().user,
                      Capability.deleteIncident))
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete_sweep_rounded,
                            color: Color(0xFF8D1515), size: 18),
                        const SizedBox(width: 12),
                        AppText(
                          context.s.deleteReport,
                          style: AppTextStyles.body
                              .copyWith(color: const Color(0xFF8D1515)),
                        ),
                      ],
                    ),
                  ),
                ];
              },
            ),
          ),
        ],
      ),
      body: Consumer<IncidentProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const ReportDetailShimmer();
          }

          final incident = provider.selectedIncident;
          if (incident == null) {
            return EmptyState(icon: Icons.error_outline, title: context.s.notFound);
          }

          // A responder can reach this screen by other routes than the list —
          // a push notification for a case later reassigned, or a stale deep
          // link. Filtering the list alone would leave those doors open, so the
          // check is repeated here where the case is actually opened.
          if (!canOpenIncident(context.watch<AuthProvider>().user, incident)) {
            return const EmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'Not assigned to you',
              subtitle:
                  'This report is being handled by someone else. You will see '
                  'it here once it is assigned to you.',
            );
          }

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  color: severityColor(incident.severityLevel).withValues(alpha: 0.08),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Hero(
                            tag: 'incident_severity_${widget.incidentId}',
                            child: SeverityBadge(level: incident.severityLevel),
                          ),
                          const SizedBox(width: 8),
                          StatusChip(status: incident.status),
                          const Spacer(),
                          Text(
                            '#${incident.id.substring(0, 8).toUpperCase()}',
                            style: AppTextStyles.caption.copyWith(fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                      // Nobody has acted: the live wait, and the last-resort flag
                      // once the report has been escalated all the way.
                      if (incident.isUnanswered) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            WaitTimerChip(
                                submittedAt: incident.createdAt, large: true),
                            if (incident.isUnattended)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF991B1B),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${context.rs.unattendedBadge} · LAST RESORT',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      Hero(
                        tag: 'incident_title_${widget.incidentId}',
                        child: Material(
                          type: MaterialType.transparency,
                          child: AppText(categoryLabel(context.s, incident.category), style: AppTextStyles.heading2),
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Reporter + a way to actually reach them. Officials
                      // could already call non-residents but not residents,
                      // which is backwards — residents file most reports and
                      // are the verified users.
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (incident.reporterName != null)
                                  AppText(
                                    'Reported by ${incident.reporterName}',
                                    style: AppTextStyles.bodySmall,
                                  ),
                                Text(formatDateTime(incident.createdAt),
                                    style: AppTextStyles.caption),
                              ],
                            ),
                          ),
                          if (incident.reporterPhone != null &&
                              incident.reporterPhone!.isNotEmpty)
                            _CallReporterButton(
                              phone: incident.reporterPhone!,
                              name: incident.reporterName,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── SLA Warning Banner ──────────────────────────────
                Builder(builder: (context) {
                  final sla = slaStatus(incident);
                  if (sla == 'ok') return const SizedBox.shrink();
                  final color = slaColor(sla);
                  final isOverdue = sla == 'overdue';
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    color: color.withValues(alpha: 0.10),
                    child: Row(
                      children: [
                        Icon(
                          isOverdue
                              ? Icons.warning_rounded
                              : Icons.timer_outlined,
                          color: color,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isOverdue
                                    ? 'Response Time Exceeded'
                                    : 'Response Getting Slow',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: color,
                                ),
                              ),
                              AppText(
                                '${slaElapsedLabel(incident)} — ${isOverdue ? 'Immediate action required' : 'Please respond soon'}',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  color: color.withValues(alpha: 0.85),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                Padding(
                  padding: const EdgeInsets.all(20),
                  child: _ResponsiveColumns(
                    left: [
                      // ── §4.5 Reporter history ───────────────────────
                      // Rendered only when there is something worth saying.
                      // Badging every ordinary first-time reporter would train
                      // officials to ignore the badge entirely.
                      if (_reporterTrust != null &&
                          !_reporterTrust!.isUnremarkable &&
                          incident.reporterId != null) ...[
                        _TrustBadge(trust: _reporterTrust!),
                        const SizedBox(height: 18),
                      ],

                      // ── §4.2 Possible duplicates ────────────────────
                      if (_dupCandidates.isNotEmpty) ...[
                        _DuplicateSuggestionCard(
                          candidates: _dupCandidates,
                          onLink: (c) => _confirmDuplicate(incident, c),
                          onDismiss: () => _dismissDuplicate(incident),
                          onOpen: (c) => Navigator.pushNamed(
                            context,
                            '/incident-manage',
                            arguments: c.incident.id,
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],

                      // Reports other people filed about this same emergency.
                      if (_linkedReports.isNotEmpty) ...[
                        _LinkedReportsCard(reports: _linkedReports),
                        const SizedBox(height: 18),
                      ],

                      // ── Quick Actions ───────────────────────────────
                      AppText(context.s.quickActions, style: AppTextStyles.heading3)
                          .animate(delay: 60.ms)
                          .fadeIn(duration: 280.ms)
                          .slideX(begin: 0.06, end: 0, duration: 300.ms, curve: Curves.easeOutCubic),
                      const SizedBox(height: 10),
                      _buildStageActions(incident),
                      const SizedBox(height: 20),

                      // ── Status Timeline ──────────────────────────────
                      AppText(context.s.statusProgress, style: AppTextStyles.heading3)
                          .animate(delay: 120.ms)
                          .fadeIn(duration: 280.ms)
                          .slideX(begin: 0.06, end: 0, duration: 300.ms, curve: Curves.easeOutCubic),
                      const SizedBox(height: 12),
                      StatusTimeline(currentStatus: incident.status),
                      const SizedBox(height: 20),

                      // ── Assign To ───────────────────────────────────
                      AppText(context.s.assignedTo, style: AppTextStyles.heading3)
                          .animate(delay: 180.ms)
                          .fadeIn(duration: 280.ms)
                          .slideX(begin: 0.06, end: 0, duration: 300.ms, curve: Curves.easeOutCubic),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => _showAssignBottomSheet(incident),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            border: Border.all(color: AppColors.divider),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: incident.assignedTo != null
                                      ? AppColors.primary.withValues(alpha: 0.1)
                                      : AppColors.background,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  incident.assignedTo != null
                                      ? Icons.person_rounded
                                      : Icons.person_add_rounded,
                                  color: incident.assignedTo != null
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AppText(
                                      incident.assignedTo != null
                                          ? incident.assignedToName ?? 'Official'
                                          : 'Unassigned',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: incident.assignedTo != null
                                            ? AppColors.textPrimary
                                            : AppColors.textSecondary,
                                      ),
                                    ),
                                    Text(
                                      incident.assignedTo != null
                                          ? 'Tap to reassign'
                                          : 'Tap to assign an official',
                                      style: AppTextStyles.caption,
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded,
                                  color: AppColors.textTertiary, size: 20),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Change Severity ─────────────────────────────
                      AppText(context.s.severityLevel, style: AppTextStyles.heading3),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: List.generate(4, (i) {
                          final level = i + 1;
                          final isActive = incident.severityLevel == level;
                          final color = severityColor(level);
                          return ChoiceChip(
                            label: AppText('L$level: ${severityLabelFor(context.s, level)}'),
                            selected: isActive,
                            selectedColor: color.withValues(alpha: 0.2),
                            labelStyle: TextStyle(
                              color: isActive ? color : AppColors.textSecondary,
                              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                              fontSize: 12,
                            ),
                            onSelected: isActive
                                ? null
                                : (_) => _updateSeverity(level),
                          );
                        }),
                      ),
                      const SizedBox(height: 20),

                    ],
                    right: [
                      // ── Description ─────────────────────────────────
                      // §5 — advisory, above the description so it is read
                      // before the report is judged, not after.
                      if (incident.reportedViaVpn || incident.locationMocked)
                        _integrityBanner(incident),

                      AppText(context.s.description, style: AppTextStyles.heading3),
                      const SizedBox(height: 8),
                      AppText(incident.description, style: AppTextStyles.body),
                      const SizedBox(height: 20),

                      // ── Location ────────────────────────────────────
                      AppText(context.s.location, style: AppTextStyles.heading3),
                      const SizedBox(height: 8),
                      Container(
                        height: 180,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: AppColors.divider),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: LatLng(incident.latitude, incident.longitude),
                            initialZoom: 16.0,
                          ),
                          children: [
                            const AppTileLayer(),
                            const AppMapAttribution(),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: LatLng(incident.latitude, incident.longitude),
                                  width: 40,
                                  height: 40,
                                  child: Icon(
                                    Icons.location_pin,
                                    size: 40,
                                    color: severityColor(incident.severityLevel),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      AppText(
                        '${incident.latitude.toStringAsFixed(6)}, ${incident.longitude.toStringAsFixed(6)}',
                        style: AppTextStyles.caption,
                      ),
                      if (incident.address != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.place, size: 14, color: AppColors.textSecondary),
                              const SizedBox(width: 4),
                              Expanded(child: AppText(incident.address!, style: AppTextStyles.bodySmall)),
                            ],
                          ),
                        ),
                      if (incident.landmark != null && incident.landmark!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.near_me, size: 14, color: AppColors.textSecondary),
                              const SizedBox(width: 4),
                              Expanded(
                                child: AppText(
                                  'Near: ${incident.landmark!}',
                                  style: AppTextStyles.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 20),

                      // ── Photos ──────────────────────────────────────
                      if (incident.photoUrls.isNotEmpty) ...[
                        AppText('${context.s.evidencePhotos} (${incident.photoUrls.length})', style: AppTextStyles.heading3),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 100,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: incident.photoUrls.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              return GestureDetector(
                                onTap: () => _openGallery(context, incident.photoUrls, index),
                                child: Hero(
                                  tag: 'photo_${incident.photoUrls[index]}',
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: CachedNetworkImage(
                                      imageUrl: incident.photoUrls[index],
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                      // Decode to thumbnail size. Without
                                      // this each 100px tile held a full
                                      // 1200px bitmap in memory — ~5.7MB for
                                      // a tile that needs 120KB.
                                      memCacheWidth: 300,
                                      placeholder: (_, __) => Container(
                                        color: AppColors.divider,
                                        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ── Videos ──────────────────────────────────────
                      if (incident.videoUrls.isNotEmpty) ...[
                        AppText('${context.s.evidenceVideos} (${incident.videoUrls.length})', style: AppTextStyles.heading3),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 80,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: incident.videoUrls.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              return GestureDetector(
                                onTap: () {
                                  Navigator.pushNamed(
                                    context,
                                    '/video-player',
                                    arguments: {
                                      'url': incident.videoUrls[index],
                                      'title': 'Video ${index + 1}',
                                    },
                                  );
                                },
                                child: Container(
                                  width: 120,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.play_circle_outline, color: Colors.white, size: 32),
                                      const SizedBox(height: 4),
                                      AppText(
                                        'Video ${index + 1}',
                                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ── Resolution Notes ────────────────────────────
                      if (incident.resolutionNotes != null && incident.resolutionNotes!.isNotEmpty) ...[
                        AppText(context.s.resolutionNotes, style: AppTextStyles.heading3),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: AppText(incident.resolutionNotes!, style: AppTextStyles.body),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ── Official Updates / Comments ─────────────────
                      AppText(context.s.officialUpdates, style: AppTextStyles.heading3)
                          .animate(delay: 240.ms)
                          .fadeIn(duration: 280.ms)
                          .slideX(begin: 0.06, end: 0, duration: 300.ms, curve: Curves.easeOutCubic),
                      const SizedBox(height: 4),
                      Text(
                        'Updates are visible to the resident',
                        style: AppTextStyles.caption.copyWith(color: AppColors.primary),
                      ),
                      const SizedBox(height: 12),
                      if (_comments.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Text(
                            'No updates posted yet.',
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                          ),
                        )
                      else
                        ..._comments.asMap().entries.map((e) =>
                            _commentBubble(e.value, isOfficial: true, index: e.key)),
                      const SizedBox(height: 12),
                      // Post new update
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _commentController,
                              maxLines: 3,
                              minLines: 1,
                              textInputAction: TextInputAction.newline,
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
                              decoration: InputDecoration(
                                hintText: context.s.postUpdateHint,
                                hintStyle: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13,
                                  color: AppColors.textTertiary,
                                ),
                                filled: true,
                                fillColor: AppColors.background,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(AppRadius.lg),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _isPostingComment ? null : _postComment,
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: _isPostingComment
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.send_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // ── Audit Log ───────────────────────────────────
                      Row(
                        children: [
                          Flexible(child: AppText(context.s.activityLog, style: AppTextStyles.heading3)),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => Navigator.pushNamed(
                              context,
                              '/audit-log',
                              arguments: {
                                'incidentId': widget.incidentId,
                                'title': 'Incident Activity',
                              },
                            ),
                            icon: const Icon(Icons.open_in_new_rounded, size: 14),
                            label: Text(context.s.viewAll),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_auditLogs.isEmpty)
                        Text(context.s.noActivityLogged, style: AppTextStyles.bodySmall)
                      else ...[
                        ...(_auditLogs.take(3).map((log) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.circle, size: 8, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AppText(
                                      '${log.userName ?? 'Official'}: ${log.details ?? log.action}',
                                      style: AppTextStyles.bodySmall,
                                    ),
                                    Text(timeAgo(log.createdAt), style: AppTextStyles.caption),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ))),
                        if (_auditLogs.length > 3)
                          GestureDetector(
                            onTap: () => Navigator.pushNamed(
                              context,
                              '/audit-log',
                              arguments: {
                                'incidentId': widget.incidentId,
                                'title': 'Incident Activity',
                              },
                            ),
                            child: AppText(
                              '+ ${_auditLogs.length - 3} more entries',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _commentBubble(CommentModel comment, {bool isOfficial = false, int index = 0}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                (comment.authorName?.isNotEmpty == true)
                    ? comment.authorName![0].toUpperCase()
                    : 'O',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: AppText(
                      comment.authorName ?? 'Official',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    )),
                    const SizedBox(width: 6),
                    Text(
                      timeAgo(comment.createdAt),
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.07),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: AppText(
                    comment.message,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: 60 * index))
        .fadeIn(duration: 280.ms)
        .slideX(begin: -0.08, end: 0, duration: 320.ms, curve: Curves.easeOutBack);
  }

  /// [blockedReason] non-null renders the action greyed out and, on tap, says
  /// who *can* do it. A disabled control with no explanation reads as a bug;
  /// naming the responsible position tells the official who to go to.

  /// §5 integrity notice.
  ///
  /// Worded to inform, not accuse. These signals are weak on their own — a VPN
  /// is common and legitimate — and an official who reads "FRAUD" here may
  /// dismiss a real emergency. The last line says so explicitly.
  Widget _integrityBanner(IncidentModel incident) {
    final t = context.s;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gpp_maybe_rounded,
                  size: 17, color: AppColors.warning),
              const SizedBox(width: 8),
              AppText(
                t.integrityWarning,
                style: AppTextStyles.body.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Mock location first: it is the stronger signal by far.
          if (incident.locationMocked)
            AppText('- ${t.integrityMocked}', style: AppTextStyles.bodySmall),
          if (incident.reportedViaVpn)
            AppText('- ${t.integrityVpn}', style: AppTextStyles.bodySmall),
          const SizedBox(height: 6),
          AppText(t.integrityAdvisory, style: AppTextStyles.caption),
        ],
      ),
    );
  }

  Widget _actionButton(String label, IconData icon, Color color, VoidCallback onTap,
      {int index = 0, String? blockedReason}) {
    final blocked = blockedReason != null;
    final shade = blocked ? AppColors.textTertiary : color;

    return GestureDetector(
      onTap: blocked
          ? () {
              HapticFeedback.heavyImpact();
              showErrorSnackbar(context, blockedReason);
            }
          : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: shade.withValues(alpha: blocked ? 0.06 : 0.1),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: shade.withValues(alpha: blocked ? 0.18 : 0.3)),
        ),
        child: Column(
          children: [
            Icon(blocked ? Icons.lock_outline_rounded : icon, color: shade),
            const SizedBox(height: 4),
            AppText(
              label,
              style: TextStyle(color: shade, fontSize: 12, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    )
        .animate(delay: Duration(milliseconds: 80 + 60 * index))
        .fadeIn(duration: 280.ms)
        .scale(
          begin: const Offset(0.88, 0.88),
          duration: 340.ms,
          curve: Curves.easeOutBack,
        );
  }

  void _openGallery(BuildContext context, List<String> urls, int index) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, __, ___) => PhotoGalleryScreen(
          photoUrls: urls,
          initialIndex: index,
        ),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  /// Stage controls for the six-stage response flow.
  ///
  /// Shows ONE primary "next step" rather than every possible status, so an
  /// official under pressure isn't choosing from a wall of buttons — the
  /// resident's tracker only moves when this is pressed, so the action must
  /// be obvious.
  Widget _buildStageActions(IncidentModel incident) {
    final t = context.s;
    final me = context.watch<AuthProvider>().user;

    // Which capability the forward action needs depends on the stage the case
    // is currently at, so it is resolved alongside the label.
    Capability capabilityFor(String status) => switch (status) {
          'pending' => Capability.verifyReport,
          'verified' => Capability.assignOfficial,
          'assigned' => Capability.dispatchResponders,
          'responding' || 'in_progress' => Capability.markOnScene,
          _ => Capability.resolveIncident,
        };

    if (incident.isFlagged) {
      return _actionButton(
        t.restoreToPending,
        Icons.undo_rounded,
        AppColors.statusPending,
        () => _updateStatus('pending'),
        index: 0,
      );
    }

    // (label, icon, colour, next status)
    final (String, IconData, Color, String)? next = switch (incident.status) {
      'pending' => (
          t.verifyReport,
          Icons.verified_rounded,
          AppColors.primary,
          'verified'
        ),
      'verified' => (
          t.assignOfficial,
          Icons.person_pin_rounded,
          AppColors.primary,
          'assigned'
        ),
      'assigned' => (
          t.dispatchResponders,
          Icons.local_shipping_rounded,
          AppColors.warning,
          'responding'
        ),
      // Legacy incidents sit at in_progress; treat them as en route so they
      // can still be driven to completion rather than getting stuck.
      'responding' || 'in_progress' => (
          t.markOnScene,
          Icons.place_rounded,
          AppColors.warning,
          'on_scene'
        ),
      'on_scene' => (
          t.markResolved,
          Icons.check_circle_rounded,
          AppColors.success,
          'resolved'
        ),
      _ => null,
    };

    // Nobody is assigned yet: any official can take it with one press. The
    // database settles who wins if two press at once.
    final canClaim = canVolunteer(me) && isOpenForVolunteers(incident);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canClaim) ...[
          VolunteerButton(
            incident: incident,
            user: me,
            busy: _claiming,
            onPressed: _claim,
          ),
          const SizedBox(height: 8),
        ],
        if (next != null)
          _actionButton(
            next.$1,
            next.$2,
            next.$3,
            blockedReason: capabilityBlockedReason(
                me, capabilityFor(incident.status)),
            // Resolving asks for notes; every other step is a single tap so
            // an official can advance the stage without friction.
            next.$4 == 'resolved'
                ? () => _showResolveDialog()
                : () => _updateStatus(next.$4),
            index: 0,
          ),
        if (incident.isResolved) ...[
          _actionButton(
            t.reopen,
            Icons.refresh_rounded,
            AppColors.statusInProgress,
            blockedReason:
                capabilityBlockedReason(me, Capability.resolveIncident),
            () => _updateStatus('responding'),
            index: 0,
          ),
        ],
        // Stepping back is deliberately secondary and text-only: mistakes
        // happen, but it must never compete with moving forward.
        if (incident.stageIndex > 0 &&
            !incident.isResolved &&
            can(me, Capability.stepBackStage)) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.undo_rounded, size: 15),
              label: AppText(t.stepBack),
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary),
              onPressed: () => _updateStatus(
                _previousStatus(incident.status),
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _previousStatus(String current) => switch (current) {
        'verified' => 'pending',
        'assigned' => 'verified',
        'responding' || 'in_progress' => 'assigned',
        'on_scene' => 'responding',
        'resolved' || 'closed' => 'on_scene',
        _ => 'pending',
      };

  /// "I'm responding" — claims the report for the signed-in official.
  Future<void> _claim() async {
    if (_claiming) return;
    setState(() => _claiming = true);
    final rs = context.rs;
    try {
      final result = await _responseService.claimIncident(widget.incidentId);
      if (!mounted) return;
      if (result.claimed) {
        showSuccessSnackbar(context, rs.claimedYou);
      } else if (result.tooEarly) {
        showErrorSnackbar(
            context, rs.claimTooEarly(formatClock(Duration(seconds: result.secondsLeft ?? 0))));
      } else if (result.alreadyHandled) {
        HapticFeedback.heavyImpact();
        showErrorSnackbar(context, rs.alreadyHandledBy(result.byName ?? '—'));
      } else {
        showErrorSnackbar(context, rs.claimNotAllowed);
      }
      // Pick up the new assignee / status either way.
      await context
          .read<IncidentProvider>()
          .loadIncident(widget.incidentId, silent: true);
      _loadAuditLogs();
    } on ClaimUnavailableException {
      if (mounted) showErrorSnackbar(context, rs.claimNeedsUpdate);
    } catch (e) {
      if (mounted) showErrorSnackbar(context, rs.claimFailed);
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    final user = context.read<AuthProvider>().user!;
    final incident = context.read<IncidentProvider>().selectedIncident;
    final success = await context.read<IncidentProvider>().updateStatus(
      widget.incidentId,
      newStatus,
      officialId: user.id,
    );
    if (mounted) {
      if (success) {
        showSuccessSnackbar(context, 'Status updated to ${statusLabel(newStatus)}');
        _loadAuditLogs();
        // Notify the resident about status change
        if (incident != null && incident.reporterId != null) {
          await _notifService.send(
            userId: incident.reporterId!,
            title: 'Report status updated',
            body: 'Your ${incident.category} report is now ${statusLabel(newStatus)}.',
            type: 'status_change',
            incidentId: widget.incidentId,
          );
        }
      } else {
        showErrorSnackbar(context, 'Failed to update status');
      }
    }
  }

  Future<void> _updateSeverity(int level) async {
    final user = context.read<AuthProvider>().user!;
    final success = await context.read<IncidentProvider>().updateSeverity(
      widget.incidentId,
      level,
      officialId: user.id,
    );
    if (mounted) {
      if (success) {
        showSuccessSnackbar(context, 'Severity updated to Level $level');
        _loadAuditLogs();
      } else {
        showErrorSnackbar(context, 'Failed to update severity');
      }
    }
  }

  void _showResolveDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(context.s.resolveIncident),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.s.addResolutionNotes),
              const SizedBox(height: 12),
              TextField(
                controller: _notesController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: context.s.resolutionNotesHint,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.s.cancel),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final user = context.read<AuthProvider>().user!;
                await context.read<IncidentProvider>().updateStatus(
                  widget.incidentId,
                  'resolved',
                  officialId: user.id,
                  resolutionNotes: _notesController.text.trim().isNotEmpty
                      ? _notesController.text.trim()
                      : null,
                );
                _notesController.clear();
                if (mounted) {
                  showSuccessSnackbar(context, 'Incident marked as resolved');
                  _loadAuditLogs();
                }
              },
              child: Text(context.s.resolve),
            ),
          ],
        );
      },
    );
  }

  void _showAssignBottomSheet(incident) {
    final currentUser = context.read<AuthProvider>().user!;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
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
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AppText(context.s.assignTo, style: AppTextStyles.heading3),
            ),
          ),
          const SizedBox(height: 8),
          if (_officials.isEmpty)
            Padding(
              padding: EdgeInsets.all(20),
              child: Text(context.s.noOfficialsInBarangay,
                  style: AppTextStyles.bodySmall),
            )
          else ...[
            // Unassign option
            if (incident.assignedTo != null)
              ListTile(
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_off_rounded,
                      color: AppColors.error, size: 20),
                ),
                title: Text(context.s.removeAssignment,
                    style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final success = await context.read<IncidentProvider>().assignIncident(
                    widget.incidentId, null, null,
                    officialId: currentUser.id,
                  );
                  if (mounted && success) {
                    showSuccessSnackbar(context, 'Assignment removed');
                    _loadAuditLogs();
                  }
                },
              ),
            // §4.4 — ranked order when a ranking exists, otherwise the plain
            // roster. Falling back to the original list means a ranking
            // failure looks like the screen always used to, not like a bug.
            ...(_rankedResponders.isEmpty
                    ? _officials.map((o) => RankedResponder(
                        official: o,
                        metresAway: null,
                        openCases: 0,
                        score: 0,
                        reason: ''))
                    : _rankedResponders)
                .map((r) {
              final official = r.official;
              return ListTile(
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: incident.assignedTo == official.id
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : AppColors.background,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: AppText(
                    official.fullName.isNotEmpty
                        ? official.fullName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: incident.assignedTo == official.id
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              title: Row(
                children: [
                  Flexible(
                    child: AppText(official.fullName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w500, fontSize: 15)),
                  ),
                  // The badge sits on the top pick only. Marking three
                  // "suggested" would be marking none.
                  if (r.isSuggested && r == _rankedResponders.first) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        context.s.suggested,
                        style: AppTextStyles.caption.copyWith(
                            color: AppColors.success,
                            fontWeight: FontWeight.w700,
                            fontSize: 10),
                      ),
                    ),
                  ],
                ],
              ),
              // Says WHY it ranked where it did — "320m away · free" is
              // checkable by someone who knows the barangay. A bare score
              // would not be.
              subtitle: AppText(
                r.reason.isEmpty
                    ? (official.role == 'superadmin'
                        ? 'Super Admin'
                        : 'Barangay Official')
                    : '${UserPosition.label(official.position)} · ${r.reason}',
                style: AppTextStyles.caption,
              ),
              trailing: incident.assignedTo == official.id
                  ? const Icon(Icons.check_circle_rounded,
                      color: AppColors.primary, size: 20)
                  : null,
              onTap: incident.assignedTo == official.id
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      final success = await context
                          .read<IncidentProvider>()
                          .assignIncident(
                        widget.incidentId,
                        official.id,
                        official.fullName,
                        officialId: currentUser.id,
                      );
                      if (mounted && success) {
                        showSuccessSnackbar(
                            context, 'Assigned to ${official.fullName}');
                        _loadAuditLogs();
                      }
                    },
              );
            }),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _handleMenuAction(String action) {
    if (action == 'full_blast') {
      _raiseFullBlast();
    } else if (action == 'flag') {
      _updateStatus('flagged');
    } else if (action == 'false_report') {
      _confirmFalseReport();
    } else if (action == 'delete') {
      _confirmDelete();
    }
  }

  Future<void> _confirmFalseReport() async {
    final incident = context.read<IncidentProvider>().selectedIncident;
    if (incident == null) return;

    // A strike suspends an account, and a non-resident emergency has none —
    // they report through a one-time session, not a profile. Say so plainly
    // rather than reaching for a null and crashing.
    if (incident.reporterId == null) {
      HapticFeedback.heavyImpact();
      showErrorSnackbar(
        context,
        'This is a non-resident report — there is no account to strike. '
        'Use Disregard instead.',
      );
      return;
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _FalseReportSheet(),
    );
    if (confirmed != true || !mounted) return;

    try {
      final result =
          await _userService.applyFalseReportStrike(incident.reporterId!);
      if (!mounted) return;

      String suspensionMsg;
      if (result.isPermanent) {
        suspensionMsg = 'Account permanently locked (3rd strike).';
      } else if (result.strikes == 2) {
        suspensionMsg = 'Reporter suspended for 30 days (2nd strike).';
      } else {
        suspensionMsg = 'Reporter suspended for 7 days (1st strike).';
      }

      await _notifService.send(
        userId: incident.reporterId!,
        title: 'False Report — Strike ${result.strikes}',
        body: result.isPermanent
            ? 'Your account has been permanently locked due to repeated false reports. Visit the barangay hall to appeal.'
            : 'Your report was marked as false. You are suspended from filing reports for '
                '${result.strikes == 1 ? "7 days" : "30 days"}.',
        type: 'false_report_strike',
        incidentId: incident.id,
      );

      _updateStatus('flagged');
      if (!mounted) return;
      showSuccessSnackbar(context, suspensionMsg);
    } catch (e) {
      if (!mounted) return;
      showErrorSnackbar(context, 'Failed to apply strike: $e');
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: Text(context.s.deleteReport),
        content: const Text(
          'This will permanently remove the report and all its media. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8D1515)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.s.delete),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final success = await context.read<IncidentProvider>().deleteIncident(widget.incidentId);
    if (!mounted) return;

    if (success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.s.reportDeleted),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      showErrorSnackbar(context, 'Failed to delete report');
    }
  }
}

// ── False Report confirmation sheet ─────────────────────────────────────────
class _FalseReportSheet extends StatelessWidget {
  const _FalseReportSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 28),
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.gavel_rounded, size: 36, color: AppColors.error),
              )
                  .animate()
                  .scale(begin: const Offset(0.6, 0.6), duration: 480.ms, curve: Curves.easeOutBack)
                  .fadeIn(duration: 280.ms),
              const SizedBox(height: 20),
              const AppText(
                'Mark as False Report?',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              )
                  .animate(delay: 80.ms)
                  .fadeIn(duration: 280.ms)
                  .slideY(begin: 0.15, end: 0, duration: 300.ms, curve: Curves.easeOutCubic),
              const SizedBox(height: 10),
              const Text(
                'This will apply a strike to the reporter\'s account:\n\n'
                '  • 1st strike — suspended 7 days\n'
                '  • 2nd strike — suspended 30 days\n'
                '  • 3rd strike — account permanently locked\n\n'
                'The reporter will be notified. This action cannot be undone.',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              )
                  .animate(delay: 140.ms)
                  .fadeIn(duration: 280.ms),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.divider),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      child: Text(context.s.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.gavel_rounded, size: 16),
                      label: Text(context.s.applyStrike),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              )
                  .animate(delay: 200.ms)
                  .fadeIn(duration: 280.ms)
                  .slideY(begin: 0.12, end: 0, duration: 300.ms, curve: Curves.easeOutBack),
            ],
          ),
        ),
      ),
    ).animate().slideY(begin: 0.2, end: 0, duration: 420.ms, curve: Curves.easeOutBack);
  }
}


/// Lets an official phone the reporter directly.
///
/// Confirms first: an official may be triaging a list at speed, and an
/// accidental call to a resident in an active emergency is worse than one
/// extra tap.
class _CallReporterButton extends StatelessWidget {
  final String phone;
  final String? name;

  const _CallReporterButton({required this.phone, this.name});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.phone_rounded, color: AppColors.success),
      tooltip: context.s.callPerson(phone),
      onPressed: () async {
        final ok = await showFrostedConfirm(
          context,
          title: context.s.callPersonQ(name ?? context.s.theReporter),
          message: context.s.willDial(phone),
          confirmLabel: context.s.call,
          icon: Icons.phone_rounded,
        );
        if (ok != true) return;

        HapticFeedback.mediumImpact();
        try {
          await launchUrl(Uri.parse('tel:$phone'));
        } catch (_) {
          if (context.mounted) {
            showErrorSnackbar(context, 'Could not open the dialer.');
          }
        }
      },
    );
  }
}


/// §4.2 — "this may already have been reported".
///
/// Phrased as a question with two answers, never as a finding. The detector is
/// matching category, distance and time; it does not know that the fire on the
/// next roof is a second fire. The official does.
class _DuplicateSuggestionCard extends StatelessWidget {
  final List<DuplicateCandidate> candidates;
  final void Function(DuplicateCandidate) onLink;
  final void Function(DuplicateCandidate) onOpen;
  final VoidCallback onDismiss;

  const _DuplicateSuggestionCard({
    required this.candidates,
    required this.onLink,
    required this.onOpen,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.s;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.copy_all_rounded,
                  size: 17, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: AppText(
                  t.possibleDuplicateTitle,
                  style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w700, color: AppColors.warning),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          AppText(t.possibleDuplicateBody, style: AppTextStyles.caption),
          const SizedBox(height: 10),
          for (final c in candidates.take(3)) ...[
            _CandidateRow(candidate: c, onLink: onLink, onOpen: onOpen),
            const SizedBox(height: 8),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded, size: 15),
              label: AppText(t.notDuplicates),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  final DuplicateCandidate candidate;
  final void Function(DuplicateCandidate) onLink;
  final void Function(DuplicateCandidate) onOpen;

  const _CandidateRow({
    required this.candidate,
    required this.onLink,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.s;
    final inc = candidate.incident;

    // Says WHY, not just how confident. "Same photo" and "20m away, 3 min
    // apart" call for completely different amounts of scrutiny, and a bare
    // percentage hides which one this is.
    final reason = switch (candidate.reason) {
      DuplicateReason.sameImage => t.dupSamePhoto,
      DuplicateReason.both => t.dupSamePhotoAndPlace,
      DuplicateReason.proximity => candidate.metresApart == null
          ? t.dupNearby
          : '${candidate.metresApart!.round()}m · ${candidate.minutesApart}min',
    };

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AppText(
                  categoryLabel(t, inc.category),
                  style: AppTextStyles.bodySmall
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: AppText(
                  reason,
                  style: AppTextStyles.caption.copyWith(
                      color: AppColors.warning, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            inc.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => onOpen(candidate),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppColors.textSecondary,
                  ),
                  child: AppText(t.openReport,
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => onLink(candidate),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.warning,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: AppText(t.sameIncident,
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Reports other people filed about this same emergency.
///
/// Shown so the official knows how many people are waiting on this one answer
/// — each of them gets the status update when this case moves.
class _LinkedReportsCard extends StatelessWidget {
  final List<IncidentModel> reports;

  const _LinkedReportsCard({required this.reports});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.group_rounded,
                  size: 17, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: AppText(
                  '${reports.length + 1} ${context.s.peopleReportedThis}',
                  style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w700, color: AppColors.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final r in reports)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: AppText(
                '· ${r.reporterName ?? context.s.nonResident} — '
                '${DateFormat('h:mm a').format(r.createdAt)}',
                style: AppTextStyles.caption,
              ),
            ),
        ],
      ),
    );
  }
}


/// §4.5 — the reporter's standing, when there is something worth saying.
///
/// Deliberately never renders a number. A score of 41 reads as a measurement
/// and invites an official to act on the arithmetic; "3 false reports on
/// record" is the actual fact, and it is the one they can weigh.
class _TrustBadge extends StatelessWidget {
  final TrustScore trust;

  const _TrustBadge({required this.trust});

  @override
  Widget build(BuildContext context) {
    final t = context.s;

    final (color, icon, headline) = switch (trust.band) {
      TrustBand.established => (
          AppColors.success,
          Icons.verified_rounded,
          t.reporterEstablished,
        ),
      TrustBand.caution => (
          AppColors.warning,
          Icons.info_outline_rounded,
          t.reporterCheckHistory,
        ),
      TrustBand.ordinary => (
          AppColors.textSecondary,
          Icons.person_outline_rounded,
          t.reporterOrdinary,
        ),
    };

    // Facts, not the score that was derived from them.
    final facts = <String>[
      if (trust.totalReports > 0) '${trust.totalReports} ${t.reportsFiled}',
      if (trust.flaggedReports > 0)
        '${trust.flaggedReports} ${t.flaggedFalse}',
      if (trust.strikes > 0) '${trust.strikes} ${t.strikesOnRecord}',
      if (trust.isVerified) t.verifiedAccount,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  headline,
                  style: AppTextStyles.bodySmall
                      .copyWith(fontWeight: FontWeight.w700, color: color),
                ),
                if (facts.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(facts.join(' · '), style: AppTextStyles.caption),
                ],
                const SizedBox(height: 3),
                // Said out loud, because a badge like this is exactly the kind
                // of thing that quietly becomes a reason not to send anyone.
                AppText(t.trustNeverBlocks,
                    style: AppTextStyles.caption
                        .copyWith(fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lays the manage-incident sections out as one column on a phone and two on a
/// desktop.
///
/// The screen was written as a single flat list, which is right for 400px and
/// wrong for 1900px: every section stretched edge to edge, the map became a
/// 1800px-wide strip, and an official had to scroll past the whole report to
/// reach the controls that act on it.
///
/// The split follows what each half is *for*, not just balance. The left holds
/// what an official **does** — reporter history, duplicates, the next-step
/// button, timeline, assignment, severity. The right holds what they are
/// **reading** — description, map, photos, notes, the conversation, the audit
/// trail. On a desktop that puts the buttons and the evidence side by side, so
/// looking at a photo and moving the case forward no longer means scrolling
/// between them.
///
/// The breakpoint is on the width this widget is handed, not the window, so a
/// phone can never reach the wide branch and keeps the exact layout it had.
class _ResponsiveColumns extends StatelessWidget {
  const _ResponsiveColumns({required this.left, required this.right});

  final List<Widget> left;
  final List<Widget> right;

  static const double _breakpoint = 900;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [...left, ...right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: left,
              ),
            ),
            const SizedBox(width: 32),
            Expanded(
              flex: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: right,
              ),
            ),
          ],
        );
      },
    );
  }
}
