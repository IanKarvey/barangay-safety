import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/non_resident_session_model.dart';
import '../../providers/non_resident_provider.dart';
import '../../services/responder_location_service.dart';
import '../../services/non_resident_service.dart';
import '../../services/location_service.dart';
import '../../config/app_config.dart';
import '../../utils/constants.dart';
import '../../l10n/app_strings.dart';
import '../../widgets/language_toggle.dart';
import '../../utils/helpers.dart';
import '../../widgets/app_tile_layer.dart';
import '../../widgets/app_map_attribution.dart';
import '../../widgets/app_text.dart';

/// The non-resident's entire app: a map and one report button.
///
/// Deliberately minimal — no tabs, no profile, no history. While a report is
/// in flight the session is locked open and location keeps streaming to the
/// barangay. See §1 in BARANGAY_CONNECT_REQUIREMENTS.md.
class NonResidentHomeScreen extends StatefulWidget {
  const NonResidentHomeScreen({super.key});

  @override
  State<NonResidentHomeScreen> createState() => _NonResidentHomeScreenState();
}

class _NonResidentHomeScreenState extends State<NonResidentHomeScreen>
    with WidgetsBindingObserver {
  final MapController _mapController = MapController();
  final _imagePicker = ImagePicker();
  final _locationService = LocationService();
  bool _hasCenteredOnce = false;

  /// When true the map camera follows the user as they move. Turned off if
  /// they pan the map themselves, so they can look around without a fight.
  bool _followMe = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<NonResidentProvider>();
      if (provider.session?.isInFlight ?? false) {
        provider.startLocationTracking();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final provider = context.read<NonResidentProvider>();
    if (!(provider.session?.isInFlight ?? false)) return;

    // Leaving the app mid-report risks the report being disregarded — warn
    // them the moment they come back. (The 2-3 minute push/SMS reminder that
    // fires while they are away still needs the SMS work in §11.)
    if (state == AppLifecycleState.resumed) {
      _showReturnWarning();
    }
  }

  void _showReturnWarning() {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => _FrostedNotice(
        icon: Icons.warning_amber_rounded,
        iconColor: AppColors.warning,
        title: context.s.stayInTheApp,
        message:
            'Your report is still active. If you leave or close the app, the '
            'barangay may lose your location and disregard your report.',
        actionLabel: 'Got it',
        onAction: () => Navigator.pop(ctx),
      ),
    );
  }

  /// Announces a status change the barangay made — deployed, resolved or
  /// disregarded. The reporter must never have to guess whether help is
  /// coming, so every official decision is surfaced immediately.
  void _announceStatus(String status) {
    final provider = context.read<NonResidentProvider>();
    provider.consumeStatusAnnouncement();

    final (icon, color, title, message, celebrate) = switch (status) {
      'deployed' => (
          Icons.local_shipping_rounded,
          AppColors.success,
          'Help is on the way',
          'The barangay reviewed your report and has dispatched responders. '
              'Stay where you are if it is safe to do so.',
          true,
        ),
      'completed' => (
          Icons.check_circle_rounded,
          AppColors.success,
          'Report resolved',
          'The barangay has marked your emergency as resolved. Thank you for '
              'reporting — you can now close the app.',
          true,
        ),
      'disregarded' => (
          Icons.cancel_rounded,
          AppColors.error,
          'Report closed',
          'The barangay closed this report without dispatching. If you still '
              'need help, please call them directly.',
          false,
        ),
      'proof_ready' => (
          Icons.hourglass_top_rounded,
          AppColors.primary,
          'Proof received',
          'The barangay is reviewing your evidence now.',
          false,
        ),
      _ => (null, null, null, null, false),
    };

    if (icon == null) return;

    HapticFeedback.heavyImpact();
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (ctx) => _FrostedNotice(
        icon: icon,
        iconColor: color!,
        title: title!,
        message: message!,
        actionLabel: celebrate ? 'Got it' : 'OK',
        actionColor: color,
        onAction: () => Navigator.pop(ctx),
      ),
    );
  }

  void _recenter(NonResidentSessionModel session) {
    if (!session.hasLocation) return;
    _mapController.move(LatLng(session.lastLat!, session.lastLng!), 17.0);
  }

  // ── Report flow ───────────────────────────────────────────────────────
  /// Dispatches to whatever step the session is currently on.
  ///
  /// The bottom button is always "the next thing to do", so dismissing any of
  /// the prompt sheets (back button, tap outside) can never dead-end the user
  /// — they just tap the button again to resume where they left off.
  Future<void> _onPrimaryAction(NonResidentSessionModel session) async {
    switch (session.status) {
      case 'active':
        await _onReportPressed(session);
      case 'reported':
        // Notified but hasn't called yet.
        _promptCallSecretary();
      case 'called':
        // Called but hasn't uploaded proof yet.
        _promptUploadProof();
      default:
        // proof_ready / deployed / completed / disregarded — nothing to do.
        break;
    }
  }

  // ── Exit / cancel ─────────────────────────────────────────────────────
  /// Lets the reporter leave. With a live report this is a real cancellation
  /// — the barangay is told explicitly rather than being left watching a
  /// location that silently stops moving, which is strictly better for them.
  Future<void> _onExitPressed(NonResidentSessionModel session) async {
    // Once responders are deployed, cancelling in-app is blocked. Someone is
    // physically travelling; silently closing the report at that moment is
    // the worst case — either the barangay keeps driving to an incident the
    // app has closed, or a real emergency is stood down by a panicked tap.
    // They can still stand down, but a human has to hear it.
    if (!session.canCancel && !session.isClosed) {
      HapticFeedback.heavyImpact();

      // Say WHY it's locked. "Responders are on their way" would be untrue
      // when the lock is only because someone has been assigned or proof is
      // under review, and a reporter told something false about their own
      // emergency loses trust in everything else the screen says.
      final (title, message) = session.isDeployed
          ? (
              'Responders are on their way',
              'This report can no longer be cancelled from the app because '
                  'help is already travelling to you. If this is a false '
                  'alarm, call the barangay so they can stand down.'
            )
          : session.isProofReady
              ? (
                  'The barangay is reviewing your report',
                  'Your evidence is being checked right now, so this report '
                      'can no longer be cancelled from the app. If this is a '
                      'false alarm, call the barangay directly.'
                )
              : (
                  'An official has been assigned',
                  'A barangay official has already been given this report and '
                      'may be on their way. It can no longer be cancelled from '
                      'the app — please call the barangay instead.'
                );

      await showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.5),
        builder: (ctx) => _FrostedNotice(
          icon: Icons.lock_rounded,
          iconColor: AppColors.warning,
          title: title,
          message: message,
          actionLabel: context.s.callBarangay,
          actionColor: AppColors.success,
          onAction: () async {
            Navigator.pop(ctx);
            await _callBarangay();
          },
          secondaryLabel: 'Close',
          onSecondary: () => Navigator.pop(ctx),
        ),
      );
      return;
    }

    final inFlight = session.isInFlight;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => _FrostedNotice(
        icon: inFlight
            ? Icons.cancel_schedule_send_rounded
            : Icons.logout_rounded,
        iconColor: inFlight ? AppColors.error : AppColors.textSecondary,
        title: inFlight ? 'Cancel your report?' : 'Sign out?',
        message: inFlight
            ? 'The barangay will be told you cancelled and will stop '
              'responding. Only do this if you no longer need help, or if '
              'you reported by mistake.'
            : 'You can sign in again with your contact number at any time.',
        actionLabel: inFlight ? 'Yes, cancel my report' : 'Sign out',
        actionColor: inFlight ? AppColors.error : null,
        onAction: () => Navigator.pop(ctx, true),
        secondaryLabel: inFlight ? 'Keep my report active' : 'Stay',
        onSecondary: () => Navigator.pop(ctx, false),
      ),
    );

    if (confirmed != true || !mounted) return;

    final provider = context.read<NonResidentProvider>();
    HapticFeedback.heavyImpact();

    if (inFlight) {
      final ok = await provider.setStatus(
        'disregarded',
        disregardReason: 'Cancelled by the reporter',
      );
      if (!mounted) return;
      if (!ok) {
        showErrorSnackbar(
            context, provider.error ?? 'Could not cancel your report.');
        provider.clearError();
        return;
      }
    }

    // force: the logout lock has served its purpose — this is a deliberate,
    // recorded cancellation, not someone vanishing mid-report.
    await provider.signOut(force: true);
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  Future<void> _onReportPressed(NonResidentSessionModel session) async {
    HapticFeedback.mediumImpact();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      // Deliberately heavy. This dispatches real people to a real place, and
      // it is the reporter's ONE report for 7 days — the weight of that has
      // to land before they tap, not after.
      builder: (ctx) => _FrostedNotice(
        icon: Icons.warning_amber_rounded,
        iconColor: AppColors.error,
        title: context.s.sendThisReport,
        message:
            'The barangay will be alerted immediately and real responders may '
            'be dispatched to your location.\n\n'
            '• This is your ONLY report for the next 7 days.\n'
            '• Once responders are on their way, you can no longer cancel it '
            'from the app.\n'
            '• Filing a false report is a punishable offence.\n\n'
            'Only continue if this is a genuine emergency.',
        actionLabel: 'Yes, this is an emergency',
        actionColor: AppColors.error,
        onAction: () => Navigator.pop(ctx, true),
        secondaryLabel: 'Go back',
        onSecondary: () => Navigator.pop(ctx, false),
      ),
    );

    if (confirmed != true || !mounted) return;

    final provider = context.read<NonResidentProvider>();
    final ok = await provider.markReported();
    if (!mounted) return;

    if (!ok) {
      HapticFeedback.heavyImpact();
      showErrorSnackbar(
          context, provider.error ?? 'Could not send your report.');
      provider.clearError();
      return;
    }

    HapticFeedback.lightImpact();
    _promptCallSecretary();
  }

  /// After notifying the secretary, the non-resident calls them once.
  void _promptCallSecretary() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => _FrostedNotice(
        icon: Icons.phone_in_talk_rounded,
        iconColor: AppColors.success,
        title: context.s.barangayNotified,
        message:
            'Now call the barangay secretary so they can confirm your '
            'emergency and dispatch help.',
        actionLabel: context.s.callBarangay,
        actionColor: AppColors.success,
        onAction: () async {
          Navigator.pop(ctx);
          await _callBarangay();
        },
        // Being out of load must never stall a real emergency — the barangay
        // was already notified when the report was filed.
        secondaryLabel: context.s.cannotCall,
        onSecondary: () async {
          Navigator.pop(ctx);
          await _onCannotCall();
        },
      ),
    );
  }

  /// Dials an arbitrary number (the assigned official). Separate from
  /// [_callBarangay], which also advances the report's status.
  Future<void> _callNumber(String? number) async {
    if (number == null || number.isEmpty) {
      showErrorSnackbar(context, 'No contact number available.');
      return;
    }
    HapticFeedback.mediumImpact();
    try {
      await launchUrl(Uri.parse('tel:$number'));
    } catch (_) {
      if (mounted) showErrorSnackbar(context, 'Could not open the dialer.');
    }
  }

  Future<void> _callBarangay() async {
    // TODO(§11): use the barangay's own secretary hotline once per-barangay
    // contact numbers exist. This falls back to the shared emergency line.
    final uri = Uri.parse('tel:${AppConfig.emergencyHotline}');
    final provider = context.read<NonResidentProvider>();

    try {
      await launchUrl(uri);
    } catch (_) {
      // Previously this fell through and marked the session 'called' anyway,
      // so a reporter who couldn't dial was logged as having called — leaving
      // the Secretary waiting for a call that would never come.
      if (!mounted) return;
      await provider.markCallFailed(reason: 'dialer_failed');
      if (!mounted) return;
      showErrorSnackbar(
          context, 'Could not open the dialer. The barangay has been told.');
      _promptUploadProof();
      return;
    }

    if (!mounted) return;
    // Android never reports whether a call actually connected, so this is the
    // reporter's word for it — hence the explicit "I couldn't call" escape
    // hatch on the prompt.
    await provider.setStatus('called');
    if (mounted) _promptUploadProof();
  }

  /// The reporter says they couldn't get through — no load, no signal.
  ///
  /// The report still stands: the barangay was notified at the `reported`
  /// stage, so the call is confirmation rather than the trigger. Being out of
  /// load must never stall a real emergency.
  Future<void> _onCannotCall() async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => _CannotCallSheet(
        onPick: (r) => Navigator.pop(ctx, r),
      ),
    );
    if (reason == null || !mounted) return;

    await context.read<NonResidentProvider>().markCallFailed(reason: reason);
    if (!mounted) return;

    HapticFeedback.lightImpact();
    showSuccessSnackbar(
      context,
      'The barangay has been told you cannot call. They will contact you.',
    );
    _promptUploadProof();
  }

  /// Proof is mandatory before the barangay will deploy anyone.
  void _promptUploadProof() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => _FrostedNotice(
        icon: Icons.add_a_photo_rounded,
        iconColor: AppColors.primary,
        title: context.s.uploadProof,
        message:
            'Take a photo or video of the emergency. The barangay reviews it '
            'before sending anyone — reports without proof are disregarded.',
        actionLabel: 'Open camera',
        onAction: () {
          Navigator.pop(ctx);
          _captureAndUploadProof();
        },
      ),
    );
  }

  /// Camera-only capture, matching the resident report form's policy of not
  /// allowing gallery uploads for evidence.
  Future<void> _captureAndUploadProof() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;

      final ok = await context
          .read<NonResidentProvider>()
          .uploadProof(File(picked.path));
      if (!mounted) return;

      if (ok) {
        HapticFeedback.lightImpact();
        showSuccessSnackbar(
            context, 'Proof sent. The barangay is reviewing it now.');
      } else {
        HapticFeedback.heavyImpact();
        final provider = context.read<NonResidentProvider>();
        showErrorSnackbar(
            context, provider.error ?? 'Could not upload your proof.');
        provider.clearError();
      }
    } catch (e) {
      if (!mounted) return;
      showErrorSnackbar(context, 'Could not open the camera.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NonResidentProvider>();
    final session = provider.session;
    final responders = provider.responders;
    final assignedOfficial = provider.assignedOfficial;

    // The barangay changed the status — tell the reporter. Deferred to after
    // the frame so showing a sheet doesn't fire during build.
    final announcement = provider.pendingStatusAnnouncement;
    if (announcement != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _announceStatus(announcement);
      });
    }

    if (session == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Keep the camera on the reporter as they move, unless they've panned
    // away themselves.
    if (session.hasLocation && (_followMe || !_hasCenteredOnce)) {
      _hasCenteredOnce = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mapController.move(
            LatLng(session.lastLat!, session.lastLng!),
            _mapController.camera.zoom,
          );
        }
      });
    }

    final center = session.hasLocation
        ? LatLng(session.lastLat!, session.lastLng!)
        : const LatLng(AppConfig.defaultLatitude, AppConfig.defaultLongitude);

    return PopScope(
      // Logout/back is locked while a report is live.
      canPop: !session.isInFlight,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          HapticFeedback.heavyImpact();
          _showReturnWarning();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 16.0,
                maxZoom: 18.0,
                minZoom: 11.0,
                // Panning by hand releases the camera so the user can look
                // around; the recenter button re-arms follow mode.
                onPointerDown: (_, __) {
                  if (_followMe) setState(() => _followMe = false);
                },
              ),
              children: [
                const AppTileLayer(),
                const AppMapAttribution(),
                // Dashed line to the nearest responder, so "how far is help"
                // is answerable at a glance.
                if (session.hasLocation && responders.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [
                          LatLng(session.lastLat!, session.lastLng!),
                          LatLng(responders.first.lat, responders.first.lng),
                        ],
                        strokeWidth: 3,
                        color: AppColors.success.withValues(alpha: 0.55),
                        isDotted: true,
                      ),
                    ],
                  ),

                // Officials on their way
                if (responders.isNotEmpty)
                  MarkerLayer(
                    markers: [
                      for (final r in responders)
                        Marker(
                          key: ValueKey('responder_${r.id}'),
                          point: LatLng(r.lat, r.lng),
                          width: 46,
                          height: 46,
                          child: _ResponderMarker(responder: r),
                        ),
                    ],
                  ),

                if (session.hasLocation)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(session.lastLat!, session.lastLng!),
                        width: 34,
                        height: 34,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.28),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppColors.primary, width: 2.5),
                          ),
                          child: const Icon(Icons.my_location_rounded,
                              size: 17, color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
              ],
            ),

            // Status header + exit control
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Expanded(child: _StatusBanner(session: session)),
                        const SizedBox(width: 8),
                        _ExitButton(
                          session: session,
                          onPressed: () => _onExitPressed(session),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Kept available inside the session, not just on the login
                    // screen before it: this is the screen someone reads while
                    // an emergency is unfolding, and it is the worst possible
                    // moment to be stuck in a language you don't read.
                    const LanguageToggle(),
                  ],
                ),
              ),
            ),

            // ── Everything that sits along the bottom edge ──────────────
            //
            // One bottom-anchored Column rather than four `Positioned`
            // widgets with hand-tuned `bottom:` offsets.
            //
            // The offsets were 102 / 132 / 176 / 186, chosen to clear each
            // other at the text size they were written at. On a real phone
            // they did not: with an official assigned and no responder yet,
            // the banner sat at bottom 102 and the recenter button at bottom
            // 132 — and because the button is right-aligned, it landed
            // directly on the banner's Call button. Reported from a physical
            // device 2026-08-25.
            //
            // Any fixed offset is guesswork here, because the banner's height
            // depends on the official's name and position wrapping, and on
            // the phone's font scale setting. A Column cannot overlap itself,
            // so the class of bug goes away rather than the one instance of
            // it being re-tuned.
            //
            // The gaps between children stay transparent to touch — Padding
            // and SizedBox do not answer hit tests — so the map is still
            // pannable between the cards.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Recenter — above the cards, never on top of them.
                    Padding(
                      padding: const EdgeInsets.only(right: 16, bottom: 12),
                      child: FloatingActionButton.small(
                        heroTag: 'nr_recenter',
                        backgroundColor: Colors.white,
                        foregroundColor: _followMe
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        tooltip:
                            _followMe ? 'Following you' : 'Center on me',
                        onPressed: () {
                          setState(() => _followMe = true);
                          _recenter(session);
                        },
                        child: Icon(_followMe
                            ? Icons.my_location_rounded
                            : Icons.location_searching_rounded),
                      ),
                    ),

                    // Who is coming — named, with a direct line to them.
                    // Knowing a person is assigned is reassurance; being able
                    // to ring them is the difference between waiting and
                    // being able to act.
                    if (assignedOfficial != null)
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(20, 0, 20, 10),
                        child: _AssignedOfficialBanner(
                          official: assignedOfficial,
                          onCall: () => _callNumber(assignedOfficial.phone),
                        ),
                      ),

                    // Responder en route
                    if (responders.isNotEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(20, 0, 20, 10),
                        child: _ResponderBanner(
                          responder: responders.first,
                          distanceMeters: session.hasLocation
                              ? _locationService.distanceBetween(
                                  session.lastLat!,
                                  session.lastLng!,
                                  responders.first.lat,
                                  responders.first.lng,
                                )
                              : null,
                        ),
                      ),

                    // Report button — always last, always reachable.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                      child: _ReportButton(
                        session: session,
                        onPressed: () => _onPrimaryAction(session),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status banner ───────────────────────────────────────────────────────────
