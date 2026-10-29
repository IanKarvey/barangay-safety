import 'package:flutter/widgets.dart';

import 'app_strings.dart';

/// Text for the unanswered-report escalation and the "How to Report" tutorial,
/// English and Filipino side by side.
///
/// Kept out of the very large [AppStrings] so each line sits next to its
/// translation while it is being written and reviewed. Same rules apply: plain
/// spoken Filipino for anything someone reads while frightened, and barangay
/// words (tanod, kapitan) left as they are.
///
/// The three escalation messages and the "good news" line are word-for-word the
/// ones approved in the panel's brief — change them there first.
class ResponseStrings {
  const ResponseStrings(this.language);

  final AppLanguage language;

  bool get _tl => language == AppLanguage.tagalog;
  String _t(String en, String tl) => _tl ? tl : en;

  // ── Resident: waiting for a response ────────────────────────────────────
  String get waitingTitle => _t(
        'Report sent. Waiting for barangay response.',
        'Naipadala na ang report. Naghihintay ng tugon ng barangay.',
      );
  String get waitingFor => _t('Waiting', 'Naghihintay');
  String nextUpdateIn(String clock) =>
      _t('Next update in $clock', 'Susunod na update sa $clock');
  String get allAlerted => _t(
        'The barangay has been alerted as far as it can be.',
        'Naabisuhan na ang buong barangay.',
      );
  String get callForHelpNow =>
      _t('Call for help now', 'Tumawag ng tulong ngayon');

  /// Messages 1–3, exactly as in the brief.
  String escalationMessage(int level) => switch (level) {
        1 => _t(
            "We're sorry, it looks like our barangay officials are currently busy. Please wait another 5 minutes.",
            'Pasensya na po, mukhang abala pa ang aming mga barangay official. Mangyaring maghintay ng 5 minuto pa.',
          ),
        2 => _t(
            'We\'re sorry for the inconvenience. We are now notifying the whole barangay so someone can take action quickly.',
            'Paumanhin po sa abala. Inaabisuhan na namin ang buong barangay para may agad na tumugon.',
          ),
        _ => _t(
            'It seems our barangay is busy right now. Please call these numbers for immediate help:',
            'Mukhang abala ang buong barangay ngayon. Mangyaring tumawag agad sa mga numerong ito:',
          ),
      };

  String escalationTitle(int level) => switch (level) {
        1 => _t('Our officials are busy', 'Abala pa ang mga official'),
        2 => _t('Alerting the whole barangay', 'Inaabisuhan ang buong barangay'),
        _ => _t('Please call for help', 'Mangyaring tumawag ng tulong'),
      };

  String get helpOnTheWayTitle =>
      _t('Help is on the way', 'May tumutugon na');
  String goodNews(String role, String name) => _t(
        'Good news! $role $name is now responding to your report.',
        'Magandang balita po! May tumutugon na sa inyong report: $role $name.',
      );
  String get viewReport => _t('View report', 'Tingnan ang report');
  String get dismiss => _t('Dismiss', 'Isara');
  String get tapToCall => _t('Tap to call', 'Pindutin para tumawag');
  String get usingStandardNumbers => _t(
        'These are the standard Lipa City emergency numbers.',
        'Ito ang mga karaniwang emergency number ng Lipa City.',
      );

  /// Position -> how the resident hears it.
  String roleLabel(String? position) => switch (position) {
        'captain' => _t('Barangay Captain', 'Kapitan ng Barangay'),
        'secretary' => _t('Barangay Secretary', 'Barangay Secretary'),
        'tanod' => _t('Tanod', 'Tanod'),
        'staff' => _t('Barangay Staff', 'Kawani ng Barangay'),
        _ => _t('Barangay Official', 'Barangay Official'),
      };

