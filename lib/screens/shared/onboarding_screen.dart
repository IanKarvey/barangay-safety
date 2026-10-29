import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/constants.dart';
import '../../l10n/app_strings.dart';
import '../../widgets/app_text.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  static const _pageCount = 3;

  // Resolved per build rather than held const — the copy changes with the
  // selected language.
  List<_PageData> _pagesFor(AppStrings t) => [
        _PageData(
          icon: Icons.shield_rounded,
          colorA: const Color(0xFF1565C0),
          colorB: const Color(0xFF42A5F5),
          title: t.onb1Title,
          subtitle: t.onb1Sub,
        ),
        _PageData(
          icon: Icons.photo_camera_rounded,
          colorA: const Color(0xFF00897B),
          colorB: const Color(0xFF4DB6AC),
          title: t.onb2Title,
          subtitle: t.onb2Sub,
        ),
        _PageData(
          icon: Icons.verified_rounded,
          colorA: const Color(0xFF5E35B1),
          colorB: const Color(0xFFAB47BC),
          title: t.onb3Title,
          subtitle: t.onb3Sub,
        ),
      ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  void _next() {
    if (_currentPage < _pageCount - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pagesFor(context.s);
    final page = pages[_currentPage];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Skip button ─────────────────────────────────────────
            SizedBox(
              height: 48,
              child: Align(
                alignment: Alignment.centerRight,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: _currentPage < _pageCount - 1 ? 1.0 : 0.0,
                  child: TextButton(
                    onPressed: _currentPage < _pageCount - 1 ? _finish : null,
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Page content ────────────────────────────────────────
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pageCount,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) => _OnboardingPage(
                  data: pages[index],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // ── Dot indicators ──────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pageCount, (i) {
                final active = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 28 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? page.colorA : AppColors.divider,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),

            const SizedBox(height: 32),

            // ── Next / Get Started button ───────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [page.colorA, page.colorB],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: page.colorA.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _next,
                    borderRadius: BorderRadius.circular(14),
                    splashColor: Colors.white24,
                    child: SizedBox(
                      height: 54,
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: ScaleTransition(
                              scale: Tween<double>(begin: 0.85, end: 1.0)
                                  .animate(anim),
                              child: child,
                            ),
                          ),
                          child: Text(
                            key: ValueKey(_currentPage == _pageCount - 1),
                            _currentPage == _pageCount - 1
                                ? 'Get Started'
                                : 'Next',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 36),
          ],
        ),
      ),
    );
  }
}

// ── Single onboarding page ───────────────────────────────────────────────────
class _OnboardingPage extends StatelessWidget {
  final _PageData data;

  const _OnboardingPage({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Illustration circle — bounces in when this page becomes active
          Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [data.colorA, data.colorB],
              ),
              boxShadow: [
                BoxShadow(
                  color: data.colorA.withValues(alpha: 0.32),
                  blurRadius: 44,
                  spreadRadius: 4,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer decorative ring
                Container(
                  width: 206,
                  height: 206,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                      width: 1.5,
                    ),
                  ),
                ),
                // Inner soft fill
                Container(
                  width: 162,
                  height: 162,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                // Icon
                Icon(data.icon, size: 82, color: Colors.white),
              ],
            ),
          )
              .animate(key: ValueKey(data.title))
              .scale(
                begin: const Offset(0.72, 0.72),
                end: const Offset(1.0, 1.0),
                duration: const Duration(milliseconds: 520),
                curve: Curves.easeOutBack,
              )
              .fadeIn(duration: const Duration(milliseconds: 380)),

          const SizedBox(height: 48),

          // Title
          AppText(
            data.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              height: 1.2,
              letterSpacing: -0.5,
            ),
          )
              .animate(key: ValueKey('title_${data.title}'))
              .fadeIn(
                delay: const Duration(milliseconds: 110),
                duration: const Duration(milliseconds: 340),
              )
              .slideY(
                begin: 0.22,
                end: 0,
                delay: const Duration(milliseconds: 110),
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutCubic,
              ),

          const SizedBox(height: 16),

          // Subtitle
          AppText(
            data.subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 15,
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          )
              .animate(key: ValueKey('sub_${data.title}'))
              .fadeIn(
                delay: const Duration(milliseconds: 200),
                duration: const Duration(milliseconds: 300),
              )
              .slideY(
                begin: 0.15,
                end: 0,
                delay: const Duration(milliseconds: 200),
                duration: const Duration(milliseconds: 340),
                curve: Curves.easeOutCubic,
              ),
        ],
      ),
    );
  }
}

// ── Page data ────────────────────────────────────────────────────────────────
class _PageData {
  final IconData icon;
  final Color colorA;
  final Color colorB;
  final String title;
  final String subtitle;

  const _PageData({
    required this.icon,
    required this.colorA,
    required this.colorB,
    required this.title,
    required this.subtitle,
  });
}
