import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_strings.dart';
import '../utils/constants.dart';
import '../utils/lgu_routing.dart';
import 'app_text.dart';

/// Tells a reporter their incident is beyond the barangay and puts the right
/// number one tap away.
///
/// Shown in place of selecting the category, so the person never fills in a
/// form for something that would not reach anyone able to act on it. See
/// [LguRouting] for the rule.
///
/// ## What the design is for
///
/// This is read by someone in the worst minutes of their day, so everything is
/// arranged around one action. The agency colour and icon say *what kind* of
/// help this is before a word is read; the call button is the largest thing on
/// screen and breathes gently so the eye lands on it; the number is printed on
/// it so it can be read aloud or dialled by hand if the call cannot be placed.
///
/// Motion is there to direct attention, not decorate: the icon arrives first,
/// the ripple behind it says "urgent", the text follows, the buttons last. With
/// the system's reduce-motion setting on, none of it plays.
Future<bool?> showLguReferralSheet(
  BuildContext context, {
  required String category,
  required LguReferral referral,
}) {
  HapticFeedback.mediumImpact();
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.62),
    builder: (_) => _LguReferralDialog(category: category, referral: referral),
  );
}

/// What each agency looks like. Colour first: a flame-orange card and a
/// police-blue one read as different kinds of help before any text does.
({Color from, Color to, IconData icon}) _styleFor(LguAgency agency) =>
    switch (agency) {
      LguAgency.fire => (
          from: const Color(0xFFFF7A3D),
          to: const Color(0xFFDC2626),
          icon: Icons.local_fire_department_rounded,
        ),
      LguAgency.police => (
          from: const Color(0xFF3B82F6),
          to: const Color(0xFF1E40AF),
          icon: Icons.local_police_rounded,
        ),
      LguAgency.medical => (
          from: const Color(0xFFF43F5E),
          to: const Color(0xFFBE123C),
          icon: Icons.medical_services_rounded,
        ),
      LguAgency.disaster => (
          from: const Color(0xFF0EA5E9),
          to: const Color(0xFF0E7490),
          icon: Icons.flood_rounded,
        ),
      LguAgency.lto => (
          from: const Color(0xFF8B5CF6),
          to: const Color(0xFF5B21B6),
          icon: Icons.directions_car_rounded,
        ),
    };

class _LguReferralDialog extends StatefulWidget {
  const _LguReferralDialog({required this.category, required this.referral});

  final String category;
  final LguReferral referral;

  @override
  State<_LguReferralDialog> createState() => _LguReferralDialogState();
}

class _LguReferralDialogState extends State<_LguReferralDialog> {
  /// Feedback shown inside the dialog. A snackbar would sit on the page *behind*
  /// the dialog, under the dimmed barrier, where it is barely visible.
  String? _message;

  String _agencyName(AppStrings t, LguAgency agency) => switch (agency) {
        LguAgency.fire => t.agencyFire,
        LguAgency.police => t.agencyPolice,
        LguAgency.medical => t.agencyMedical,
        LguAgency.disaster => t.agencyDisaster,
        LguAgency.lto => t.agencyLto,
      };