class _StatusBanner extends StatelessWidget {
  final NonResidentSessionModel session;
  const _StatusBanner({required this.session});

  @override
  Widget build(BuildContext context) {
    final t = context.s;
    final (label, color, icon) = switch (session.status) {
      'reported' => (t.nrBannerNotified, AppColors.warning,
          Icons.campaign_rounded),
      'called' => (t.nrBannerUploadProof, AppColors.primary,
          Icons.add_a_photo_rounded),
      'proof_ready' => (t.nrBannerReviewing, AppColors.primary,
          Icons.hourglass_top_rounded),
      'deployed' => (t.helpOnTheWay, AppColors.success,
          Icons.local_shipping_rounded),
      'completed' => (t.nrBannerResolved, AppColors.success,
          Icons.check_circle_rounded),
      'disregarded' => (t.nrBannerDisregarded, AppColors.error,
          Icons.cancel_rounded),
      _ => (
          session.barangayName != null
              ? t.connectedTo(session.barangayName!)
              : t.locatingBarangay,
          AppColors.textSecondary,
          Icons.location_on_rounded
        ),
    };

    // Leaving the covered area overrides everything else — the barangay may
    // not be able to reach them, and they need to know that immediately.
    if (session.isOutsideCoverage && !session.isClosed) {
      return _bannerShell(
        icon: Icons.wrong_location_rounded,
        color: AppColors.warning,
        label: t.nrOutsideCoverage,
        showPulse: false,
      );
    }

    return _bannerShell(
      icon: icon,
      color: color,
      label: label,
      showPulse: session.isInFlight && session.hasLocation,
    );
  }

