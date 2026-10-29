import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:app_links/app_links.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'config/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/supabase_service.dart';
import 'services/local_notification_service.dart';
import 'services/fcm_service.dart';
import 'providers/auth_provider.dart';
import 'providers/incident_provider.dart';
import 'providers/barangay_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/non_resident_provider.dart';
import 'providers/responder_location_provider.dart';
import 'providers/language_provider.dart';
import 'l10n/app_strings.dart';
import 'utils/theme.dart';

// Screens
import 'screens/shared/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/verify_otp_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'screens/resident/resident_home_screen.dart';
import 'screens/resident/report_form_screen.dart';
import 'screens/resident/report_tutorial_screen.dart';
import 'screens/resident/report_detail_screen.dart';
import 'screens/official/official_home_screen.dart';
import 'screens/official/incident_manage_screen.dart';
import 'screens/official/non_resident_queue_screen.dart';
import 'screens/superadmin/superadmin_home_screen.dart';
import 'screens/superadmin/barangay_coordinates_screen.dart';
import 'screens/shared/help_support_screen.dart';
import 'screens/shared/about_screen.dart';
import 'screens/shared/privacy_notice_screen.dart';
import 'screens/shared/video_player_screen.dart';
import 'screens/resident/edit_profile_screen.dart';
import 'screens/shared/audit_log_screen.dart';
import 'screens/shared/escalations_screen.dart';
import 'screens/shared/analytics_screen.dart';
import 'screens/shared/heatmap_screen.dart';
import 'screens/shared/notifications_screen.dart';
import 'screens/shared/onboarding_screen.dart';
import 'screens/auth/pending_verification_screen.dart';
import 'screens/non_resident/non_resident_login_screen.dart';
import 'screens/non_resident/non_resident_home_screen.dart';
import 'widgets/alert_host.dart';
import 'widgets/app_text.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A build-time exception renders Flutter's default ErrorWidget, which in a
  // release build is a featureless grey rectangle. That is how the official
  // and superadmin dashboards failed on a real phone (2026-08-11): no message,
  // no stack, nothing to act on, and it does not reproduce in debug where the
  // red error screen appears instead.
  //
  // Showing the actual exception on screen means the next failure reports
  // itself — a screenshot is enough to diagnose it, with no USB cable, no adb
  // and no guesswork about which widget broke.
  ErrorWidget.builder = (FlutterErrorDetails details) => _CrashReport(
        details: details,
      );

  // Flutter's default image cache is 1000 images / 100 MiB — sized for a
  // desktop, not for the ₱4,000 Android phones this app actually runs on. The
  // official screens show grids of incident photos and ID scans, so the cache
  // fills fast and the eviction pressure lands on a device that may only have
  // 2GB of RAM in total. Half the budget is still ample for a photo grid.
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = 50 << 20
    ..maximumSize = 150;

  // Date symbols for non-en_US locales are NOT bundled by default. Without
  // this, DateFormat throws LocaleDataException on any device whose locale is
  // not en_US — a phone set to Filipino, for instance. That was the confirmed
  // cause of the grey dashboards (2026-08-11): of six DateFormat call sites,
  // the only two in a dashboard header were the two screens that failed.
  //
  // Initialising ONE locale and pinning Intl to it, rather than loading every
  // locale: bundling all of them parses a large table on the main thread at
  // startup, and pinning also makes date output deterministic instead of
  // varying with whatever the handset happens to be set to.
  await initializeDateFormatting('en_US');
  Intl.defaultLocale = 'en_US';

  // Lock to portrait orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set status bar style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // Initialize Supabase
  await SupabaseService.initialize();

  // Attached here, immediately after Supabase is ready, rather than in
  // BarangaySafetyApp.initState(). onAuthStateChange is a broadcast stream
  // with no replay buffer — supabase_flutter processes an incoming
  // password-recovery deep link (and can emit AuthChangeEvent.passwordRecovery)
  // as soon as it is initialized, which can happen before runApp() even
  // builds the first frame. A listener attached in initState() is one
  // microtask too late to be guaranteed to see that event; a listener
  // attached here cannot be.
  watchPasswordRecoveryGlobally();

  // Initialize local notifications
  await LocalNotificationService.initialize();

  // Initialize Firebase FCM
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await FcmService.instance.initialize();
    FcmService.setNavigatorKey(navigatorKey);
    LocalNotificationService.setNavigatorKey(navigatorKey);
  } catch (_) {
    // Firebase init failed — safe to ignore
  }

  runApp(const BarangaySafetyApp());
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ── Password recovery deep link ────────────────────────────────────────
//
// Module-level, not tied to any widget's lifecycle. See the call site in
// main() for why: it has to exist before runApp() so it cannot lose the
// race against supabase_flutter's own internal link processing.