  /// The inline status line, or an empty box while there is nothing to say.
  Widget _noticeFor(({Color from, Color to, IconData icon}) style) =>
      _message == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 14),
              child: _Notice(
                message: _message!,
                color: style.to,
                reduce: MediaQuery.of(context).disableAnimations,
              ),
            );

  /// One agency's call button and its alternate numbers.
  ///
  /// Each block arrives after the one above it ([index] staggers the delay), so
  /// the eye reads them in order. Only the first button breathes: two pulsing
  /// buttons would compete for the one thing the screen is trying to say.
  List<Widget> _optionBlock(
    AppStrings t,
    LguOption option,
    int index,
    bool reduce,
  ) {
    final style = _styleFor(option.agency);
    final name = _agencyName(t, option.agency);
    final base = 380 + index * 220;

    return [
      if (index > 0) ...[
        const SizedBox(height: 22),
        // The ambulance is offered "in case it is worse", so it says so.
        if (option.agency == LguAgency.medical)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              t.referralIfHurt.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ).motion(
            reduce,
            (a) => a.fadeIn(delay: Duration(milliseconds: base), duration: 300.ms),
          ),
      ],
      _PrimaryCallButton(
        style: style,
        agency: name,
        number: option.primary,
        breathe: index == 0,
        reduce: reduce,
        onCall: () => _call(option.primary),
        onCopy: () => _copyOnly(option.primary),
      ).motion(
        reduce,
        (a) => a
            .fadeIn(delay: Duration(milliseconds: base), duration: 300.ms)
            .slideY(
              begin: 0.25,
              end: 0,
              delay: Duration(milliseconds: base),
              duration: 420.ms,
              curve: Curves.easeOutCubic,
            ),
      ),
      for (final (i, n) in option.alternates.indexed) ...[
        const SizedBox(height: 10),
        _AlternateRow(
          color: style.to,
          number: n,
          onCall: () => _call(n),
          onCopy: () => _copyOnly(n),
        ).motion(
          reduce,
          (a) => a
              .fadeIn(
                delay: Duration(milliseconds: base + 140 + i * 90),
                duration: 300.ms,
              )
              .slideX(
                begin: 0.08,
                end: 0,
                delay: Duration(milliseconds: base + 140 + i * 90),
                duration: 380.ms,
                curve: Curves.easeOutCubic,
              ),
        ),
      ],
    ];
  }

  Future<void> _copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  Future<void> _call(LguNumber number) async {
    HapticFeedback.mediumImpact();
    final t = context.s;
    var launched = false;
    try {
      launched = await launchUrl(
        Uri(scheme: 'tel', path: number.dial),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      launched = false;
    }
    if (launched || !mounted) return;

    // No dialer (an emulator, a tablet, a phone with no SIM app) or the OS
    // refused. "Nothing happened" is not acceptable on this screen, so copy the
    // number — in dialable form, so it pastes straight into any phone app — and
    // say that this is what happened.
    await _copy(number.dial);
    if (mounted) setState(() => _message = t.referralNoDialer);
  }

  Future<void> _copyOnly(LguNumber number) async {
    HapticFeedback.selectionClick();
    await _copy(number.dial);
    if (mounted) setState(() => _message = context.s.referralCopied);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.s;
    final reduce = MediaQuery.of(context).disableAnimations;
    final referral = widget.referral;
    final style = _styleFor(referral.agency);
    final categoryName = categoryLabel(t, widget.category);
    // Every agency on offer, so the sentence names all of them ("LTO or
    // Ambulance") rather than only the first.
    final agencies = referral.options
        .map((o) => _agencyName(t, o.agency))
        .join(t.referralOr);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Material(
            color: AppColors.surface,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    style: style,
                    title: referral.allowsReporting
                        ? t.referralAdvisoryTitle
                        : t.referralTitle,
                    categoryName: categoryName,
                    reduce: reduce,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppText.body(
                          referral.allowsReporting
                              ? t.referralAdvisoryBody(categoryName, agencies)
                              : t.referralBody(categoryName, agencies),
                          maxLines: 6,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.body.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.5,
                          ),
                        ).motion(
                          reduce,
                          (a) => a.fadeIn(delay: 260.ms, duration: 350.ms),
                        ),
                        const SizedBox(height: 20),
                        for (final (oi, option) in referral.options.indexed)
                          ..._optionBlock(t, option, oi, reduce),
                        // Not AnimatedSize with a zero duration under reduce-motion:
                        // a zero-length animation notifies its listeners during
                        // layout, and Flutter rejects a render object resizing
                        // itself mid-layout. Without motion there is nothing to
                        // animate, so it is simply not used.
                        if (reduce)
                          _noticeFor(style)
                        else
                          AnimatedSize(
                            duration: 250.ms,
                            curve: Curves.easeOutCubic,
                            child: _noticeFor(style),
                          ),
                        const SizedBox(height: 6),
                        // The barangay still takes this report, so say so and
                        // make it the clear next step — the police number above
                        // is advice, not a gate.
                        if (referral.allowsReporting) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 50,
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).pop(true),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: const BorderSide(
                                    color: AppColors.primary, width: 1.4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: const Icon(Icons.edit_note_rounded, size: 22),
                              label: Text(
                                t.referralContinue,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ).motion(
                            reduce,
                            (a) => a.fadeIn(delay: 650.ms, duration: 300.ms),
                          ),
                        ],
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(t.referralBack),
                        ).motion(
                          reduce,
                          (a) => a.fadeIn(delay: 700.ms, duration: 300.ms),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).motion(
      reduce,
      (a) => a
          .fadeIn(duration: 180.ms)
          .scaleXY(
            begin: 0.88,
            end: 1,
            duration: 420.ms,
            curve: Curves.easeOutBack,
          ),
    );
  }
}