  Widget _bannerShell({
    required IconData icon,
    required Color color,
    required String label,
    required bool showPulse,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: AppText(
                label,
                key: ValueKey(label),
                style: AppTextStyles.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          if (showPulse) const _LivePulse(),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 320.ms)
        .slideY(begin: -0.3, end: 0, curve: Curves.easeOutBack);
  }
}

// ── "I can't call" reason picker ────────────────────────────────────────────
/// Asks why the reporter couldn't call, so the Secretary knows what they're
/// dealing with — no load means "phone them", no signal means "they may be
/// unreachable entirely".
class _CannotCallSheet extends StatelessWidget {
  final void Function(String reason) onPick;

  const _CannotCallSheet({required this.onPick});

  // Built per-call rather than held static: the labels change with language,
  // and `value` stays the canonical code sent to the backend.
  static List<({String value, String label, IconData icon})> _reasonsFor(
          AppStrings t) =>
      [
        (
          value: 'no_credits',
          label: t.reasonNoLoad,
          icon: Icons.money_off_rounded
        ),
        (
          value: 'no_signal',
          label: t.reasonNoSignal,
          icon: Icons.signal_cellular_off_rounded
        ),
        (
          value: 'other',
          label: t.reasonOther,
          icon: Icons.more_horiz_rounded
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.of(context).padding.bottom + 20),
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
          const SizedBox(height: 20),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.phone_disabled_rounded,
                color: AppColors.warning, size: 28),
          )
              .animate()
              .scale(
                  begin: const Offset(0.5, 0.5),
                  end: const Offset(1, 1),
                  duration: 460.ms,
                  curve: Curves.easeOutBack),
          const SizedBox(height: 16),
          AppText("Why can't you call?",
              textAlign: TextAlign.center, style: AppTextStyles.heading3),
          const SizedBox(height: 8),
          Text(
            'Your report still stands — the barangay was already alerted. '
            'This just tells them to contact you instead.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 18),
          for (final r in _reasonsFor(context.s))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: Icon(r.icon, size: 18),
                  label: Align(
                    alignment: Alignment.centerLeft,
                    child: AppText(r.label),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    alignment: Alignment.centerLeft,
                  ),
                  onPressed: () => onPick(r.value),
                ),
              ),
            ),
        ],
      ),
    ).animate().slideY(
        begin: 0.2, end: 0, duration: 380.ms, curve: Curves.easeOutBack);
  }
}

