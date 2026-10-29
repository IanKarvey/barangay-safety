import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/fcm_service.dart';
import '../../services/local_notification_service.dart';
import '../../services/location_service.dart';
import '../../utils/constants.dart';
import '../../config/app_config.dart';
import '../../utils/helpers.dart';
import '../../widgets/app_tile_layer.dart';
import '../../widgets/app_map_attribution.dart';
import '../../widgets/animated_text_field.dart';
import '../../widgets/animated_button.dart';
import '../../widgets/language_toggle.dart';
import '../../l10n/app_strings.dart';
import '../../widgets/app_text.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isCheckingLocation = false;
  final _locationService = LocationService();

  final MapController _mapController = MapController();

  // Circular orbit map animation
  late final AnimationController _mapAnimController;

  // Card slide-up + fade-in
  late final AnimationController _cardAnimController;
  late final Animation<double> _cardSlideAnim;
  late final Animation<double> _cardFadeAnim;

  // Shake on login failure
  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;

  static const double _centerLat = 13.9411;
  static const double _centerLng = 121.1632;
  static const double _orbitRadius = 0.024; // ~2.6 km orbit
  static const double _orbitZoom = 14.8;

  // 40s orbit / 240 steps = ~6 map moves per second.
  static const int _orbitSteps = 240;
  int _lastOrbitStep = -1;

  @override
  void initState() {
    super.initState();

    // Circular orbit — loops forever around Lipa City at fixed zoom
    _mapAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    );
    // Throttled to ~6 moves/sec rather than one per frame. Every move()
    // recomputes the visible tile set and can kick off tile requests, so
    // driving it at 60fps pinned the main thread on real hardware for the
    // entire time the login screen was open. At this rate the orbit still
    // looks continuous and costs a tenth as much.
    _mapAnimController.addListener(() {
      if (!mounted) return;
      final step = (_mapAnimController.value * _orbitSteps).floor();
      if (step == _lastOrbitStep) return;
      _lastOrbitStep = step;

      final angle = _mapAnimController.value * 2 * math.pi;
      final lat = _centerLat + _orbitRadius * math.cos(angle);
      final lng = _centerLng + _orbitRadius * math.sin(angle);
      _mapController.move(LatLng(lat, lng), _orbitZoom);
    });

    // Card entrance animation
    _cardAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _cardSlideAnim = Tween<double>(begin: 80, end: 0).animate(
      CurvedAnimation(parent: _cardAnimController, curve: Curves.easeOutCubic),
    );
    _cardFadeAnim = CurvedAnimation(parent: _cardAnimController, curve: Curves.easeOut);

    // Shake on login failure
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -10), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10, end: -8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: -4), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -4, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeInOut));

    // Delay start so FlutterMap has time to attach the MapController
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _mapAnimController.repeat(); // start orbiting after map is ready
        _cardAnimController.forward();
      }
    });
  }

  @override
  void dispose() {
    _mapAnimController.dispose();
    _cardAnimController.dispose();
    _shakeCtrl.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<bool> _residentWithinLipaCity(AuthProvider authProvider) async {
    setState(() => _isCheckingLocation = true);
    try {
      final position = await _locationService.getCurrentPosition();
      // Guarded: acquiring a GPS fix takes seconds, and a user who
      // backs out of the screen while waiting leaves this callback
      // running against a disposed State. setState() then throws
      // "setState() called after dispose()".
      if (!mounted) return false;
      final distKm = lipaCityDistanceKm(position.latitude, position.longitude);
      setState(() => _isCheckingLocation = false);
      if (distKm > 20.0) {
        HapticFeedback.heavyImpact();
        await authProvider.signOut();
        await showOutsideCitySheet(context, distKm);
        return false;
      }
      return true;
    } catch (_) {
      if (mounted) setState(() => _isCheckingLocation = false);
      return true;
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.signIn(
      _emailController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;

    if (success) {
      final user = authProvider.user;
      if (user == null) return;

      // Admins and officials bypass geofencing — only residents are location-gated
      if (user.isResident) {
        if (!await _residentWithinLipaCity(authProvider)) return;
        if (!mounted) return;
      }

      // Ask for notification permission on first login
      await LocalNotificationService.requestPermission();

      // Subscribe to FCM push topic for officials/admins
      if (user.isAdmin && user.barangayId != null) {
        await FcmService.instance.subscribeToBarangay(user.barangayId!);
      } else if (user.isSuperAdmin) {
        await FcmService.instance.subscribeToTopic('all_incidents');
      }

      if (user.isSuperAdmin) {
        Navigator.pushReplacementNamed(context, '/superadmin');
      } else if (user.isAdmin) {
        Navigator.pushReplacementNamed(context, '/official');
      } else if (!user.isVerified) {
        Navigator.pushReplacementNamed(context, '/pending-verification');
      } else {
        Navigator.pushReplacementNamed(context, '/resident');
      }
    } else {
      final err = authProvider.error ?? '';
      if (err == 'email_not_confirmed') {
        HapticFeedback.mediumImpact();
        _showPendingVerificationSheet();
      } else if (err == 'account_suspended') {
        HapticFeedback.heavyImpact();
        _showSuspensionSheet(authProvider.suspensionExpiry);
      } else if (err == 'no_internet') {
        HapticFeedback.heavyImpact();
        _shakeCtrl.forward(from: 0);
        showErrorSnackbar(
          context,
          'No internet connection. Please check your network and try again.',
        );
      } else {
        HapticFeedback.heavyImpact();
        _shakeCtrl.forward(from: 0);
        showErrorSnackbar(context, err.isEmpty ? 'Login failed' : err);
      }
    }
  }

  void _showPendingVerificationSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => const _PendingVerifSheet(),
    );
  }

  void _showSuspensionSheet(DateTime? expiry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (_) => _SuspensionSheet(expiry: expiry),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        return Scaffold(
          resizeToAvoidBottomInset: true,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // ── Animated map background ────────────────────────────────
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: LatLng(_centerLat + _orbitRadius, _centerLng),
                  initialZoom: _orbitZoom,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  const AppTileLayer(),
                  const AppMapAttribution(),
                ],
              ),

              // ── Dark gradient overlay ──────────────────────────────────
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xBB001F5B),
                      Color(0xDD001F5B),
                      Color(0xF2000E2E),
                    ],
                    stops: [0.0, 0.45, 1.0],
                  ),
                ),
              ),

              // ── Language switch ────────────────────────────────────────
              // Sits on the very first screen so an official who reads little
              // English can switch before they have to understand anything.
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                right: 16,
                child: const LanguageToggle(onDark: true),
              ),

              // ── Top branding ───────────────────────────────────────────
              Positioned(
                top: MediaQuery.of(context).padding.top + 52,
                left: 0,
                right: 0,
                child: AnimatedBuilder(
                  animation: _cardFadeAnim,
                  builder: (context, child) =>
                      Opacity(opacity: _cardFadeAnim.value, child: child),
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.40),
                              blurRadius: 40,
                              spreadRadius: -4,
                              offset: const Offset(0, 16),
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/images/app_icon.png',
                          width: 120,
                          height: 120,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const AppText(
                        AppConfig.appName,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.8,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.s.appTagline,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.65),
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.location_on_rounded, size: 12, color: Colors.white.withValues(alpha: 0.8)),
                            const SizedBox(width: 4),
                            Text(
                              'Lipa City, Batangas',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.85),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Login card (slides up from bottom) ─────────────────────
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_cardAnimController, _shakeCtrl]),
                  builder: (context, child) => Transform.translate(
                    offset: Offset(_shakeAnim.value, _cardSlideAnim.value),
                    child: Opacity(opacity: _cardFadeAnim.value, child: child),
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x50000000),
                          blurRadius: 40,
                          offset: Offset(0, -10),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Bottom sheet handle bar
                              Center(
                                child: Container(
                                  width: 36,
                                  height: 4,
                                  margin: const EdgeInsets.only(bottom: 20),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE5E5EA),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),

                              AppText(
                                context.s.signIn,
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1C1C1E),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                context.s.welcomeBack,
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13,
                                  color: Color(0xFF8E8E93),
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Email
                              AnimatedTextField(
                                controller: _emailController,
                                labelText: context.s.email,
                                prefixIcon: Icons.email_outlined,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                validator: validateEmail,
                              ),
                              const SizedBox(height: 14),

                              // Password
                              AnimatedTextField(
                                controller: _passwordController,
                                labelText: context.s.password,
                                prefixIcon: Icons.lock_outlined,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _handleLogin(),
                                validator: validatePassword,
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscurePassword = !_obscurePassword),
                                ),
                              ),
                              const SizedBox(height: 4),

                              // Forgot password
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () =>
                                      Navigator.pushNamed(context, '/forgot-password'),
                                  child: Text(context.s.forgotPassword),
                                ),
                              ),
                              const SizedBox(height: 10),

                              // Sign In button
                              AnimatedButton(
                                label: context.s.signIn,
                                isLoading: auth.isLoading || _isCheckingLocation,
                                onPressed: _handleLogin,
                              ),
                              const SizedBox(height: 20),

                              // Register link
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    context.s.noAccount,
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 14,
                                      color: Color(0xFF8E8E93),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => Navigator.pushNamed(context, '/register'),
                                    child: Text(
                                      context.s.register,
                                      style: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 14,
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Non-resident quick entry — no account needed
                              const Divider(height: 1),
                              const SizedBox(height: 12),
                              GestureDetector(
                                onTap: () => Navigator.pushNamed(
                                    context, '/non-resident-login'),
                                behavior: HitTestBehavior.opaque,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.emergency_share_rounded,
                                        size: 18, color: AppColors.error),
                                    const SizedBox(width: 8),
                                    Text(
                                      context.s.justVisiting,
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 14,
                                        color: AppColors.error,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Who this is for. The system only covers five
                              // barangays; saying so before anyone signs in
                              // spares residents elsewhere from registering for
                              // a service that will never reach them.
                              const _ScopeNotice(),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Serving Barangays 1, 2, 3, 7 and 10" — read from [AppConfig.barangayCenters]
/// so it cannot disagree with the barangays the app actually routes to.
class _ScopeNotice extends StatelessWidget {
  const _ScopeNotice();

  /// "1, 2, 3, 7 and 10".
  static String _list(String and) {
    final numbers = AppConfig.coveredBarangays;
    if (numbers.length < 2) return numbers.join();
    return '${numbers.sublist(0, numbers.length - 1).join(', ')} $and '
        '${numbers.last}';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.s;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.location_on_rounded,
                size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  t.loginScopeTitle(_list(t.listAnd)),
                  maxLines: 2,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 3),
                AppText(
                  t.loginScopeBody,
                  maxLines: 3,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    height: 1.4,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pending Verification bottom sheet ───────────────────────────────────────
class _PendingVerifSheet extends StatefulWidget {
  const _PendingVerifSheet();

  @override
  State<_PendingVerifSheet> createState() => _PendingVerifSheetState();
}

class _PendingVerifSheetState extends State<_PendingVerifSheet>
    with TickerProviderStateMixin {
  late final List<AnimationController> _ringCtrls;
  late final AnimationController _shieldCtrl;
  late final Animation<double> _shieldScale;

  @override
  void initState() {
    super.initState();

    _shieldCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _shieldScale = CurvedAnimation(parent: _shieldCtrl, curve: Curves.easeOutBack);
    _shieldCtrl.forward();

    _ringCtrls = List.generate(3, (i) {
      final ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2200),
      );
      Future.delayed(Duration(milliseconds: i * 520), () {
        if (mounted) ctrl.repeat();
      });
      return ctrl;
    });
  }

  @override
  void dispose() {
    _shieldCtrl.dispose();
    for (final c in _ringCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        28, 16, 28, MediaQuery.of(context).viewInsets.bottom + 36,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 28),

          // Shield with radar rings
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Pulse rings
                ...List.generate(3, (i) => AnimatedBuilder(
                  animation: _ringCtrls[i],
                  builder: (_, __) {
                    final t = _ringCtrls[i].value;
                    final radius = 28.0 + t * 42.0;
                    return SizedBox(
                      width: radius * 2,
                      height: radius * 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: (1 - t) * 0.35),
                            width: 1.5,
                          ),
                        ),
                      ),
                    );
                  },
                )),

                // Shield icon
                ScaleTransition(
                  scale: _shieldScale,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: AppColors.primary,
                      size: 32,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          const AppText(
            'Account Pending Verification',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Your account has been created but not yet verified.\nVisit the barangay hall in person so an official can confirm your identity.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.55,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),

          // CTA
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushReplacementNamed(context, '/pending-verification');
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              child: const Text(
                'View Verification Steps',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Dismiss',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Suspension bottom sheet ──────────────────────────────────────────────────
class _SuspensionSheet extends StatefulWidget {
  final DateTime? expiry;
  const _SuspensionSheet({this.expiry});

  @override
  State<_SuspensionSheet> createState() => _SuspensionSheetState();
}

class _SuspensionSheetState extends State<_SuspensionSheet>
    with TickerProviderStateMixin {
  late final List<AnimationController> _ringCtrls;
  late final AnimationController _iconCtrl;
  late final Animation<double> _iconScale;

  @override
  void initState() {
    super.initState();

    _iconCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _iconScale = CurvedAnimation(parent: _iconCtrl, curve: Curves.easeOutBack);
    _iconCtrl.forward();

    _ringCtrls = List.generate(3, (i) {
      final ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2000),
      );
      Future.delayed(Duration(milliseconds: i * 480), () {
        if (mounted) ctrl.repeat();
      });
      return ctrl;
    });
  }

  @override
  void dispose() {
    _iconCtrl.dispose();
    for (final c in _ringCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  String _formatExpiry(DateTime expiry) {
    final now = DateTime.now();
    final diff = expiry.difference(now);
    if (diff.inDays >= 1) {
      final d = diff.inDays;
      return '$d day${d == 1 ? '' : 's'}';
    }
    if (diff.inHours >= 1) {
      final h = diff.inHours;
      return '$h hour${h == 1 ? '' : 's'}';
    }
    final m = diff.inMinutes.clamp(1, 59);
    return '$m minute${m == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final hasExpiry = widget.expiry != null &&
        widget.expiry!.isAfter(DateTime.now());
    final expiryText = hasExpiry ? _formatExpiry(widget.expiry!) : '7 days';

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        28, 16, 28, MediaQuery.of(context).viewInsets.bottom + 40,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 28),

          // Lock icon with warning rings
          SizedBox(
            width: 110,
            height: 110,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ...List.generate(3, (i) => AnimatedBuilder(
                  animation: _ringCtrls[i],
                  builder: (_, __) {
                    final t = _ringCtrls[i].value;
                    final radius = 30.0 + t * 46.0;
                    return SizedBox(
                      width: radius * 2,
                      height: radius * 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFDC2626)
                                .withValues(alpha: (1 - t) * 0.4),
                            width: 1.5,
                          ),
                        ),
                      ),
                    );
                  },
                )),

                // Lock icon
                ScaleTransition(
                  scale: _iconScale,
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      color: Color(0xFFDC2626),
                      size: 34,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          const AppText(
            'Account Suspended',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),

          // Warning chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFDC2626).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFDC2626).withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFDC2626), size: 14),
                const SizedBox(width: 6),
                Text(
                  'False Report Warning',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFDC2626),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13.5,
                color: AppColors.textSecondary,
                height: 1.6,
              ),
              children: [
                const TextSpan(
                  text:
                      'Your account has been placed on hold due to a false report incident. '
                      'You are restricted from filing new reports for ',
                ),
                TextSpan(
                  text: expiryText,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFDC2626),
                  ),
                ),
                const TextSpan(text: '.'),
              ],
            ),
          ),

          const SizedBox(height: 10),

          Text(
            'If you believe this is a mistake, please visit your barangay office.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: AppColors.textSecondary.withValues(alpha: 0.7),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              child: const Text(
                'I Understand',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