  // ── Officials: alerts, timer, claiming ──────────────────────────────────
  String alertTitle(int level) => switch (level) {
        1 => _t('Unanswered report', 'Walang sumasagot na report'),
        2 => _t('Still unanswered — everyone please check',
            'Wala pa ring sumasagot — pakitingnan po ng lahat'),
        _ => _t('UNATTENDED — last resort', 'WALANG TUMUGON — huling paraan'),
      };
  String get openReport => _t('Open report', 'Buksan ang report');
  String get unattendedBadge => _t('UNATTENDED', 'WALANG TUMUGON');
  String get imResponding => _t("I'm responding", 'Ako ang tutugon');
  String get claimedYou => _t(
        "You're now responding to this report.",
        'Ikaw na ang tutugon sa report na ito.',
      );
  String alreadyHandledBy(String name) =>
      _t('Already handled by $name', 'Hawak na ni $name');
  /// "5 minutes" / "30 seconds" — what the volunteer lock is measured in.
  String span(Duration d) {
    if (d.inSeconds >= 60 && d.inSeconds % 60 == 0) {
      final m = d.inMinutes;
      return _t(m == 1 ? '1 minute' : '$m minutes', '$m minuto');
    }
    final secs = d.inSeconds;
    return _t(secs == 1 ? '1 second' : '$secs seconds', '$secs segundo');
  }

  String volunteerOpensIn(String clock) =>
      _t("I'm responding — opens in $clock", 'Ako ang tutugon — bubukas sa $clock');
  String volunteerLockedHint(String span) => _t(
        'The barangay hall gets the first $span to answer. You can volunteer after that.',
        'Ang unang $span ay para sa barangay hall. Maaari kang magprisinta pagkatapos nito.',
      );
  String get volunteerOpenHint => _t(
        'Nobody has taken this yet. Tap to say you are on your way.',
        'Wala pang kumukuha nito. Pindutin kung papunta ka na.',
      );
  String claimTooEarly(String clock) => _t(
        'Not yet — you can volunteer in $clock.',
        'Hindi pa — maaari kang magprisinta sa loob ng $clock.',
      );
  String get claimNotAllowed => _t(
        "You can't take this report.",
        'Hindi mo maaaring kunin ang report na ito.',
      );
  String get claimNeedsUpdate => _t(
        'This needs the latest system update. Please tell your administrator.',
        'Kailangan nito ng pinakabagong update ng system. Pakisabihan ang administrator.',
      );
  String get claimFailed => _t(
        'Could not reach the server. Try again.',
        'Hindi maabot ang server. Subukan muli.',
      );
  String waitedLabel(String clock) => _t('Waiting $clock', 'Naghihintay $clock');

  // ── Tutorial ─────────────────────────────────────────────────────────────
  String get tutorialButton => 'Paano Mag-report? / How to Report';
  String get tutorialTitle => _t('How to Report', 'Paano Mag-report');
  String stepOf(int n, int total) => _t('Step $n of $total', 'Hakbang $n sa $total');
  String get next => _t('Next', 'Susunod');
  String get back => _t('Back', 'Bumalik');
  String get close => _t('Close', 'Isara');
  String get done => _t('Done', 'Tapos na');
  String get readAloud => _t('Read aloud', 'Basahin nang malakas');
  String get stopReading => _t('Stop reading', 'Itigil ang pagbasa');
  String get tryIt => _t('Try it — practice', 'Subukan — pagsasanay');
  String get practiceOnly => 'Practice only / Pagsasanay lang';
  String get practiceHint => _t(
        'This looks like the real thing, but nothing is sent to anyone.',
        'Kamukha ito ng totoo, pero walang ipinapadala kaninuman.',
      );
  String get practiceSubmitted => _t(
        'Great! In a real report, this would go to your barangay right away.',
        'Magaling! Sa totoong report, agad itong mapupunta sa barangay ninyo.',
      );
  String get practiceAgain => _t('Practice again', 'Magsanay muli');
  String get speechUnavailable => _t(
        'Read-aloud is not available on this phone.',
        'Hindi available ang pagbasa nang malakas sa phone na ito.',
      );
  String get helpHere => _t('How do I do this?', 'Paano ito gawin?');

