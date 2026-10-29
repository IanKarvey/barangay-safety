import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../utils/constants.dart';
import '../../config/app_config.dart';
import '../../l10n/app_strings.dart';
import '../../widgets/app_text.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen>
    with TickerProviderStateMixin {
  late final AnimationController _cardAnimController;
  late final Animation<double> _cardSlideAnim;
  late final Animation<double> _cardFadeAnim;

  late final AnimationController _shieldCtrl;
  late final Animation<double> _shieldScale;

  late final AnimationController _pulseCtrl;

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
    _cardFadeAnim =
        CurvedAnimation(parent: _cardAnimController, curve: Curves.easeOut);

    _shieldCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _shieldScale =
        CurvedAnimation(parent: _shieldCtrl, curve: Curves.easeOutBack);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) {
        _cardAnimController.forward();
        _shieldCtrl.forward();
        _pulseCtrl.repeat();
      }
    });
  }

  @override
  void dispose() {
    _cardAnimController.dispose();
    _shieldCtrl.dispose();
    _pulseCtrl.dispose();
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
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.shield_rounded,
                                color: Colors.white, size: 18),
                            const SizedBox(height: 2),
                            Text(
                              'BARANGAY SAFETY',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withValues(alpha: 0.7),
                                letterSpacing: 2.0,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Shield with pulse ring
                  SizedBox(
                    width: 96,
                    height: 96,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Pulse ring
                        AnimatedBuilder(
                          animation: _pulseCtrl,
                          builder: (_, __) {
                            final t = _pulseCtrl.value;
                            final radius = 44.0 + t * 16.0;
                            return SizedBox(
                              width: radius * 2,
                              height: radius * 2,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white
                                        .withValues(alpha: (1 - t) * 0.25),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),

                        // Shield icon
                        ScaleTransition(
                          scale: _shieldScale,
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
                              Icons.shield_rounded,
                              color: Colors.white,
                              size: 38,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  const AppText(
                    AppConfig.appName,
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

                  const SizedBox(height: 4),

                  Text(
                    'Incident Reporting System',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12.5,
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                  ).animate(delay: 120.ms).fadeIn(duration: 400.ms),

                  const SizedBox(height: 10),

                  // Version chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: const Text(
                      'Version 1.0.0',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ).animate(delay: 160.ms).fadeIn(duration: 400.ms),

                  const SizedBox(height: 22),
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
                    maxHeight: MediaQuery.of(context).size.height * 0.65,
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
                            math.max(bottomInset, 36),
                          ),
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _InfoSection(
                                title: context.s.aboutTheApp,
                                delay: const Duration(milliseconds: 80),
                                child: const AppText(
                                  '${AppConfig.appName} is a geo-tagged incident reporting system designed for the '
                                  'high-density barangays of Lipa City, Batangas. It enables residents to '
                                  'quickly report safety incidents, track their status, and communicate with '
                                  'local officials — all in one platform.',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                    height: 1.65,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),

                              _InfoSection(
                                title: context.s.keyFeatures,
                                delay: const Duration(milliseconds: 130),
                                child: Column(
                                  children: [
                                    _FeatureRow(
                                      icon: Icons.report_rounded,
                                      label: context.s.featGeoTagged,
                                    ),
                                    _FeatureRow(
                                      icon: Icons.map_rounded,
                                      label: context.s.featMap,
                                    ),
                                    _FeatureRow(
                                      icon: Icons.track_changes_rounded,
                                      label: context.s.featTracking,
                                    ),
                                    _FeatureRow(
                                      icon: Icons.verified_user_rounded,
                                      label: context.s.featRoles,
                                    ),
                                    _FeatureRow(
                                      icon: Icons.bar_chart_rounded,
                                      label: context.s.featAnalytics,
                                    ),
                                    _FeatureRow(
                                      icon: Icons.history_rounded,
                                      label: context.s.featAudit,
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: 12),

                              _InfoSection(
                                title: context.s.coverageArea,
                                delay: Duration(milliseconds: 180),
                                child: Column(
                                  children: [
                                    _InfoRow(
                                      label: context.s.city,
                                      value: 'Lipa City, Batangas',
                                    ),
                                    _InfoRow(
                                      label: context.s.barangay,
                                      value: '5 High-Density Barangays',
                                    ),
                                    _InfoRow(
                                      label: context.s.users,
                                      value:
                                          'Residents, Officials, SuperAdmin',
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: 12),

                              _InfoSection(
                                title: context.s.technology,
                                delay: Duration(milliseconds: 230),
                                child: Column(
                                  children: [
                                    _InfoRow(
                                        label: context.s.platform,
                                        value: 'Flutter (Android & iOS)'),
                                    _InfoRow(
                                        label: context.s.backend,
                                        value: 'Supabase (PostgreSQL)'),
                                    _InfoRow(
                                        label: context.s.storage,
                                        value: 'Supabase Storage'),
                                    _InfoRow(
                                        label: context.s.maps,
                                        value:
                                            'OpenStreetMap via flutter_map'),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),

                              _InfoSection(
                                title: context.s.legal,
                                delay: const Duration(milliseconds: 280),
                                child: const Text(
                                  'This application is developed for official use by Lipa City barangay offices. '
                                  'All data collected is used solely for public safety purposes and is handled '
                                  'in accordance with the Data Privacy Act of 2012 (Republic Act No. 10173).',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 12.5,
                                    color: AppColors.textSecondary,
                                    height: 1.65,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 20),

                              Center(
                                child: Text(
                                  '© 2024 Lipa City Government\nAll rights reserved.',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11,
                                    color: AppColors.textSecondary
                                        .withValues(alpha: 0.7),
                                    height: 1.6,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ).animate(delay: 320.ms).fadeIn(duration: 400.ms),
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
}

// ── Section card ──────────────────────────────────────────────────────────────
class _InfoSection extends StatelessWidget {
  final String title;
  final Widget child;
  final Duration delay;

  const _InfoSection({
    required this.title,
    required this.child,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              AppText(
                title,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    )
        .animate(delay: delay)
        .fadeIn(duration: 350.ms)
        .slideY(begin: 0.08, curve: Curves.easeOutCubic);
  }
}

// ── Feature row ───────────────────────────────────────────────────────────────
class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.primary, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AppText(
              label,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info row ─────────────────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: AppText(
              label,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AppText(
              value,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.5,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
