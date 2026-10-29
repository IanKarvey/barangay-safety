import '../../utils/live_refresh.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/incident_provider.dart';
import '../../services/comment_service.dart';
import '../../services/notification_service.dart';
import '../../providers/auth_provider.dart';
import '../../models/comment_model.dart';
import '../../utils/constants.dart';
import '../../l10n/app_strings.dart';
import '../../utils/helpers.dart';
import '../../widgets/widgets.dart';
import '../shared/photo_gallery_screen.dart';
import '../../widgets/app_text.dart';
import '../../widgets/waiting_for_response_card.dart';

class ReportDetailScreen extends StatefulWidget {
  final String incidentId;

  const ReportDetailScreen({super.key, required this.incidentId});

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen>
    with SingleTickerProviderStateMixin, LiveRefreshMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnim;
  bool _isDeleting = false;
  final _commentService = CommentService();
  final _notifService = NotificationService();
  List<CommentModel> _comments = [];
  final _replyController = TextEditingController();
  StreamSubscription? _commentsSub;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    // The reporter is often sitting on this exact screen while the barangay
    // works their case. The provider's realtime subscription is the fast path;
    // this is the floor under it.
    startLiveRefresh();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    // Deferred to after the first frame — loadIncident() calls
    // notifyListeners() synchronously, which throws "setState() called
    // during build" if fired while this screen's own initial build is
    // still in progress.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<IncidentProvider>().loadIncident(widget.incidentId);
    });
    _watchComments();
  }

  /// Live thread — replaces the old one-shot fetch so an official's reply
  /// appears without the resident pulling to refresh.
  void _watchComments() {
    _commentsSub?.cancel();
    _commentsSub = _commentService.watchComments(widget.incidentId).listen(
      (comments) {
        if (mounted) setState(() => _comments = comments);
      },
      onError: (e) {
        // An unhandled error kills the stream permanently, which would look
        // like "chat just stopped working" with nothing in the logs.
        debugPrint('ReportDetail: comment stream error: $e');
      },
      cancelOnError: false,
    );
  }

  /// Re-reads this one incident. See LiveRefreshMixin.
  @override
  Duration get livePollInterval => const Duration(seconds: 15);

  @override
  Future<void> onLiveRefresh() =>
      context.read<IncidentProvider>().loadIncident(widget.incidentId, silent: true);

  @override
  void dispose() {
    _fadeController.dispose();
    _replyController.dispose();
    _commentsSub?.cancel();
    super.dispose();
  }

  /// Lets the resident reply to the barangay.
  ///
  /// Previously this screen only rendered official messages, so a resident
  /// could be asked a clarifying question about their own emergency with no
  /// way to answer — one-way communication in a safety app.
  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _isSending) return;

    final user = context.read<AuthProvider>().user;
    if (user == null) return;

    setState(() => _isSending = true);
    try {
      await _commentService.postComment(
        incidentId: widget.incidentId,
        authorId: user.id,
        authorName: user.fullName,
        authorRole: user.role,
        message: text,
      );
      _replyController.clear();
      if (!mounted) return;
      // No local append — the live stream delivers it, and adding it here
      // too would briefly show the message twice.
      HapticFeedback.lightImpact();

      // Tell the officials handling this, so a reply isn't left unseen until
      // someone happens to reopen the report.
      final incident = context.read<IncidentProvider>().selectedIncident;
      if (incident?.assignedTo != null) {
        await _notifService.send(
          userId: incident!.assignedTo!,
          title: 'Reply from ${user.fullName}',
          body: text,
          type: 'comment',
          incidentId: widget.incidentId,
        );
      }
    } catch (e) {
      // Surface the real reason. A generic "could not send" hid an RLS
      // rejection here and made this take a device query to diagnose —
      // the same swallowing that hid the responder bug.
      debugPrint('ReportDetail: comment post failed: $e');
      if (mounted) {
        showErrorSnackbar(context, 'Could not send: ${_readableError(e)}');
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  /// Turns a raw Postgrest/network error into something a resident can act
  /// on, while keeping enough detail to diagnose from a screenshot.
  String _readableError(Object e) {
    final msg = e.toString();
    if (msg.contains('row-level security') ||
        msg.contains('violates row-level') ||
        msg.contains('42501')) {
      return 'you do not have permission to post here.';
    }
    if (msg.contains('SocketException') || msg.contains('Failed host')) {
      return 'no internet connection.';
    }
    return msg.replaceFirst('Exception: ', '');
  }

  Future<void> _confirmDelete(IncidentProvider provider) async {
    final confirmed = await showFrostedConfirm(
      context,
      title: context.s.deleteReport,
      message:
          'Are you sure you want to delete this report? This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    final success = await provider.deleteIncident(widget.incidentId);
    if (!mounted) return;

    if (success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.s.reportDeletedOk),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(provider.error ?? 'Failed to delete report'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.s.reportDetails),
        actions: [
          Consumer<IncidentProvider>(
            builder: (context, provider, _) {
              final incident = provider.selectedIncident;
              if (incident == null || provider.isLoading) return const SizedBox.shrink();
              if (incident.status != 'pending') return const SizedBox.shrink();
              if (_isDeleting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              return PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(
                          Icons.delete_sweep_rounded,
                          color: Color(0xFF8D1515),
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        AppText(
                          'Delete Report',
                          style: AppTextStyles.body.copyWith(
                            color: const Color(0xFF8D1515),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                onSelected: (val) {
                  if (val == 'delete') _confirmDelete(provider);
                },
              );
            },
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
            return EmptyState(
              icon: Icons.error_outline,
              title: context.s.reportNotFound,
            );
          }

          // Trigger fade-in once content is ready
          if (!_fadeController.isCompleted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _fadeController.forward();
            });
          }

          return FadeTransition(
            opacity: _fadeAnim,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status & Severity Header
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
                        const SizedBox(height: 12),
                        Hero(
                          tag: 'incident_title_${widget.incidentId}',
                          child: Material(
                            type: MaterialType.transparency,
                            child: AppText(categoryLabel(context.s, incident.category), style: AppTextStyles.heading2),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(formatDateTime(incident.createdAt), style: AppTextStyles.bodySmall),
                      ],
                    ),
                  ),

                  // Nobody has responded yet: the live wait and what happens
                  // next. Gone as soon as an official acts.
                  if (incident.isUnanswered)
                    WaitingForResponseCard(incident: incident),

                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Description
                        AppText(context.s.description, style: AppTextStyles.heading3),
                        const SizedBox(height: 8),
                        AppText(incident.description, style: AppTextStyles.body),
                        const SizedBox(height: 20),

                        // Location Map
                        AppText(context.s.location, style: AppTextStyles.heading3),
                        const SizedBox(height: 8),
                        Container(
                          height: 200,
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
                                    width: 72,
                                    height: 72,
                                    child: _PulsingPin(
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
                          'Lat: ${incident.latitude.toStringAsFixed(6)}, Lng: ${incident.longitude.toStringAsFixed(6)}',
                          style: AppTextStyles.caption,
                        ),
                        if (incident.address != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.place, size: 14, color: AppColors.textSecondary),
                              const SizedBox(width: 4),
                              Expanded(
                                child: AppText(incident.address!, style: AppTextStyles.bodySmall),
                              ),
                            ],
                          ),
                        ],
                        if (incident.landmark != null && incident.landmark!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
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
                        ],
                        const SizedBox(height: 20),

                        // Photos
                        if (incident.photoUrls.isNotEmpty) ...[
                          AppText(context.s.photosCount(incident.photoUrls.length), style: AppTextStyles.heading3),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 120,
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
                                      borderRadius: BorderRadius.circular(AppRadius.sm),
                                      child: CachedNetworkImage(
                                        imageUrl: incident.photoUrls[index],
                                        width: 120,
                                        height: 120,
                                        fit: BoxFit.cover,
                                        // See incident_manage_screen — decode
                                        // at tile size, not source size.
                                        memCacheWidth: 360,
                                        placeholder: (_, __) => Container(
                                          color: AppColors.divider,
                                          child: const Center(
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                        ),
                                        errorWidget: (_, __, ___) => Container(
                                          color: AppColors.divider,
                                          child: const Icon(Icons.broken_image),
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                    .animate(delay: Duration(milliseconds: 60 * index))
                                    .fadeIn(duration: 300.ms)
                                    .scale(
                                      begin: const Offset(0.75, 0.75),
                                      duration: 380.ms,
                                      curve: Curves.easeOutBack,
                                    );
                              },
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Videos
                        if (incident.videoUrls.isNotEmpty) ...[
                          AppText(context.s.videosCount(incident.videoUrls.length), style: AppTextStyles.heading3),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 100,
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
                                    height: 100,
                                    decoration: BoxDecoration(
                                      color: Colors.black87,
                                      borderRadius: BorderRadius.circular(AppRadius.sm),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.play_circle_outline, color: Colors.white, size: 36),
                                        const SizedBox(height: 4),
                                        AppText(
                                          'Video ${index + 1}',
                                          style: const TextStyle(color: Colors.white70, fontSize: 12),
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

                        // Response tracker — the resident's window into what
                        // is actually happening, rather than a status label.
                        AppText(context.s.responseProgress,
                            style: AppTextStyles.heading3),
                        const SizedBox(height: 12),
                        IncidentTracker(incident: incident),

                        // Resolution Notes
                        if (incident.resolutionNotes != null &&
                            incident.resolutionNotes!.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          AppText(context.s.resolutionNotes, style: AppTextStyles.heading3),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                            ),
                            child: AppText(incident.resolutionNotes!, style: AppTextStyles.body),
                          ),
                        ],

                        const SizedBox(height: 20),

                        // ── Official Updates ────────────────────────────
                        Row(
                          children: [
                            Flexible(child: AppText(context.s.conversation, style: AppTextStyles.heading3)),
                            const SizedBox(width: 8),
                            if (_comments.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: AppText(
                                  '${_comments.length}',
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_comments.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline_rounded,
                                    size: 16, color: AppColors.textSecondary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    context.s.noMessages,
                                    style: AppTextStyles.bodySmall.copyWith(
                                        color: AppColors.textSecondary),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          ..._comments.map((c) => _MessageBubble(comment: c)),

                        const SizedBox(height: 14),
                        _ReplyComposer(
                          controller: _replyController,
                          isSending: _isSending,
                          onSend: _sendReply,
                        ),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
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
}

// ── Pulsing map pin ──────────────────────────────────────────────────────────
class _PulsingPin extends StatefulWidget {
  final Color color;
  const _PulsingPin({required this.color});

  @override
  State<_PulsingPin> createState() => _PulsingPinState();
}

class _PulsingPinState extends State<_PulsingPin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _radius;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _radius = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _opacity = Tween<double>(begin: 0.6, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Expanding pulse rings
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Container(
            width: 72 * _radius.value,
            height: 72 * _radius.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: _opacity.value * 0.35),
            ),
          ),
        ),
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            // Second ring, offset by half a cycle
            final v = (_ctrl.value + 0.5) % 1.0;
            final r = Curves.easeOut.transform(v);
            final o = (1.0 - r) * 0.5;
            return Container(
              width: 72 * r,
              height: 72 * r,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: o * 0.25),
              ),
            );
          },
        ),
        // Solid dot center
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.5),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        // Pin icon above
        Positioned(
          bottom: 22,
          child: Icon(
            Icons.location_pin,
            size: 28,
            color: widget.color,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Conversation ────────────────────────────────────────────────────────────
/// One message in the resident↔barangay thread.
///
/// The resident's own messages sit on the right in primary colour, officials'
/// on the left in grey — the same convention every messaging app uses, so no
/// one has to work out who said what.
class _MessageBubble extends StatelessWidget {
  final CommentModel comment;

  const _MessageBubble({required this.comment});

  bool get _isFromResident =>
      comment.authorRole == 'resident' || comment.authorRole == 'non_resident';

  @override
  Widget build(BuildContext context) {
    final mine = _isFromResident;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine) ...[
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
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      mine
                          ? context.s.you
                          : (comment.authorName ?? context.s.official),
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(timeAgo(comment.createdAt),
                        style: AppTextStyles.caption),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: mine
                        ? AppColors.primary
                        : AppColors.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(mine ? 12 : 0),
                      topRight: Radius.circular(mine ? 0 : 12),
                      bottomLeft: const Radius.circular(12),
                      bottomRight: const Radius.circular(12),
                    ),
                  ),
                  child: AppText(
                    comment.message,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: mine ? Colors.white : AppColors.textPrimary,
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
        .animate()
        .fadeIn(duration: 240.ms)
        .slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic);
  }
}

/// Input for the resident to message the barangay about their report.
class _ReplyComposer extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;

  const _ReplyComposer({
    required this.controller,
    required this.isSending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.newline,
            style: AppTextStyles.bodySmall,
            decoration: InputDecoration(
              hintText: context.s.messageBarangay,
              hintStyle: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textTertiary),
              filled: true,
              fillColor: AppColors.background,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.6),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: AppColors.primary,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: isSending ? null : onSend,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded,
                      size: 20, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
