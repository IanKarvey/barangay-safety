import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/constants.dart';
import '../../l10n/app_strings.dart';
import '../../widgets/app_text.dart';

class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen>
    with TickerProviderStateMixin {
  int? _expandedIndex;

  late final AnimationController _cardAnimController;
  late final Animation<double> _cardSlideAnim;
  late final Animation<double> _cardFadeAnim;

  late final AnimationController _iconCtrl;
  late final Animation<double> _iconScale;

  static const _faqs = [
    (
      q: 'How do I submit an incident report?',
      a: 'Tap the "+" button on the home screen. Fill in the category, description, and severity level. Then pin the location on the map, optionally attach photos, review your report, and tap Submit.',
    ),
    (
      q: 'Can I edit a report after submitting?',
      a: 'No. Once a report is submitted it is forwarded to barangay officials for review. If you made a mistake on a pending report, you can delete it and resubmit.',
    ),
    (
      q: 'How do I delete a report?',
      a: 'You can only delete reports that are still "Pending." Open the report detail screen, tap the ⋮ menu at the top right, and choose Delete. You can also swipe left on the report in "My Reports."',
    ),
    (
      q: 'What do the severity levels mean?',
      a: 'Level 1 – Critical: Immediate threat to life or property.\nLevel 2 – High: Serious incident needing urgent attention.\nLevel 3 – Medium: Moderate issue that should be addressed soon.\nLevel 4 – Low: Minor concern or nuisance.',
    ),
    (
      q: 'Why is my account not yet verified?',
      a: 'Non-resident accounts require manual verification by a barangay official. Please wait for approval or visit your barangay office with a valid ID.',
    ),
    (
      q: 'How do I reset my password?',
      a: 'On the login screen, tap "Forgot Password?" and enter your email address. You will receive a password reset link.',
    ),
    (
      q: 'Who can see my report?',
      a: 'Your reports are visible to you and to the barangay officials of your registered barangay. The SuperAdmin can also view all reports across all barangays.',
    ),
    (
      q: 'What happens after I submit a report?',
      a: 'Officials will review your report and change its status:\n• Pending → In Progress (being handled)\n• In Progress → Resolved (completed)\nYou can track the status in "My Reports."',
    ),
  ];

  @override
  void initState() {
    super.initState();

    _cardAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _cardSlideAnim = Tween<double>(begin: 0.18, end: 0.0).animate(
      CurvedAnimation(parent: _cardAnimController, curve: Curves.easeOutCubic),
    );
    _cardFadeAnim = CurvedAnimation(
      parent: _cardAnimController,
      curve: Curves.easeOut,
    );

    _iconCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _iconScale =
        CurvedAnimation(parent: _iconCtrl, curve: Curves.easeOutBack);

    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) {
        _cardAnimController.forward();
        _iconCtrl.forward();
      }
    });
  }

  @override
  void dispose() {
    _cardAnimController.dispose();
    _iconCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ── Navy gradient background ─────────────────────────────────────
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF001245),
                    Color(0xFF0D2272),
                    Color(0xFF001A6E),
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),

            // ── Decorative circles ───────────────────────────────────────────
            Positioned(
              top: -70,
              right: -50,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                ),
              ),
            ),
            Positioned(
              top: 80,
              left: -90,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.03),
                ),
              ),
            ),

            // ── Header ───────────────────────────────────────────────────────
            SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const Spacer(),
                        const Flexible(child: AppText(
                          'Help & Support',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        )),
                        const Spacer(),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Icon
                  ScaleTransition(
                    scale: _iconScale,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4A90E2), Color(0xFF001245)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.support_agent_rounded,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  const AppText(
                    'How can we help?',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.4,
                    ),
                  )
                      .animate(delay: 80.ms)
                      .fadeIn(duration: 400.ms)
                      .slideY(begin: 0.15, end: 0, curve: Curves.easeOutCubic),

                  const SizedBox(height: 6),

                  Text(
                    'Browse FAQs or contact your barangay office.',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                  )
                      .animate(delay: 130.ms)
                      .fadeIn(duration: 400.ms)
                      .slideY(begin: 0.15, end: 0, curve: Curves.easeOutCubic),

                  const SizedBox(height: 24),
                ],
              ),
            )
                .animate()
                .fadeIn(duration: 400.ms)
                .slideY(
                  begin: -0.08,
                  end: 0,
                  duration: 400.ms,
                  curve: Curves.easeOutCubic,
                ),

            // ── Sliding white card ───────────────────────────────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedBuilder(
                animation: _cardAnimController,
                builder: (_, child) => FadeTransition(
                  opacity: _cardFadeAnim,
                  child: Transform.translate(
                    offset: Offset(
                      0,
                      _cardSlideAnim.value *
                          MediaQuery.of(context).size.height,
                    ),
                    child: child,
                  ),
                ),
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.70,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(32)),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x50000000),
                        blurRadius: 48,
                        offset: Offset(0, -10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Handle
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 4),
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      Flexible(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            22,
                            16,
                            22,
                            math.max(bottomInset, 32),
                          ),
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ── FAQ section ──────────────────────────────
                              _sectionLabel('Frequently Asked Questions'),
                              const SizedBox(height: 12),

                              ...List.generate(_faqs.length, (i) {
                                final faq = _faqs[i];
                                final isOpen = _expandedIndex == i;
                                return _FaqCard(
                                  question: faq.q,
                                  answer: faq.a,
                                  isOpen: isOpen,
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() =>
                                        _expandedIndex = isOpen ? null : i);
                                  },
                                  delay: Duration(milliseconds: 60 + i * 40),
                                );
                              }),

                              const SizedBox(height: 24),

                              // ── Contact section ───────────────────────────
                              _sectionLabel('Contact Support'),
                              const SizedBox(height: 12),

                              _ContactCard(
                                icon: Icons.location_city_rounded,
                                title: context.s.barangayOffice,
                                subtitle:
                                    'Visit your local barangay hall for in-person assistance.',
                                delay: const Duration(milliseconds: 420),
                              ),
                              const SizedBox(height: 8),
                              _ContactCard(
                                icon: Icons.email_outlined,
                                title: context.s.emailUs,
                                subtitle: 'support@example.com',
                                onTap: () => launchUrl(Uri.parse(
                                    'mailto:support@example.com')),
                                delay: const Duration(milliseconds: 460),
                              ),
                              const SizedBox(height: 8),
                              _ContactCard(
                                icon: Icons.emergency_rounded,
                                title: context.s.emergencyHotline,
                                subtitle: '911 (National) · 117 (Police)',
                                onTap: () =>
                                    launchUrl(Uri.parse('tel:911')),
                                delay: const Duration(milliseconds: 500),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: AppText(
          text,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 0.9,
          ),
        ),
      );
}