/// Debounces duplicate signals for the SAME tap of the SAME link.
///
/// A cold start delivers one recovery through two independent paths —
/// `AppLinks.getInitialLink()` and the SDK's own `AuthChangeEvent
/// .passwordRecovery` — and both call [_goToResetPassword].
///
/// This used to be a permanent one-shot `bool` instead of a timestamp, which
/// was a worse bug than the one it was fixing: once *any* recovery
/// navigation had happened, the flag stayed `true` for the rest of the app
/// process, silently swallowing every later attempt. A user who tested more
/// than one reset email in the same session — exactly how this gets tested —
/// would find the first link worked and every one after it did nothing, with
/// no way to tell the difference from the link being broken outright. Three
/// seconds is generous for two near-simultaneous callbacks racing on the same
/// tap and well short of how long it takes a person to request and open a
/// second email.
DateTime? _lastRecoveryNavAt;

/// Matches a Supabase recovery redirect in either auth-flow shape.
///
/// Kept in sync by hand with `isRecoveryLink` in
/// `test/recovery_link_test.dart` — that file cannot import this one, since
/// this is the app entry point, not a library.
bool _isRecoveryLink(Uri uri) =>
    uri.host == 'reset-password' ||
    uri.path.contains('reset-password') ||
    uri.fragment.contains('type=recovery') ||
    uri.queryParameters['type'] == 'recovery';

/// True when a recovery-shaped link is carrying Supabase's own error
/// response instead of a usable code — `?error=access_denied&error_code=
/// otp_expired&...`, confirmed live (2026-09-16) from a link that had
/// already been used once.
///
/// The error can land in the query string or the fragment depending on which
/// auth flow issued the redirect, so both are checked. Kept separate from
/// [_isRecoveryLink] rather than folded in, because the two questions differ:
/// "is this link recovery-shaped at all" decides whether to look further;
/// "did it actually work" decides what to do once it is.
bool _recoveryLinkError(Uri uri) {
  final fromQuery = uri.queryParameters['error_description'] ??
      (uri.queryParameters.containsKey('error') ? uri.queryParameters['error'] : null);
  if (fromQuery != null) return true;
  return uri.fragment.contains('error=') || uri.fragment.contains('error_code=');
}

/// The message shown for [_recoveryLinkError], pulled from the URI when
/// Supabase supplies one rather than hardcoded — `otp_expired` reads
/// differently from a link that was simply malformed, and the description
/// Supabase sends is already the plain-language version.
String _recoveryLinkErrorMessage(Uri uri) {
  final fromQuery = uri.queryParameters['error_description'];
  if (fromQuery != null && fromQuery.isNotEmpty) {
    return fromQuery.replaceAll('+', ' ');
  }
  final frag = uri.fragment;
  final m = RegExp(r'error_description=([^&]+)').firstMatch(frag);
  if (m != null) {
    return Uri.decodeComponent(m.group(1)!).replaceAll('+', ' ');
  }
  return 'This reset link no longer works. Please request a new one.';
}

