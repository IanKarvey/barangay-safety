/// Application-wide configuration constants.
/// Update these values with your actual Supabase project credentials.
class AppConfig {
  AppConfig._();

  // Display name. Native shells (AndroidManifest, Info.plist) carry their
  // own copy and must be changed alongside this one.
  static const String appName = 'Barangay Safety';

  // ── Supabase ──────────────────────────────────────────────────────────
  // Supplied at build time so no project credentials live in the repository:
  //   flutter run --dart-define-from-file=env.json
  // (see env.example.json). Found in: Supabase Dashboard → Settings → API.
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  // ── Map Defaults ──────────────────────────────────────────────────────
  // Center of Lipa City, Batangas
  static const double defaultLatitude = 13.9411;
  static const double defaultLongitude = 121.1632;
  static const double defaultZoom = 14.0;

  // ── Map Tiles (Stadia Maps) ───────────────────────────────────────────
  // Replaced tile.openstreetmap.org, whose Tile Usage Policy forbids apps
  // pulling from it — that was the source of the constant
  // "Connection reset by peer" errors.
  //
  // The key is supplied at build time (STADIA_API_KEY in env.json). Restrict it
  // in the Stadia dashboard (Manage Properties → allowed app bundle IDs /
  // domains): it ships inside the APK and can be extracted.
  //
  // Style options: osm_bright (current — closest to standard OSM),
  // alidade_smooth, alidade_smooth_dark, outdoors, stamen_terrain.
  static const String stadiaApiKey = String.fromEnvironment('STADIA_API_KEY');
  static const String mapTileStyle = 'osm_bright';
  static const String mapTileUrl =
      'https://tiles.stadiamaps.com/tiles/$mapTileStyle/{z}/{x}/{y}.png'
      '?api_key=$stadiaApiKey';

  /// Required attribution — Stadia's terms require crediting them, OSM and
  /// OpenMapTiles wherever their tiles are displayed.
  static const String mapAttribution =
      '© Stadia Maps © OpenMapTiles © OpenStreetMap contributors';

  /// The barangay numbers this system covers, ascending — 1, 2, 3, 7 and 10.
  /// Derived from [barangayCenters] so the login screen's "Serving Barangays …"
  /// notice cannot disagree with the barangays the app actually routes to.
  static List<int> get coveredBarangays => barangayCenters.keys
      .map((name) => int.tryParse(name.replaceAll(RegExp(r'[^0-9]'), '')))
      .whereType<int>()
      .toList()
    ..sort();

  // ── Barangay Boundaries (approximate centers) ─────────────────────────
  static const Map<String, Map<String, double>> barangayCenters = {
    'Barangay 1': {'lat': 13.9420, 'lng': 121.1640},
    'Barangay 2': {'lat': 13.9435, 'lng': 121.1620},
    'Barangay 3': {'lat': 13.9400, 'lng': 121.1610},
    'Barangay 7': {'lat': 13.9390, 'lng': 121.1650},
    'Barangay 10': {'lat': 13.9445, 'lng': 121.1660},
  };

  // ── Emergency Contact ────────────────────────────────────────────────
  // ⚠️ UNVERIFIED — this number was hardcoded in report_form_screen.dart and
  // flagged in the 2026-04-24 audit as possibly not a real line. Confirm it
  // with the barangay before release, or replace it with the real hotline.
  // Longer term this should come from the barangay record so each barangay
  // dials its own secretary — see §11 in BARANGAY_CONNECT_REQUIREMENTS.md.
  static const String emergencyHotline = '+6304377778888';

  // ── LGU referral numbers ─────────────────────────────────────────────
  // Where a reporter is sent when their incident is beyond what a barangay can
  // handle (see lib/utils/lgu_routing.dart). Each agency has a LIST of numbers:
  // the first is the big call button, the rest appear as smaller buttons under
  // it, because a rescue line that is busy is exactly when a second one matters.
  //
  // `dial` is what the phone calls, in international form so it works from any
  // network; `display` is what is shown on the button so the person can read it.
  //
  // 911 is the national emergency line and is the fallback for any agency whose
  // own number has not been supplied yet — a real number that works everywhere,
  // rather than a placeholder that would dial nothing in an emergency.
  static const nationalEmergency = (dial: '911', display: '911');

