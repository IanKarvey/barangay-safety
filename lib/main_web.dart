import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'l10n/app_strings.dart';
import 'providers/auth_provider.dart';
import 'providers/barangay_provider.dart';
import 'providers/incident_provider.dart';
import 'providers/language_provider.dart';
import 'providers/non_resident_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/responder_location_provider.dart';
import 'screens/official/incident_manage_screen.dart';
import 'screens/official/non_resident_queue_screen.dart';
import 'screens/resident/report_detail_screen.dart';
import 'screens/shared/analytics_screen.dart';
import 'screens/shared/audit_log_screen.dart';
import 'screens/shared/emergency_contacts_screen.dart';
import 'screens/shared/escalations_screen.dart';
import 'screens/shared/response_analytics_screen.dart';
import 'screens/shared/heatmap_screen.dart';
import 'screens/shared/notifications_screen.dart';
import 'screens/web/web_build.dart';
import 'screens/web/web_page_frame.dart';
import 'screens/web/web_update_banner.dart';
import 'screens/web/web_shell.dart';
import 'services/supabase_service.dart';
import 'utils/theme.dart';
import 'widgets/alert_host.dart';

/// Web entry point — the §2 revision's "non-mobile-dependent" admin dashboard.
///
/// ## Why this is a second entry point rather than `kIsWeb` branches in main()
///
/// `lib/main.dart` boots the mobile app: Firebase, FCM, local notifications,
/// and the password-recovery deep-link watcher. Four of this project's
/// packages have no web implementation at all — `geocoding`,
/// `flutter_local_notifications`, `permission_handler` and `app_links` — so
/// every one of those calls would need guarding, and a missed guard surfaces
/// as a runtime `MissingPluginException` in the browser rather than a build
/// error anyone would notice.
///
/// Keeping web on its own entry means `main.dart` is never edited for the web
/// build, so the working Android release cannot regress because of work done
/// here. Build with:
///
///     flutter build web -t lib/main_web.dart
///     flutter run -d chrome -t lib/main_web.dart
///
/// ## What is shared, and what is not
///
/// Everything below the UI is shared as-is: the models, the services, the
/// providers, and therefore every RLS assumption and permission rule. That is
/// the whole reason for choosing Flutter web over a separate JS dashboard —
/// the authorisation logic has exactly one implementation, so the two
/// surfaces cannot drift apart and quietly disagree about who may see what.
///
/// Only the shell differs: a sidebar layout for a desktop browser instead of
/// a bottom navigation bar sized for a thumb.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Surface failures on screen. A release build otherwise swallows them: a
  // screen that throws while building is a blank grey box, and the explanation
  // sits in a browser console nobody has open.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    webLastError.value = details.exceptionAsString();
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    webLastError.value = error.toString();
    return true;
  };
  ErrorWidget.builder = (details) => Material(
        color: const Color(0xFFFEF2F2),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            details.exceptionAsString(),
            style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13),
          ),
        ),
      );

  // Same single-locale initialisation as the mobile entry. Omitting this is
  // what produced the grey-dashboard bug on mobile (fixed 2026-08-11) — the
  // date formatters the dashboard builds with throw without it.
  await initializeDateFormatting('en_US');

  await SupabaseService.initialize();

  runApp(const BarangaySafetyWeb());
}

/// Needed by [webOnGenerateRoute] to read the signed-in user when guarding a
/// route, exactly as `main.dart`'s `navigatorKey` does for the mobile app.
final GlobalKey<NavigatorState> webNavigatorKey = GlobalKey<NavigatorState>();