/// Navigates to the change-password screen, once per distinct tap.
///
/// `pushNamedAndRemoveUntil` clears the stack deliberately — a plain
/// `pushReplacementNamed` only swaps the top route, so whatever startup
/// routing had already pushed (Splash, then Login) stayed underneath, which
/// is why the screen used to be reachable by swiping back but was never
/// shown on top.
void _goToResetPassword() {
  final now = DateTime.now();
  if (_lastRecoveryNavAt != null &&
      now.difference(_lastRecoveryNavAt!) < const Duration(seconds: 3)) {
    debugPrint('[recovery] _goToResetPassword: debounced, skipping');
    return;
  }

  final nav = navigatorKey.currentState;
  if (nav == null) {
    // Cold start: this can fire before MaterialApp has built a Navigator at
    // all. Retrying after every frame until one exists — rather than giving
    // up — is what makes the earlier subscription point in main() actually
    // pay off; attaching early is wasted if a null navigator here just drops
    // the event.
    debugPrint('[recovery] _goToResetPassword: navigator not ready, retrying next frame');
    WidgetsBinding.instance.addPostFrameCallback((_) => _goToResetPassword());
    return;
  }

  debugPrint('[recovery] _goToResetPassword: pushing /reset-password now');
  _lastRecoveryNavAt = now;
  nav.pushNamedAndRemoveUntil('/reset-password', (route) => false);
}

/// Shown when a recovery link fails to exchange for a session — an expired
/// or already-used link, most commonly.
///
/// ## Why this exists
///
/// `_isRecoveryLink()` matches on URL *shape* alone — `host == 'reset-password'`
/// is true whether Supabase's redirect carries a working `?code=` or an
/// `?error=access_denied&error_code=otp_expired`. So the app was already
/// navigating to the change-password screen on a failed link exactly as
/// readily as a working one — the reporter would land on a normal-looking
/// "set new password" form with no valid session behind it, and only find out
/// something was wrong if they filled it in and pressed submit.
///
/// The underlying `AuthException` was already being caught — `onError` on the
/// auth-state stream — but only `debugPrint`ed. Confirmed live (2026-09-16):
/// a recovery link tapped twice (the second time by mistake, or by an email
/// client's link-prefetch silently consuming the one-time code before the
/// real tap) produces exactly this — `otp_expired` — with nothing on screen
/// to explain it. This surfaces that failure the moment it happens, rather
/// than after a confused submit-and-fail.
void _showRecoveryError(String message, {int retries = 0}) {
  final ctx = navigatorKey.currentContext;
  if (ctx == null) {
    // Same reasoning as _goToResetPassword: this can fire before the
    // Navigator exists. Bounded retry rather than an infinite loop, since —
    // unlike navigation, which matters however late — a toast nobody is
    // looking at yet has a point past which showing it is no longer useful.
    if (retries > 20) return;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showRecoveryError(message, retries: retries + 1),
    );
    return;
  }
  ScaffoldMessenger.of(ctx).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: Colors.red.shade700,
      duration: const Duration(seconds: 6),
    ),
  );
}

