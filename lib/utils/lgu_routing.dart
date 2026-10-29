import '../config/app_config.dart';
import 'severity.dart';

/// Who a reporter should call for an incident the barangay cannot handle.
enum LguAgency { fire, police, medical, disaster, lto }

/// One number a reporter can call.
typedef LguNumber = ({String dial, String display});

/// One agency a reporter can call, with every number it has.
class LguOption {
  const LguOption({required this.agency, required this.numbers})
      : assert(numbers.length > 0);

  final LguAgency agency;

  /// The first is the big call button; the rest are shown smaller beneath it,
  /// for when the first line is busy.
  final List<LguNumber> numbers;

  LguNumber get primary => numbers.first;
  List<LguNumber> get alternates => numbers.skip(1).toList();
}

/// Where to send a reporter instead of letting them file.
///
/// Usually one agency. A vehicular accident has two — LTO for the accident
/// itself, an ambulance if it turns out someone is hurt — because which one is
/// needed is not known until the person is looking at the scene, so they are
/// offered both rather than guessed at.
class LguReferral {
  const LguReferral({required this.options, this.allowsReporting = false})
      : assert(options.length > 0);

  /// Whether the person may still file this with the barangay.
  ///
  /// False for a fire or an accident, where filing would reach no one able to
  /// help. True for the categories the barangay genuinely handles *and* the
  /// police are worth knowing about — see [LguRouting.barangayStillHandles]. In
  /// that case the pop-up is advice with a call button, and a clear way to
  /// carry on reporting.
  final bool allowsReporting;

  /// In display order; the first is the headline.
  final List<LguOption> options;

  LguOption get _first => options.first;

  /// The headline agency — drives the pop-up's colour and icon.
  LguAgency get agency => _first.agency;

  /// Further agencies offered below the headline one.
  List<LguOption> get others => options.skip(1).toList();

  // Shortcuts to the headline agency's numbers.
  List<LguNumber> get numbers => _first.numbers;
  LguNumber get primary => _first.primary;
  List<LguNumber> get alternates => _first.alternates;
  String get dial => primary.dial;
  String get display => primary.display;
}

/// The rule that stops the barangay being asked to handle what it cannot.
///
/// ## The rule
///
/// A barangay hall has tanods, not fire trucks or ambulances. A report that
/// says "fire" or "car accident" gives the reporter the feeling help is coming
/// while the people it reached cannot actually provide it, and in an emergency
/// that false reassurance costs minutes. So for anything at **High or Critical**
/// the app does not take a report: it tells the person this is beyond the
/// barangay and puts the right number one tap away.
///
/// Low and Medium (noise, vandalism, suspicious activity, public disturbance,
/// "other") are exactly what a barangay is for, so those still file normally.
///
/// ## Why it is derived from severity rather than listed
///
/// Severity is already decided per category in one place ([Severity]), and
/// "the barangay can't handle it" tracks it closely. Deriving the rule means a
/// category added to the app is triaged once and routed correctly with no
/// second list to forget. The one thing that is a separate decision is *which
/// agency* to call, because that is not a function of how severe it is.
///
/// ## The two kinds of pop-up
///
/// *Blocking* — fire, accidents, assault, theft, flooding, medical. The person
/// is told to call and no report can be started.
///
/// *Advisory* — domestic violence and drug-related ([barangayStillHandles]).
/// The barangay genuinely handles these, so the person may still report, but the
/// police number is shown first because someone in danger right now needs it
/// more than they need a form.
///
/// ## Moving the line
///
/// The cut-off is [Severity.isUrgent] (High and above). To make another category
/// reportable-with-advice, add it to [barangayStillHandles]. To stop showing a
/// pop-up for a category at all, change its level in `severity.dart`, which also
/// changes how it is ranked.
class LguRouting {
  const LguRouting._();

  /// Categories that are serious enough that the police number is shown, but
  /// which the barangay can and does handle — so the person may still report
  /// them. Domestic violence is partly the Punong Barangay's own job (Barangay
  /// Protection Orders under RA 9262) and drug cases start with the barangay's
  /// anti-drug abuse council; cutting residents off from reporting either to the
  /// hall would be the wrong answer, but the police number must still be there.
  ///
  /// Everything else at High or Critical is blocked: a fire report reaches no
  /// one who can put out a fire.
  static const Set<String> barangayStillHandles = {
    'Domestic Violence',
    'Drug-Related',
  };

  /// Whether a referral pop-up is shown for [category]: High and Critical
  /// categories. It either blocks the report ([blocksReporting]) or, for
  /// [barangayStillHandles], advises alongside it.
  ///
  /// An unknown or missing category gets no pop-up: [Severity] files it as
  /// Medium, and refusing to let someone report something merely because it was
  /// added to the database before the app learned its name would be worse than
  /// letting it through.
  static bool shouldRedirect(String? category) =>
      category != null && Severity.isUrgent(Severity.forCategory(category));

  /// The agencies for [category], most relevant first.
  ///
  /// A vehicular accident is LTO first (the accident, the vehicles, the road)
  /// and an ambulance second, for the case where it is worse than it looks.
  static List<LguAgency> agenciesFor(String category) => switch (category) {
        'Fire' => [LguAgency.fire],
        'Medical Emergency' => [LguAgency.medical],
        'Flooding' => [LguAgency.disaster],
        'Vehicular Accident' => [LguAgency.lto, LguAgency.medical],
        // Assaults, domestic violence, theft and drugs are police matters.
        _ => [LguAgency.police],
      };

  /// The headline agency for [category].
  static LguAgency agencyFor(String category) => agenciesFor(category).first;

  static List<LguNumber> _numbersFor(LguAgency agency) => switch (agency) {
        LguAgency.fire => AppConfig.referralFire,
        LguAgency.police => AppConfig.referralPolice,
        LguAgency.medical => AppConfig.referralMedical,
        LguAgency.disaster => AppConfig.referralDisaster,
        LguAgency.lto => AppConfig.referralLto,
      };

  /// The referral for [category], or null when the barangay can handle it.
  ///
  /// An agency with no number configured is left out rather than shown with a
  /// guess: a button that dials the wrong office in an emergency is worse than
  /// one that is not there. If *every* agency for a category is missing a
  /// number, 911 is offered so the person is never left with nothing.
  static LguReferral? referralFor(String? category) {
    if (!shouldRedirect(category)) return null;

    final options = [
      for (final agency in agenciesFor(category!))
        if (_numbersFor(agency).isNotEmpty)
          LguOption(agency: agency, numbers: _numbersFor(agency)),
    ];

    if (options.isEmpty) {
      return LguReferral(
        options: [
          LguOption(
            agency: agencyFor(category),
            numbers: const [AppConfig.nationalEmergency],
          ),
        ],
        allowsReporting: barangayStillHandles.contains(category),
      );
    }
    return LguReferral(
      options: options,
      allowsReporting: barangayStillHandles.contains(category),
    );
  }

  /// Whether filing [category] is blocked outright (the person is sent to call
  /// instead), as opposed to merely being shown the number.
  static bool blocksReporting(String? category) {
    final referral = referralFor(category);
    return referral != null && !referral.allowsReporting;
  }
}