  // Short labels drawn inside the tutorial's picture of the app.
  String get mockReportButton =>
      _t('Report an Incident', 'Mag-report ng Insidente');
  String get mockFire => _t('Fire', 'Sunog');
  String get mockTheft => _t('Theft', 'Nakawan');
  String get mockAccident => _t('Accident', 'Aksidente');
  String get mockMedical => _t('Medical', 'Medikal');
  String get mockNoise => _t('Noise', 'Ingay');
  String get mockOther => _t('Other', 'Iba pa');
  String get mockUseLocation => _t('Use my location', 'Gamitin ang lokasyon ko');
  String get mockWriteHere => _t('Write here…', 'Isulat dito…');
  String get mockAddPhoto => _t('Add photo', 'Magdagdag ng litrato');
  // Taken from the app's own strings, so the tutorial can never name a button
  // differently from the one on the screen.
  String get mockSubmit => AppStrings.of(language).submitReport;
  String get mockMyReports => AppStrings.of(language).myReports;
  String get mockHome => AppStrings.of(language).home;
  String get mockOnTheWay => _t('On the way', 'Papunta na');
  String get mockTapHere => _t('Tap here', 'Pindutin dito');

  // Practice mode.
  String get practiceTitle => _t('Practice', 'Pagsasanay');
  String get practiceStep1 => _t('1. Tap what happened', '1. Pindutin ang nangyari');
  String get practiceStep2 =>
      _t('2. Write a few words (you can skip)', '2. Magsulat ng ilang salita (puwedeng laktawan)');
  String get practiceStep3 => _t('3. Tap Submit', '3. Pindutin ang Ipadala');
  String get practiceSkipWriting => _t('Skip', 'Laktawan');
  String get practiceTypeHint =>
      _t('For example: "Smoke from the house next door"',
          'Halimbawa: "May usok sa kabilang bahay"');

  static const int tutorialStepCount = 7;

  String stepTitle(int i) => switch (i) {
        0 => _t('Tap the Report button', 'Pindutin ang Report button'),
        1 => _t('Choose what happened', 'Piliin kung ano ang nangyari'),
        2 => _t('Confirm your location', 'Tiyakin ang iyong lokasyon'),
        3 => _t('Write what happened', 'Isulat ang nangyari'),
        4 => _t('Tap Submit Report', 'Pindutin ang Ipadala ang Report'),
        5 => _t('What happens next', 'Ano ang susunod'),
        _ => _t('Check your report', 'Tingnan ang report mo'),
      };

  String stepText(int i) => switch (i) {
        0 => _t(
            'On the first screen, tap the big blue button that says "Report an Incident".',
            'Sa unang screen, pindutin ang malaking asul na button na may nakasulat na "Report an Incident".',
          ),
        1 => _t(
            'Tap the picture that matches the problem, like Fire or Theft.',
            'Pindutin ang larawan na tugma sa nangyari, tulad ng Sunog o Nakawan.',
          ),
        2 => _t(
            'Allow the app to find where you are. Check that the pin is in the right place.',
            'Payagan ang app na hanapin kung nasaan ka. Tingnan kung tama ang lugar ng pin.',
          ),
        3 => _t(
            'Type a few words about what happened. You can also add a photo.',
            'Magsulat ng ilang salita tungkol sa nangyari. Puwede ring magdagdag ng litrato.',
          ),
        4 => _t(
            'Tap the green "Submit Report" button. Your report goes to the barangay right away.',
            'Pindutin ang berdeng "Ipadala ang Report" button. Agad na mapupunta sa barangay ang report mo.',
          ),
        5 => _t(
            'You will see a timer. If nobody answers in 5 minutes, we tell you and alert more people. After 15 minutes you will see emergency numbers to call.',
            'Makikita mo ang timer. Kung walang sumagot sa loob ng 5 minuto, sasabihan ka namin at mas maraming tao ang aalertuhan. Pagkalipas ng 15 minuto, makikita mo ang mga numerong tatawagan.',
          ),
        _ => _t(
            'Open "My Reports" at the bottom any time to see if someone is on the way.',
            'Buksan ang "Mga Report Ko" sa ibaba anumang oras para makita kung may papunta na.',
          ),
      };
}

extension ResponseStringsX on BuildContext {
  /// `context.rs.waitingTitle` — follows the app language and rebuilds with it.
  ResponseStrings get rs {
    final scope = dependOnInheritedWidgetOfExactType<AppStringsScope>();
    return ResponseStrings(scope?.language ?? AppLanguage.english);
  }
}