/// Starts listening for a password-recovery deep link.
///
/// Called once, from `main()`, right after Supabase finishes initializing.
void watchPasswordRecoveryGlobally() {
  // Deliberately not stored/cancelled — this listens for the whole app
  // process, the same as the module-level `navigatorKey` it feeds.
  //
  // Every event is logged, not just passwordRecovery. Every failure branch
  // in this file has been logged at some point; the success path never has
  // been, at any layer — supabase_flutter's own internal handler uses the
  // `logging` package's Logger, which is silent by default with nothing
  // attached to Logger.root, so its own "handle deeplink uri" / "handle
  // deeplink uri" info logs produce no logcat output either. The result: a
  // successful exchange and a silently-stalled one are currently
  // indistinguishable from outside. This closes that blind spot.
  SupabaseService.instance.auth.onAuthStateChange.listen(
    (state) {
      debugPrint('[recovery] onAuthStateChange: ${state.event}'
          ' session=${state.session != null}');
      if (state.event != AuthChangeEvent.passwordRecovery) return;
      debugPrint('[recovery] passwordRecovery event received — navigating');
      _goToResetPassword();
    },
    onError: (e) {
      debugPrint('[recovery] onAuthStateChange error: $e');
      final message = e is AuthException
          ? e.message
          : 'This reset link no longer works. Please request a new one.';
      _showRecoveryError(message);
    },
  );

  final appLinks = AppLinks();

  // Link arrives while the app is already running (warm start).
  appLinks.uriLinkStream.listen((uri) {
    debugPrint('[recovery] uriLinkStream received: $uri');
    if (!_isRecoveryLink(uri)) {
      debugPrint('[recovery] not recovery-shaped, ignoring');
      return;
    }
    // A link that already carries Supabase's error response (tapped twice,
    // or already consumed by an email client's link-prefetch before the real
    // tap) has nothing to exchange for a session. Navigating to the
    // change-password form anyway is what produced the reported "nothing
    // seems to happen" — the form rendered, with no valid session behind it,
    // and gave no sign anything was wrong until a submit failed. Showing the
    // error immediately and skipping the doomed navigation is the fix.
    if (_recoveryLinkError(uri)) {
      debugPrint('[recovery] link carries an error param — showing it, not navigating');
      _showRecoveryError(_recoveryLinkErrorMessage(uri));
      return;
    }
    debugPrint('[recovery] link looks valid — calling _goToResetPassword via URL fallback');
    _goToResetPassword();
  });

  // Link launched the app from a cold start.
  appLinks.getInitialLink().then((uri) {
    debugPrint('[recovery] getInitialLink resolved: $uri');
    if (uri == null || !_isRecoveryLink(uri)) return;
    if (_recoveryLinkError(uri)) {
      _showRecoveryError(_recoveryLinkErrorMessage(uri));
      return;
    }
    _goToResetPassword();
  });
}

/// Replaces the default grey rectangle a release build shows when a widget
/// throws during build.
///
/// Deliberately dependency-free — no theme, no providers, no localization. It
/// has to render when the rest of the app is in an unknown state, so it must
/// not touch anything that could itself throw.
class _CrashReport extends StatelessWidget {
  final FlutterErrorDetails details;

  const _CrashReport({required this.details});