/// The coloured top: agency icon with an expanding ripple, then the title.
class _Header extends StatelessWidget {
  const _Header({
    required this.style,
    required this.title,
    required this.categoryName,
    required this.reduce,
  });

  final ({Color from, Color to, IconData icon}) style;
  final String title;
  final String categoryName;
  final bool reduce;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [style.from, style.to],
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 112,
            height: 112,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // Two staggered ripples. They say "urgent" without a word, and
                // they are the only thing on this screen that repeats.
                if (!reduce)
                  for (final delay in const [0, 900])
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.55),
                          width: 2,
                        ),
                      ),
                    )
                        .animate(
                          delay: Duration(milliseconds: delay),
                          onPlay: (c) => c.repeat(),
                        )
                        .scaleXY(
                          begin: 1,
                          end: 1.55,
                          duration: 1800.ms,
                          curve: Curves.easeOut,
                        )
                        .fadeOut(duration: 1800.ms, curve: Curves.easeOut),
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(style.icon, size: 40, color: Colors.white),
                ).motion(
                  reduce,
                  (a) => a.scaleXY(
                    begin: 0.3,
                    end: 1,
                    delay: 120.ms,
                    duration: 700.ms,
                    curve: Curves.elasticOut,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              categoryName.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ).motion(
            reduce,
            (a) => a.fadeIn(delay: 180.ms, duration: 300.ms),
          ),
          const SizedBox(height: 12),
          AppText.heading3(
            title,
            maxLines: 3,
            textAlign: TextAlign.center,
            style: AppTextStyles.heading3.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ).motion(
            reduce,
            (a) => a
                .fadeIn(delay: 220.ms, duration: 350.ms)
                .slideY(
                  begin: 0.3,
                  end: 0,
                  delay: 220.ms,
                  duration: 400.ms,
                  curve: Curves.easeOutCubic,
                ),
          ),
        ],
      ),
    );
  }
}

/// The one thing this screen exists for.
class _PrimaryCallButton extends StatelessWidget {
  const _PrimaryCallButton({
    required this.style,
    required this.agency,
    required this.number,
    required this.breathe,
    required this.reduce,
    required this.onCall,
    required this.onCopy,
  });

  final ({Color from, Color to, IconData icon}) style;
  final String agency;
  final LguNumber number;

  /// Whether this button pulses. Only the headline one does.
  final bool breathe;
  final bool reduce;
  final VoidCallback onCall;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final button = Semantics(
      button: true,
      label: '$agency ${number.display}',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(colors: [style.from, style.to]),
          boxShadow: [
            BoxShadow(
              color: style.to.withValues(alpha: 0.38),
              blurRadius: 22,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onCall,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.call_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          context.s.referralCall(agency),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            number.display,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy',
                    onPressed: onCopy,
                    icon: Icon(Icons.copy_rounded,
                        color: Colors.white.withValues(alpha: 0.85), size: 20),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // A slow breath, so the eye settles on it. Skipped under reduce-motion.
    if (reduce || !breathe) return button;
    return button
        .animate(
          delay: 1000.ms,
          onPlay: (c) => c.repeat(reverse: true),
        )
        .scaleXY(
          begin: 1,
          end: 1.018,
          duration: 1100.ms,
          curve: Curves.easeInOut,
        );
  }
}

/// A second line for the same agency, for when the first is busy.
class _AlternateRow extends StatelessWidget {
  const _AlternateRow({
    required this.color,
    required this.number,
    required this.onCall,
    required this.onCopy,
  });

  final Color color;
  final LguNumber number;
  final VoidCallback onCall;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onCall,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Row(
            children: [
              Icon(Icons.phone_in_talk_rounded, size: 20, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  number.display,
                  style: TextStyle(
                    color: color,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copy',
                onPressed: onCopy,
                icon: Icon(Icons.copy_rounded,
                    size: 19, color: color.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The inline status line ("number copied" / "no phone app").
class _Notice extends StatelessWidget {
  const _Notice({
    required this.message,
    required this.color,
    required this.reduce,
  });

  final String message;
  final Color color;
  final bool reduce;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_rounded, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    ).motion(
      reduce,
      (a) => a
          .fadeIn(duration: 250.ms)
          .slideY(begin: 0.3, end: 0, duration: 300.ms, curve: Curves.easeOut),
    );
  }
}

extension _Motion on Widget {
  /// Applies [build] unless the system asks for reduced motion.
  Widget motion(bool reduce, Animate Function(Animate a) build) =>
      reduce ? this : build(animate());
}
