import '../config/app_config.dart';

/// Severity, and the category that decides it.
///
/// ## The scale
///
/// **4 is the worst, 1 is the least.** Chosen by the owner on 2026-08-25. The
/// app previously ran the other way — 1 meant Critical — and the flip touched
/// eleven files, because the raw integer was compared against literals all
/// over the codebase (`severityLevel == 1`, `<= 2`, `!= 1`).
///
/// This class exists so that never happens twice. Nothing outside it should
/// compare a severity to a number: ask [isCritical], [isUrgent] or [rank]
/// instead. If the scale is ever reversed again it is reversed here, once.
///
/// ## Why the reporter no longer picks it
///
/// Severity used to be a slider the reporter set themselves, and later a value
/// the AI suggested. Both were wrong for the same reason: a person in an
/// emergency should not be triaging their own emergency, and two people
/// reporting the same fire would file it at two different levels. Officials
/// then had to second-guess every number they saw.
///
/// Now the category carries the level. Choosing "Fire" *is* choosing Critical.
/// It is not editable — not by the reporter, not by the AI — so the same event
/// always arrives at the same level, and an official reading the queue can
/// trust the ordering.
class Severity {
  const Severity._();

  /// Immediate danger to life.
  static const int critical = 4;

  /// Serious, needs an urgent response.
  static const int high = 3;

  /// Needs a timely response.
  static const int medium = 2;

  /// Minor disturbance.
  static const int low = 1;

  /// Every level, worst first — the order queues and pickers should show.
  static const List<int> allWorstFirst = [critical, high, medium, low];

  /// Used when a level is missing or unrecognised.
  ///
  /// Deliberately [medium] and not [critical]: an unknown level that defaults
  /// to Critical would fire the §14 full blast at the whole barangay hall for
  /// a corrupt row, and an alert people learn to ignore is worse than no
  /// alert. Nor [low], which would bury a real report.
  static const int fallback = medium;

  /// Whether this level triggers the §14 mass alert.
  static bool isCritical(int level) => level >= critical;

  /// Whether this level belongs in the "needs attention now" counters on the
  /// dashboards — Critical and High together.
  static bool isUrgent(int level) => level >= high;

  /// 0.0 (least severe) to 1.0 (most severe), for meters and progress bars.
  static double fraction(int level) => clamp(level) / critical;

  /// Forces any incoming value onto the scale.
  static int clamp(int level) =>
      level < low ? fallback : (level > critical ? critical : level);

  // ── Category → level ──────────────────────────────────────────────────
  //
  // The judgement calls, stated rather than buried, because these decide who
  // gets woken up:
  //
  //   * Fire and Medical Emergency are Critical without argument — minutes
  //     decide outcomes and both can escalate to lives lost.
  //   * Physical Assault and Domestic Violence are Critical because both mean
  //     a person is being hurt *now*. Domestic violence in particular is a
  //     category where under-triaging is how people die, and RA 9262 treats it
  //     as urgent regardless of visible injury.
  //   * Vehicular Accident is High, not Critical. Most are damage-only, and
  //     making every fender-bender blast the entire hall would train people to
  //     ignore the blast. A serious one gets raised by the official reviewing
  //     it.
  //   * Theft / Robbery is High: a robbery in progress is dangerous, but most
  //     reports arrive after the fact.
  //   * Noise Disturbance is the only Low. It is the textbook non-emergency
  //     and the one the owner named.
  //
  // Officials can still re-rank an individual incident after the fact. What
  // is fixed is the level it *arrives* at.
  static const Map<String, int> _byCategory = {
    'Fire': critical,
    'Medical Emergency': critical,
    'Physical Assault': critical,
    'Domestic Violence': critical,
    'Vehicular Accident': high,
    'Theft / Robbery': high,
    'Flooding': high,
    'Drug-Related': high,
    'Suspicious Activity': medium,
    'Vandalism': medium,
    'Public Disturbance': medium,
    'Other': medium,
    'Noise Disturbance': low,
  };

  /// The level [category] always carries.
  ///
  /// An unknown category falls back to [fallback] rather than throwing: a
  /// category added in the database before it is added here must still be
  /// reportable, and must not silently arrive as an emergency.
  static int forCategory(String? category) {
    if (category == null) return fallback;
    return _byCategory[category] ?? fallback;
  }

  /// True when the mapping covers every category the app offers.
  ///
  /// Exposed for the test that guards against someone adding a category to
  /// [AppConfig.incidentCategories] and forgetting to triage it — at which
  /// point it would quietly become Medium.
  static List<String> get uncoveredCategories => AppConfig.incidentCategories
      .where((c) => !_byCategory.containsKey(c))
      .toList();
}