  @override
  Widget build(BuildContext context) {
    // The first frames of the stack name the widget that actually failed;
    // everything after is framework plumbing.
    final stack = details.stack
            ?.toString()
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .take(12)
            .join('\n') ??
        'No stack trace available.';

    return Material(
      color: const Color(0xFF121212),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppText(
                'This screen failed to load',
                style: TextStyle(
                  color: Color(0xFFFF6B6B),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Screenshot this and send it to the developer.',
                style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 13),
              ),
              const SizedBox(height: 18),
              const Text('ERROR',
                  style: TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 11,
                      letterSpacing: 1.2)),
              const SizedBox(height: 4),
              SelectableText(
                details.exceptionAsString(),
                style: const TextStyle(
                  color: Color(0xFFFFD166),
                  fontSize: 12.5,
                  height: 1.45,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 18),
              const Text('WHERE',
                  style: TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 11,
                      letterSpacing: 1.2)),
              const SizedBox(height: 4),
              SelectableText(
                stack,
                style: const TextStyle(
                  color: Color(0xFF9BC1FF),
                  fontSize: 11,
                  height: 1.4,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BarangaySafetyApp extends StatefulWidget {
  const BarangaySafetyApp({super.key});

  @override
  State<BarangaySafetyApp> createState() => _BarangaySafetyAppState();
}

class _BarangaySafetyAppState extends State<BarangaySafetyApp> {
  // Password-recovery deep-link handling lives at module level now (see
  // watchPasswordRecoveryGlobally, called once from main() right after
  // Supabase initializes) — not here. Attaching it in this State's
  // initState() was the original bug: that runs after runApp() builds the
  // first frame, which is one step too late to be guaranteed to see an
  // AuthChangeEvent.passwordRecovery that supabase_flutter's own internal
  // link processing can fire as soon as it is initialized.

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => IncidentProvider()),
        ChangeNotifierProvider(create: (_) => BarangayProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => NonResidentProvider()),
        ChangeNotifierProvider(create: (_) => ResponderLocationProvider()),
        // Loads the saved choice immediately so the app never flashes English
        // at someone who chose Tagalog.
        ChangeNotifierProvider(create: (_) => LanguageProvider()..load()),
      ],
      // Wrapping MaterialApp (rather than sitting inside it) means a language
      // change rebuilds every screen, including anything already on the stack.
      child: Consumer<LanguageProvider>(
        builder: (context, lang, _) => AppStringsScope(
          language: lang.language,
          strings: lang.strings,
          child: MaterialApp(
            title: AppConfig.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            navigatorKey: navigatorKey,
            initialRoute: '/',
            onGenerateRoute: _onGenerateRoute,
            // Escalation pop-ups (unanswered report, last-resort numbers, "good
            // news") sit above every screen.
            builder: (context, child) => AlertHost(
              navigatorKey: navigatorKey,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/onboarding':
        return _buildRoute(const OnboardingScreen(), settings);
      case '/':
        return _buildRoute(const SplashScreen(), settings);

      // ── Auth ────────────────────────────────────────────────────────────
      case '/login':
        return _buildRoute(const LoginScreen(), settings);
      case '/register':
        return _buildRoute(const RegisterScreen(), settings);
      case '/forgot-password':
        return _buildRoute(const ForgotPasswordScreen(), settings);
      case '/verify-otp':
        final email = settings.arguments as String;
        return _buildRoute(VerifyOtpScreen(email: email), settings);
      case '/reset-password':
        return _buildRoute(const ResetPasswordScreen(), settings);
      case '/pending-verification':
        return _buildRoute(const PendingVerificationScreen(), settings);

      case '/non-resident-queue':
        return _buildRoute(const NonResidentQueueScreen(), settings);
      case '/heatmap':
        final isSuperAdmin = settings.arguments as bool? ?? false;
        return _buildRoute(HeatmapScreen(isSuperAdmin: isSuperAdmin), settings);

      // ── Non-Resident (one-time report flow) ─────────────────────────────
      case '/non-resident-login':
        return _buildRoute(const NonResidentLoginScreen(), settings);
      case '/non-resident':
        return _buildRoute(const NonResidentHomeScreen(), settings);

      // ── Resident ────────────────────────────────────────────────────────
      case '/resident':
        return _buildRoute(const ResidentHomeScreen(), settings);
      case '/report-form':
        return _buildRoute(const ReportFormScreen(), settings);
      case '/report-tutorial':
        // Arguments: {'source': 'auto' | 'button' | 'form_help', 'step': int}.
        final args = settings.arguments as Map<String, dynamic>?;
        return _buildRoute(
          ReportTutorialScreen(
            source: args?['source'] as String? ?? 'button',
            initialStep: args?['step'] as int? ?? 0,
          ),
          settings,
        );
      case '/report-detail':
        final incidentId = settings.arguments as String;
        return _buildRoute(
          ReportDetailScreen(incidentId: incidentId),
          settings,
        );

      // ── Official (Admin) ────────────────────────────────────────────────
      case '/official':
        return _buildRoute(const OfficialHomeScreen(), settings);
      case '/incident-manage':
        final incidentId = settings.arguments as String;
        // Guard the route itself, not just the callers. This screen exposes
        // Mark Resolved / Flag / Delete, so a resident must never reach it —
        // however they got here. A notification handler already made that
        // mistake once.
        final ctx = navigatorKey.currentContext;
        final isOfficial = ctx == null
            ? false
            : (ctx.read<AuthProvider>().user?.isOfficial ?? false);
        if (!isOfficial) {
          return _buildRoute(ReportDetailScreen(incidentId: incidentId), settings);
        }
        return _buildCardUpRoute(IncidentManageScreen(incidentId: incidentId), settings);

      // ── Super Admin ─────────────────────────────────────────────────────
      case '/superadmin':
        return _buildRoute(const SuperAdminHomeScreen(), settings);

      // ── Shared ──────────────────────────────────────────────────────────
      case '/help-support':
        return _buildRoute(const HelpSupportScreen(), settings);
      case '/privacy':
        return _buildRoute(const PrivacyNoticeScreen(), settings);
      case '/about':
        return _buildRoute(const AboutScreen(), settings);
      case '/edit-profile':
        return _buildRoute(const EditProfileScreen(), settings);
      case '/video-player':
        final rawArgs = settings.arguments;
        final url = rawArgs is Map ? rawArgs['url'] as String? : null;
        if (url == null || url.isEmpty) {
          return _buildRoute(const _RouteErrorScreen(message: 'Video not found.'), settings);
        }
        final title = (rawArgs is Map ? rawArgs['title'] as String? : null) ?? 'Video';
        return _buildRoute(
          VideoPlayerScreen(videoUrl: url, title: title),
          settings,
        );
      case '/notifications':
        return _buildRoute(const NotificationsScreen(), settings);
      case '/analytics':
        final isSuperAdmin = settings.arguments as bool? ?? false;
        return _buildRoute(
          AnalyticsScreen(isSuperAdmin: isSuperAdmin),
          settings,
        );
      case '/barangay-coordinates':
        return _buildRoute(const BarangayCoordinatesScreen(), settings);
      case '/escalations':
        return _buildRoute(const EscalationsScreen(), settings);
      case '/audit-log':
        final args = settings.arguments as Map<String, dynamic>?;
        return _buildRoute(
          AuditLogScreen(
            incidentId: args?['incidentId'] as String?,
            userId: args?['userId'] as String?,
            title: args?['title'] as String? ?? 'Activity Log',
          ),
          settings,
        );

      default:
        return _buildRoute(const LoginScreen(), settings);
    }
  }

  static Route<dynamic> _buildRoute(Widget page, RouteSettings settings) {
    return PageRouteBuilder(
      settings: settings,
      pageBuilder: (_, __, ___) => page,
      transitionDuration: const Duration(milliseconds: 400),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        // ── Incoming page curves ──────────────────────────────────────
        // easeOutBack gives a subtle spring overshoot on scale
        final enterFade = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        final enterScale = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );

        // ── Outgoing page curves (page being covered) ─────────────────
        final exitCurve = CurvedAnimation(
          parent: secondaryAnimation,
          curve: Curves.easeInCubic,
          reverseCurve: Curves.easeOutCubic,
        );

        Widget result = child;

        // Step 1 — outgoing page scales back + dims when something pushes on top
        result = FadeTransition(
          opacity: Tween<double>(begin: 1.0, end: 0.82).animate(exitCurve),
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.0, end: 0.95).animate(exitCurve),
            child: result,
          ),
        );

        // Step 2 — incoming page lifts up from below + springs into scale + fades in
        result = FadeTransition(
          opacity: Tween<double>(begin: 0.0, end: 1.0).animate(enterFade),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.91, end: 1.0).animate(enterScale),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.035),
                end: Offset.zero,
              ).animate(enterFade),
              child: result,
            ),
          ),
        );

        return result;
      },
    );
  }

  // Bottom-up card entrance — used for manage screen (feels like a modal card)
  static Route<dynamic> _buildCardUpRoute(Widget page, RouteSettings settings) {
    return PageRouteBuilder(
      settings: settings,
      pageBuilder: (_, __, ___) => page,
      transitionDuration: const Duration(milliseconds: 480),
      reverseTransitionDuration: const Duration(milliseconds: 340),
      transitionsBuilder: (_, animation, secondaryAnimation, child) {
        final enter = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );
        final exit = CurvedAnimation(
          parent: secondaryAnimation,
          curve: Curves.easeInCubic,
          reverseCurve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: Tween<double>(begin: 1.0, end: 0.85).animate(exit),
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOut),
            ),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(enter),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

// Fallback shown when a route is reached with missing/invalid arguments
// (e.g. a deep link to /video-player without a url) instead of crashing.
class _RouteErrorScreen extends StatelessWidget {
  final String message;

  const _RouteErrorScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 48, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 16),
                AppText(message, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