// ── Responder marker ────────────────────────────────────────────────────────
/// A barangay official who is sharing their position. Green and pulsing so
/// the reporter's eye finds "help" instantly against their own blue dot.
class _ResponderMarker extends StatefulWidget {
  final ResponderLocation responder;
  const _ResponderMarker({required this.responder});

  @override
  State<_ResponderMarker> createState() => _ResponderMarkerState();
}

class _ResponderMarkerState extends State<_ResponderMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            // Expanding ring — reads as "moving/active" rather than a static pin
            Opacity(
              opacity: (1 - t) * 0.5,
              child: Container(
                width: 22 + t * 24,
                height: 22 + t * 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: AppColors.success, width: 2),
                ),
              ),
            ),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.success.withValues(alpha: 0.45),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(Icons.local_police_rounded,
                  size: 15, color: Colors.white),
            ),
          ],
        );
      },
    );
  }
}

/// Tells the reporter help is en route and how far away it is — the whole
/// point of officials broadcasting at all.
class _ResponderBanner extends StatelessWidget {
  final ResponderLocation responder;
  final double? distanceMeters;

  const _ResponderBanner({required this.responder, this.distanceMeters});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.success,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.success.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.local_police_rounded,
              color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  responder.fullName,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                AppText(
                  distanceMeters != null
                      ? '${formatDistance(distanceMeters!)} away — on the way to you'
                      : 'On the way to you',
                  style: AppTextStyles.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 340.ms)
        .slideY(begin: 0.4, end: 0, curve: Curves.easeOutBack);
  }
}