// ── FAQ Card ──────────────────────────────────────────────────────────────────
class _FaqCard extends StatelessWidget {
  final String question;
  final String answer;
  final bool isOpen;
  final VoidCallback onTap;
  final Duration delay;

  const _FaqCard({
    required this.question,
    required this.answer,
    required this.isOpen,
    required this.onTap,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: isOpen
              ? AppColors.primary.withValues(alpha: 0.035)
              : const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isOpen
                ? AppColors.primary.withValues(alpha: 0.35)
                : AppColors.divider,
            width: isOpen ? 1.5 : 1.0,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Q number badge
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: isOpen
                            ? AppColors.primary
                            : AppColors.divider,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isOpen ? Colors.white : AppColors.textSecondary,
                          ),
                          child: Text('Q'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: isOpen
                              ? AppColors.primary
                              : AppColors.textPrimary,
                          height: 1.4,
                        ),
                        child: AppText(question),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: isOpen ? 0.5 : 0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: isOpen
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        size: 22,
                      ),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  child: isOpen
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 12),
                            Container(
                              height: 1,
                              color: AppColors.primary.withValues(alpha: 0.12),
                            ),
                            const SizedBox(height: 12),
                            AppText(
                              answer,
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13,
                                color: AppColors.textSecondary,
                                height: 1.6,
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    )
        .animate(delay: delay)
        .fadeIn(duration: 320.ms)
        .slideY(begin: 0.1, curve: Curves.easeOutCubic);
  }
}

// ── Contact Card ──────────────────────────────────────────────────────────────
class _ContactCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Duration delay;

  const _ContactCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F4FB),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: AppColors.textSecondary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  AppText(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: AppColors.textSecondary,
              ),
          ],
        ),
      ),
    )
        .animate(delay: delay)
        .fadeIn(duration: 320.ms)
        .slideY(begin: 0.1, curve: Curves.easeOutCubic);
  }
}