  /// Bureau of Fire Protection, Lipa. Supplied by the owner on 2026-10-15 as
  /// "(043) 757 4168" — Batangas area code 043, so +63 43 757 4168.
  static const referralFire = [
    (dial: '+63437574168', display: '(043) 757 4168'),
  ];

  /// Philippine National Police.
  ///
  /// Placeholder in the public repository — set the police station's
  /// verified hotline for your deployment.
  static const referralPolice = [
    (dial: '+639000000001', display: '+63 900 000 0001'),
  ];

  /// Emergency medical. Uses the same CDRRMO (Lipa Rescue) lines as
  /// [referralDisaster], per the owner on 2026-10-15 — the rescue office is who
  /// answers a medical call here, so there is no separate ambulance number.
  static const referralMedical = referralDisaster;

  /// Land Transportation Office — offered first for a vehicular accident, with
  /// an ambulance beside it. Supplied by the owner on 2026-10-15 as
  /// "(043) 756 2345" — Batangas area code 043, so +63 43 756 2345.
  static const referralLto = [
    (dial: '+63437562345', display: '(043) 756 2345'),
  ];

  /// City Disaster Risk Reduction and Management Office (Lipa Rescue) office
  /// landlines; the first entry is a placeholder for the office mobile line.
  static const referralDisaster = [
    (dial: '+639000000002', display: '+63 900 000 0002'),
    (dial: '+63437560217', display: '(043) 756 0217'),
    (dial: '+63437575164', display: '(043) 757 5164'),
  ];

  // ── Geofence ─────────────────────────────────────────────────────────
  static const double lipaCityLat = 13.9411;
  static const double lipaCityLng = 121.1632;
  static const double lipaCityRadiusKm = 20.0; // covers all Lipa City barangays

  // ── Storage ───────────────────────────────────────────────────────────
  static const String incidentPhotoBucket = 'incident-photos';
  static const String profilePhotoBucket = 'profile-photos';
  static const String idVerificationBucket = 'id-verification';

  // ── Auth deep links ───────────────────────────────────────────────────
  /// Where Supabase sends the user after they tap a password-recovery email.
  ///
  /// Must match an `intent-filter` in AndroidManifest.xml **and** be listed
  /// under Authentication → URL Configuration → Redirect URLs in the Supabase
  /// dashboard. Supabase silently falls back to the project Site URL for any
  /// redirect it does not recognise — which is what made the recovery link
  /// open a browser instead of the app.
  static const String passwordResetRedirect =
      'com.barangaysafety.app://reset-password';

  // ── Severity Levels ───────────────────────────────────────────────────
  // 4 is the worst, 1 the least — see lib/utils/severity.dart. Reversed from
  // the original scale on 2026-08-25 at the owner's direction.
  static const Map<int, String> severityLabels = {
    4: 'Critical / Life-Threatening',
    3: 'High / Serious',
    2: 'Medium / Moderate',
    1: 'Low / Minor Disturbance',
  };

  static const Map<int, String> severityDescriptions = {
    4: 'Immediate danger to life. Requires emergency response.',
    3: 'Serious incident requiring urgent attention.',
    2: 'Moderate incident that needs timely response.',
    1: 'Minor disturbance or community concern.',
  };

  // ── Incident Categories ───────────────────────────────────────────────
  static const List<String> incidentCategories = [
    'Theft / Robbery',
    'Physical Assault',
    'Vehicular Accident',
    'Fire',
    'Flooding',
    'Noise Disturbance',
    'Vandalism',
    'Suspicious Activity',
    'Drug-Related',
    'Domestic Violence',
    'Public Disturbance',
    'Medical Emergency',
    'Other',
  ];

  // ── Report Statuses ───────────────────────────────────────────────────
  static const List<String> reportStatuses = [
    'pending',
    'in_progress',
    'resolved',
    'flagged',
  ];
}