/// Routes the reused screens push to.
///
/// This is not optional plumbing. `WebShell` renders existing screens, and
/// those screens navigate: tapping any incident card calls
/// `Navigator.pushNamed(context, '/incident-manage')`, which is where verify,
/// assign, dispatch and resolve actually happen. With only `home:` set and no
/// generator, every one of those taps threw "Could not find a generator for
/// route" — the dashboard rendered perfectly and then did nothing when used,
/// which is the worst shape a bug can take.
///
/// Only the routes those screens actually reach are listed. The resident flows
/// (report form, camera, GPS) are deliberately absent: they need plugins with
/// no web implementation, and an admin dashboard has no reason to open them.
Route<dynamic>? webOnGenerateRoute(RouteSettings settings) {
  Widget? page;

  switch (settings.name) {
    case '/incident-manage':
      final incidentId = settings.arguments as String;
      // The same guard as main.dart, carried over deliberately rather than
      // reimplemented: this screen exposes Mark Resolved / Flag / Delete, so a
      // non-official must never reach it however they arrived. Dropping the
      // guard here would reopen on web exactly the authorisation hole that was
      // found and closed on mobile in August.
      final ctx = webNavigatorKey.currentContext;
      final isOfficial =
          ctx == null ? false : (ctx.read<AuthProvider>().user?.isOfficial ?? false);
      page = isOfficial
          ? IncidentManageScreen(incidentId: incidentId)
          : ReportDetailScreen(incidentId: incidentId);

    case '/notifications':
      page = const NotificationsScreen();

    case '/non-resident-queue':
      page = const NonResidentQueueScreen();

    case '/analytics':
      page = AnalyticsScreen(
        isSuperAdmin: settings.arguments as bool? ?? false,
      );

    case '/heatmap':
      page = HeatmapScreen(
        isSuperAdmin: settings.arguments as bool? ?? false,
      );

    case '/audit-log':
      final args = settings.arguments as Map<String, dynamic>?;
      page = AuditLogScreen(
        incidentId: args?['incidentId'] as String?,
        userId: args?['userId'] as String?,
        title: args?['title'] as String? ?? 'Activity Log',
      );

    case '/escalations':
      page = const EscalationsScreen();

    case '/response-times':
      page = const ResponseAnalyticsScreen();

    case '/emergency-numbers':
      page = const EmergencyContactsScreen();

    case '/report-detail':
      page = ReportDetailScreen(incidentId: settings.arguments as String);
  }

  if (page == null) return null;
  return MaterialPageRoute(builder: (_) => WebPageFrame(child: page!), settings: settings);
}

class BarangaySafetyWeb extends StatelessWidget {
  const BarangaySafetyWeb({super.key});

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
        ChangeNotifierProvider(create: (_) => LanguageProvider()..load()),
      ],
      child: Consumer<LanguageProvider>(
        builder: (context, lang, _) => AppStringsScope(
          language: lang.language,
          strings: lang.strings,
          child: MaterialApp(
            title: '${AppConfig.appName} — Admin',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            navigatorKey: webNavigatorKey,
            home: const WebShell(),
            onGenerateRoute: webOnGenerateRoute,
            // In a release build an unrouted pushNamed does nothing at all —
            // no error, no screen — which is indistinguishable from a dead
            // button. Naming the route that failed makes it a findable bug.
            onUnknownRoute: (settings) => MaterialPageRoute(
              settings: settings,
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Page not available')),
                body: Center(
                  child: SelectableText(
                    'No page is registered for "${settings.name}" on the web dashboard.',
                  ),
                ),
              ),
            ),
            // The update bar is a row ABOVE the app, not an overlay: laid over it,
            // it covered the logo and the Refresh button. It takes no space at all
            // until a newer version exists (see web_update_banner.dart).
            builder: (context, child) => AlertHost(
              navigatorKey: webNavigatorKey,
              child: Column(
                children: [
                  const UpdateBanner(),
                  Expanded(
                    child: Stack(
                      children: [
                        if (child != null) child,
                        const Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _ErrorBanner(),
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
    );
  }
}

/// Red strip along the bottom showing the last uncaught error, with the build
/// it came from. Dismissible; a new error replaces it.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: webLastError,
      builder: (context, error, _) {
        if (error == null) return const SizedBox.shrink();
        return Material(
          color: const Color(0xFF991B1B),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    'Error (build $kBuildId): $error',
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 18),
                  onPressed: () => webLastError.value = null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