// ── Exit / cancel button ────────────────────────────────────────────────────
/// Deliberately small and neutral so it never competes with the report
/// button, but always reachable — a reporter must never be trapped in the
/// flow with no way out.
class _ExitButton extends StatelessWidget {
  final NonResidentSessionModel session;
  final VoidCallback onPressed;

  const _ExitButton({required this.session, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final inFlight = session.isInFlight;
    // Locked once responders are deployed — the icon says so before the user
    // taps, rather than letting them expect a cancel that won't come.
    final locked = !session.canCancel && !session.isClosed;

    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Icon(
            locked
                ? Icons.lock_rounded
                : inFlight
                    ? Icons.close_rounded
                    : Icons.logout_rounded,
            size: 20,
            color: locked
                ? AppColors.textTertiary
                : inFlight
                    ? AppColors.error
                    : AppColors.textSecondary,
          ),
        ),
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 320.ms).scale(
        begin: const Offset(0.7, 0.7),
        end: const Offset(1, 1),
        curve: Curves.easeOutBack);
  }
}

/// Small pulsing dot showing location is actively streaming.
class _LivePulse extends StatefulWidget {
  const _LivePulse();

  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_ctrl),
      child: Container(
        width: 9,
        height: 9,
        decoration: const BoxDecoration(
          color: AppColors.success,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ── Report button ───────────────────────────────────────────────────────────
class _ReportButton extends StatelessWidget {
  final NonResidentSessionModel session;
  final VoidCallback onPressed;

  const _ReportButton({required this.session, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    // The button always shows the next step in the flow. This is what makes
    // the flow recoverable — if a prompt sheet gets dismissed, tapping here
    // resumes it instead of leaving the user stranded.
    final t = context.s;
    final (label, icon, enabled, color) = switch (session.status) {
      'active' when !session.hasLocation => (
          t.nrWaitingLocation,
          Icons.location_searching_rounded,
          false,
          AppColors.textSecondary
        ),
      'active' => (
          t.reportEmergency,
          Icons.campaign_rounded,
          true,
          AppColors.error
        ),
      'reported' => (
          t.nrCallBarangayCaps,
          Icons.phone_in_talk_rounded,
          true,
          AppColors.success
        ),
      'called' => (
          t.nrUploadProofCaps,
          Icons.add_a_photo_rounded,
          true,
          AppColors.primary
        ),
      'proof_ready' => (
          t.nrReviewing,
          Icons.hourglass_top_rounded,
          false,
          AppColors.primary
        ),
      'deployed' => (
          t.helpOnTheWay,
          Icons.local_shipping_rounded,
          false,
          AppColors.success
        ),
      'completed' => (
          t.nrBannerResolved,
          Icons.check_circle_rounded,
          false,
          AppColors.success
        ),
      'disregarded' => (
          t.nrBannerDisregarded,
          Icons.cancel_rounded,
          false,
          AppColors.textSecondary
        ),
      _ => (
          t.nrAlreadyFiled,
          Icons.lock_clock_rounded,
          false,
          AppColors.textSecondary
        ),
    };

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 260),
      opacity: enabled ? 1.0 : 0.6,
      child: SizedBox(
        height: 62,
        child: ElevatedButton.icon(
          onPressed: enabled ? onPressed : null,
          icon: Icon(icon),
          label: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: AppText(
              label,
              key: ValueKey(label),
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.textSecondary,
            disabledForegroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            elevation: 6,
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(delay: 200.ms, duration: 360.ms)
        .slideY(begin: 0.4, end: 0, curve: Curves.easeOutBack);
  }
}

// ── Frosted notice sheet ────────────────────────────────────────────────────
class _FrostedNotice extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final String actionLabel;
  final Color? actionColor;
  final VoidCallback onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const _FrostedNotice({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.actionColor,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, MediaQuery.of(context).padding.bottom + 20),
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
          const SizedBox(height: 22),
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 30),
          )
              .animate()
              .scale(
                  begin: const Offset(0.5, 0.5),
                  end: const Offset(1, 1),
                  duration: 480.ms,
                  curve: Curves.easeOutBack),
          const SizedBox(height: 16),
          AppText(title,
              textAlign: TextAlign.center, style: AppTextStyles.heading3),
          const SizedBox(height: 8),
          AppText(message,
              textAlign: TextAlign.center, style: AppTextStyles.bodySmall),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: actionColor ?? AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: AppText(actionLabel,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
          if (secondaryLabel != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: TextButton(
                onPressed: onSecondary,
                child: AppText(secondaryLabel!),
              ),
            ),
          ],
        ],
      ),
    ).animate().slideY(
        begin: 0.18, end: 0, duration: 380.ms, curve: Curves.easeOutBack);
  }
}


// ── Assigned official ───────────────────────────────────────────────────────
/// Names the official handling this report and gives the reporter a direct
/// line to them.
///
/// "Help is coming" is reassuring; "Juan Dela Cruz, Barangay Tanod, tap to call"
/// is actionable — the reporter can describe where exactly they are, or say
/// the situation changed.
class _AssignedOfficialBanner extends StatelessWidget {
  final ResponderContact official;
  final VoidCallback onCall;

  const _AssignedOfficialBanner({required this.official, required this.onCall});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(positionIcon(official.position),
                size: 19, color: AppColors.primary),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.s.assignedToYourReport,
                    style: AppTextStyles.caption),
                AppText(
                  official.fullName,
                  style: AppTextStyles.bodySmall
                      .copyWith(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
                if (official.position != null)
                  AppText(UserPosition.label(official.position),
                      style: AppTextStyles.caption),
              ],
            ),
          ),
          if (official.phone != null && official.phone!.isNotEmpty)
            Material(
              color: AppColors.success,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onCall,
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.phone_rounded,
                      size: 19, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 340.ms)
        .slideY(begin: 0.3, end: 0, curve: Curves.easeOutBack);
  }
}
