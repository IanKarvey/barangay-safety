import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../../providers/non_resident_provider.dart';
import '../../utils/constants.dart';
import '../../config/app_config.dart';
import '../../widgets/app_tile_layer.dart';
import '../../widgets/app_map_attribution.dart';
import '../../widgets/app_text.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();

  // Map animation — slowly zoom into Lipa City
  late final AnimationController _mapAnimController;
  late final Animation<double> _zoomAnim;
  late final Animation<double> _latAnim;
  late final Animation<double> _lngAnim;

  // UI fade in
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnim;

  // Lipa City center
  static const double _centerLat = 13.9411;
  static const double _centerLng = 121.1632;

  @override
  void initState() {
    super.initState();

    // Map pan+zoom animation
    _mapAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    );

    _zoomAnim = Tween<double>(begin: 12.0, end: 15.5).animate(
      CurvedAnimation(parent: _mapAnimController, curve: Curves.easeInOut),
    );
    _latAnim = Tween<double>(begin: _centerLat - 0.03, end: _centerLat).animate(
      CurvedAnimation(parent: _mapAnimController, curve: Curves.easeInOut),
    );
    _lngAnim = Tween<double>(begin: _centerLng + 0.02, end: _centerLng).animate(
      CurvedAnimation(parent: _mapAnimController, curve: Curves.easeInOut),
    );

    _mapAnimController.addListener(() {
      if (mounted) {
        _mapController.move(
          LatLng(_latAnim.value, _lngAnim.value),
          _zoomAnim.value,
        );
      }
    });

    // UI fade animation
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    // Start animations
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _mapAnimController.forward();
        _fadeController.forward();
      }
    });

    _initializeApp();
  }

  @override
  void dispose() {
    _mapAnimController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    await Future.delayed(const Duration(milliseconds: 2200));
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('onboarding_complete') ?? false;
    if (!onboardingDone) {
      if (mounted) Navigator.pushReplacementNamed(context, '/onboarding');
      return;
    }

    // A signed-in non-resident must land back on their map, not the login
    // screen — §1 requires the session to survive an app restart.
    final nonResident = context.read<NonResidentProvider>();
    await nonResident.restoreSession();
    if (!mounted) return;
    if (nonResident.hasSession) {
      Navigator.pushReplacementNamed(context, '/non-resident');
      return;
    }

    final authProvider = context.read<AuthProvider>();
    await authProvider.initialize();
    if (!mounted) return;

    if (authProvider.isAuthenticated) {
      final user = authProvider.user;
      if (user == null) {
        Navigator.pushReplacementNamed(context, '/login');
      } else if (user.isSuperAdmin) {
        Navigator.pushReplacementNamed(context, '/superadmin');
      } else if (user.isAdmin) {
        Navigator.pushReplacementNamed(context, '/official');
      } else if (!user.isVerified) {
        Navigator.pushReplacementNamed(context, '/pending-verification');
      } else {
        Navigator.pushReplacementNamed(context, '/resident');
      }
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Live map background ─────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(_centerLat - 0.03, _centerLng + 0.02),
              initialZoom: 12.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.none, // disable all gestures
              ),
            ),
            children: [
              const AppTileLayer(),
              const AppMapAttribution(),
            ],
          ),

          // ── Dark gradient overlay ────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xCC001F5B), // deep navy, 80% opacity top
                  Color(0xE6001F5B), // deeper at bottom
                ],
              ),
            ),
          ),

          // ── Branding content ─────────────────────────────────────────────
          FadeTransition(
            opacity: _fadeAnim,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Shield logo
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 30,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.shield_rounded,
                    size: 54,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 28),

                // App name
                const AppText(
                  AppConfig.appName,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Incident Reporting System',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.7),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    'Lipa City, Batangas',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Loading indicator at bottom ──────────────────────────────────
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Column(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white.withValues(alpha: 0.7),
                      strokeWidth: 2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Loading...',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
