import '../../utils/live_refresh.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import '../../l10n/app_strings.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/id_verification_service.dart';
import '../../widgets/language_toggle.dart';
import '../../widgets/app_text.dart';

class PendingVerificationScreen extends StatefulWidget {
  const PendingVerificationScreen({super.key});

  @override
  State<PendingVerificationScreen> createState() =>
      _PendingVerificationScreenState();
}

class _PendingVerificationScreenState extends State<PendingVerificationScreen>
    with TickerProviderStateMixin, LiveRefreshMixin {
  // Pulsing ring — slow outward signal pulse from shield (like radio transmission)
  late final AnimationController _ring1Ctrl;
  late final AnimationController _ring2Ctrl;
  late final AnimationController _ring3Ctrl;
  late final AnimationController _shieldCtrl;

  /// Re-reads the account so approval lands on its own.
  ///
  /// This screen is the one a resident sits on *waiting* for an official to
  /// act. It previously only refreshed when they pulled to refresh or
  /// submitted another photo — so someone whose ID had already been approved
  /// kept staring at "waiting for verification" until they signed out and back
  /// in. Checked more often than the default because that wait is the entire
  /// purpose of the screen.
  @override
  Duration get livePollInterval => const Duration(seconds: 10);

  @override
  Future<void> onLiveRefresh() =>
      context.read<AuthProvider>().refreshProfile();

  @override
  void initState() {
    super.initState();
    startLiveRefresh();

    // Shield entrance
    _shieldCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    )..forward();

    // Three offset-staggered rings pulse outward and fade
    _ring1Ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _ring2Ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _ring3Ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _ring2Ctrl.repeat();
    });
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) _ring3Ctrl.repeat();
    });
  }

  @override
  void dispose() {
    _ring1Ctrl.dispose();
    _ring2Ctrl.dispose();
    _ring3Ctrl.dispose();
    _shieldCtrl.dispose();
    super.dispose();
  }

  Widget _buildRing(AnimationController ctrl, Color color) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        final t = Curves.easeOut.transform(ctrl.value);
        final size = 88.0 + t * 80.0;
        final opacity = (1.0 - t).clamp(0.0, 1.0) * 0.35;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha: opacity),
              width: 1.5,
            ),
          ),
        );
      },
    );
  }

  /// Which slot is mid-upload, so only that row shows a spinner. A single
  /// screen-wide flag would freeze all three rows for one upload.
  IdSlot? _uploadingSlot;

  /// §8 - replaces the trip to the barangay hall.
  ///
  /// Camera first: a photo taken now of the ID in the person's hand is harder
  /// to pass off as someone else's than a file picked from the gallery. The
  /// gallery stays available for the ID itself because plenty of people
  /// already keep a photo of theirs, and refusing it would send them back to
  /// the hall - the exact trip this feature exists to remove.
  ///
  /// **The selfie is camera-only**, and that exception is the point of the
  /// slot: it exists to show the holder with the document *now*. A selfie
  /// chosen from the gallery could be any photograph of anyone holding
  /// anything, which would make the check theatre.
  Future<void> _pickAndSubmit(IdSlot slot, ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
        preferredCameraDevice:
            slot == IdSlot.selfie ? CameraDevice.front : CameraDevice.rear,
      );
      // The camera runs in a separate activity; on a low-memory phone Android
      // may tear this one down behind it.
      if (picked == null || !mounted) return;

      setState(() => _uploadingSlot = slot);
      await IdVerificationService().submitIdPhoto(File(picked.path), slot);

      // Refresh so the row flips to the submitted state without a restart.
      if (mounted) await context.read<AuthProvider>().refreshProfile();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showSuccessSnackbar(context, context.s.idPhotoSaved);
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not upload: $e');
    } finally {
      if (mounted) setState(() => _uploadingSlot = null);
    }
  }

  void _showSourceSheet(IdSlot slot) {
    // See _pickAndSubmit: the selfie has no gallery path, so there is nothing
    // to choose between and the sheet would be a pointless extra tap.
    if (slot == IdSlot.selfie) {
      _pickAndSubmit(slot, ImageSource.camera);
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
            20, 18, 20, MediaQuery.of(ctx).padding.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppText(_slotTitle(ctx.s, slot), style: AppTextStyles.heading3),
            const SizedBox(height: 14),
            ListTile(
              leading:
                  const Icon(Icons.camera_alt_rounded, color: AppColors.primary),
              title: AppText(ctx.s.takeAPhoto),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSubmit(slot, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.textSecondary),
              title: AppText(ctx.s.chooseFromGallery),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSubmit(slot, ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _slotTitle(AppStrings t, IdSlot slot) => switch (slot) {
        IdSlot.front => t.idFrontTitle,
        IdSlot.back => t.idBackTitle,
        IdSlot.selfie => t.idSelfieTitle,
      };

  String _slotHint(AppStrings t, IdSlot slot) => switch (slot) {
        IdSlot.front => t.idFrontHint,
        IdSlot.back => t.idBackHint,
        IdSlot.selfie => t.idSelfieHint,
      };

  String? _slotValue(UserModel? u, IdSlot slot) => switch (slot) {
        IdSlot.front => u?.idPhotoUrl,
        IdSlot.back => u?.idBackUrl,
        IdSlot.selfie => u?.idSelfieUrl,
      };

  /// Which document is being presented.
  ///
  /// Asked before the camera opens because the answer changes what else is
  /// required - a school ID identifies a minor, and RA 10173 needs a
  /// guardian's consent to process a minor's data.
  void _showIdTypeSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
            20, 18, 20, MediaQuery.of(ctx).padding.bottom + 12),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(ctx.s.selectIdType, style: AppTextStyles.heading3),
              const SizedBox(height: 10),
              ...IdType.all.map(
                (type) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    type == IdType.schoolId
                        ? Icons.school_rounded
                        : Icons.badge_outlined,
                    color: AppColors.primary,
                  ),
                  title: AppText(IdType.label(type)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await IdVerificationService().setIdType(type);
                    if (!mounted) return;
                    await context.read<AuthProvider>().refreshProfile();
                    if (mounted) setState(() {});
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One row per photograph, plus the document-type picker above them.
  Widget _buildIdUpload() {
    final t = context.s;
    final user = context.watch<AuthProvider>().user;
    final done = [IdSlot.front, IdSlot.back, IdSlot.selfie]
        .where((slot) => _slotValue(user, slot) != null)
        .length;
    final complete = done == 3;
    final accent = complete ? AppColors.success : AppColors.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                complete ? Icons.check_circle_rounded : Icons.badge_outlined,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppText(
                  complete ? t.idAllSubmitted : t.uploadIdTitle,
                  style: AppTextStyles.body
                      .copyWith(fontWeight: FontWeight.w700, color: accent),
                ),
              ),
              // Progress is shown as a count rather than a bar: three items is
              // too few for a bar to mean anything, and "2 of 3" says exactly
              // what is left.
              AppText('$done ${t.ofThree}',
                  style: AppTextStyles.caption.copyWith(color: accent)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            complete ? t.idAllSubmittedNote : t.uploadIdSubtitle,
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 14),

          // Document type. Sits above the photos because it changes what the
          // photos need to show.
          InkWell(
            onTap: _showIdTypeSheet,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                    color: AppColors.textTertiary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.article_outlined,
                      size: 17, color: AppColors.textSecondary),
                  const SizedBox(width: 9),
                  Expanded(
                    child: AppText(
                      user?.idType == null
                          ? t.selectIdType
                          : IdType.label(user!.idType),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: user?.idType == null
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                        fontWeight: user?.idType == null
                            ? FontWeight.w400
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(Icons.expand_more_rounded,
                      size: 18, color: AppColors.textTertiary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          for (final slot in IdSlot.values) ...[
            _buildSlotRow(t, slot, _slotValue(user, slot) != null),
            const SizedBox(height: 8),
          ],

          const SizedBox(height: 2),
          Row(
            children: [
              const Icon(Icons.lock_outline_rounded,
                  size: 12, color: AppColors.textTertiary),
              const SizedBox(width: 5),
              Expanded(
                child: AppText(t.idPrivacyNote, style: AppTextStyles.caption),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSlotRow(AppStrings t, IdSlot slot, bool submitted) {
    final busy = _uploadingSlot == slot;
    final color = submitted ? AppColors.success : AppColors.primary;

    return InkWell(
      onTap: busy ? null : () => _showSourceSheet(slot),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: busy
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : Icon(
                      submitted
                          ? Icons.check_circle_rounded
                          : switch (slot) {
                              IdSlot.front => Icons.badge_outlined,
                              IdSlot.back => Icons.flip_to_back_rounded,
                              IdSlot.selfie => Icons.person_pin_rounded,
                            },
                      size: 20,
                      color: color,
                    ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _slotTitle(t, slot),
                    style: AppTextStyles.bodySmall
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    busy ? t.idUploading : _slotHint(t, slot),
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
            if (!busy)
              Text(
                submitted ? t.retakeId : t.addPhoto,
                style: AppTextStyles.caption
                    .copyWith(color: color, fontWeight: FontWeight.w700),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 12),
              // Unverified residents are parked here and cannot reach the
              // Profile settings, so this is their only way to switch.
              const Align(
                alignment: Alignment.centerRight,
                child: LanguageToggle(),
              ),
              const SizedBox(height: 28),

              // ── Shield + pulsing rings ────────────────────────────────────
              SizedBox(
                width: 200,
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _buildRing(_ring3Ctrl, AppColors.primary),
                    _buildRing(_ring2Ctrl, AppColors.primary),
                    _buildRing(_ring1Ctrl, AppColors.primary),
                    ScaleTransition(
                      scale: CurvedAnimation(
                        parent: _shieldCtrl,
                        curve: Curves.easeOutBack,
                      ),
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.shield_rounded,
                          size: 48,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // ── Heading ──────────────────────────────────────────────────
              AppText(
                context.s.verificationHeading,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.8,
                  height: 1.15,
                ),
                textAlign: TextAlign.center,
              )
                  .animate(delay: 300.ms)
                  .fadeIn(duration: 360.ms)
                  .slideY(begin: 0.18, end: 0, duration: 380.ms, curve: Curves.easeOutCubic),

              const SizedBox(height: 14),

              Text(
                context.s.verificationBlurb,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              )
                  .animate(delay: 420.ms)
                  .fadeIn(duration: 340.ms),

              const SizedBox(height: 40),

              // ── Steps card ───────────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.s.whatToDoNext,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildStep(
                      number: '1',
                      title: context.s.stepUploadId,
                      subtitle: context.s.stepUploadIdDesc,
                      delay: 500,
                    ),
                    _buildStep(
                      number: '2',
                      title: context.s.stepOfficialChecks,
                      subtitle: context.s.stepOfficialChecksDesc,
                      delay: 600,
                    ),
                    _buildStep(
                      number: '3',
                      title: context.s.youGetNotified,
                      subtitle:
                          'Once verified you will receive a notification and can file reports.',
                      delay: 700,
                      isLast: true,
                    ),
                  ],
                ),
              )
                  .animate(delay: 480.ms)
                  .fadeIn(duration: 360.ms)
                  .slideY(begin: 0.12, end: 0, duration: 380.ms, curve: Curves.easeOutCubic),

              const SizedBox(height: 22),

              // §8 - the action comes before the explanation. A resident who
              // already knows what to do should not have to read three steps
              // to find the button.
              _buildIdUpload()
                  .animate(delay: 520.ms)
                  .fadeIn(duration: 320.ms)
                  .slideY(begin: 0.10, end: 0, curve: Curves.easeOutCubic),

              const SizedBox(height: 20),

              // ── Info chip ────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.30),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 16,
                      color: Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.s.reviewedManuallyNote,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ],
                ),
              )
                  .animate(delay: 620.ms)
                  .fadeIn(duration: 300.ms),

              const SizedBox(height: 36),

              // ── Back to login button ─────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: Text(context.s.backToLogin),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
                  .animate(delay: 720.ms)
                  .fadeIn(duration: 300.ms)
                  .slideY(begin: 0.1, end: 0, duration: 320.ms, curve: Curves.easeOutBack),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep({
    required String number,
    required String title,
    required String subtitle,
    required int delay,
    bool isLast = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: AppText(
                number,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 36,
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                AppText(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                AppText(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                if (!isLast) const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ],
    ).animate(delay: Duration(milliseconds: delay)).fadeIn(duration: 280.ms).slideX(
          begin: 0.08,
          end: 0,
          duration: 300.ms,
          curve: Curves.easeOutCubic,
        );
  }
}
