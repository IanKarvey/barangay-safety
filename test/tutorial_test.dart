import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:barangay_safety_app/l10n/app_strings.dart';
import 'package:barangay_safety_app/l10n/response_strings.dart';
import 'package:barangay_safety_app/screens/resident/practice_report_screen.dart';
import 'package:barangay_safety_app/screens/resident/report_tutorial_screen.dart';
import 'package:barangay_safety_app/services/speech_service.dart';
import 'package:barangay_safety_app/services/tutorial_service.dart';
import 'package:barangay_safety_app/utils/theme.dart';
import 'package:barangay_safety_app/widgets/how_to_report_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/render.dart';

class _Speech implements SpeechService {
  _Speech({this.hasVoice = true});
  final bool hasVoice;
  final spoken = <(String, AppLanguage)>[];
  int stops = 0;
  final _speaking = ValueNotifier(false);

  @override
  ValueListenable<bool> get speaking => _speaking;

  @override
  Future<bool> speak(String text, AppLanguage language) async {
    spoken.add((text, language));
    if (!hasVoice) return false;
    _speaking.value = true;
    return true;
  }

  @override
  Future<void> stop() async {
    stops++;
    _speaking.value = false;
  }

  @override
  void dispose() {}
}

class _Log implements TutorialLog {
  final opens = <(String, bool)>[];
  final progress_ = <(int, bool)>[];

  @override
  Future<String?> opened({required String source, bool practice = false}) async {
    opens.add((source, practice));
    return 'log-${opens.length}';
  }

  @override
  Future<void> progress(String? logId, {required int stepsViewed, required bool completed}) async {
    progress_.add((stepsViewed, completed));
  }
}

Widget _host(Widget child, {AppLanguage lang = AppLanguage.english, double textScale = 1.0}) =>
    AppStringsScope(
      language: lang,
      strings: AppStrings.of(lang),
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: c!,
        ),
        home: RepaintBoundary(key: snapKey, child: child),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
}

void main() {
  setUpAll(loadRealFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('first-time auto-show bookkeeping', () {
    test('a new person has not seen it; after marking, they have', () async {
      expect(await TutorialService.hasSeen('rita'), isFalse);
      await TutorialService.markSeen('rita');
      expect(await TutorialService.hasSeen('rita'), isTrue);
    });

    test('it is remembered per person, not per phone', () async {
      await TutorialService.markSeen('rita');
      expect(await TutorialService.hasSeen('lolo-ben'), isFalse);
    });
  });

  group('the seven steps', () {
    testWidgets('every step has a picture, a title and text in both languages', (tester) async {
      for (final lang in AppLanguage.values) {
        useSize(tester, const Size(390, 844));
        await tester.pumpWidget(_host(
          ReportTutorialScreen(key: ValueKey(lang), speech: _Speech(), log: _Log()),
          lang: lang,
        ));
        await _settle(tester);
        final rs = ResponseStrings(lang);
        for (var i = 0; i < ResponseStrings.tutorialStepCount; i++) {
          expect(find.text(rs.stepTitle(i)), findsOneWidget, reason: '$lang step $i');
          expect(find.text(rs.stepText(i)), findsOneWidget);
          expect(find.text(rs.stepOf(i + 1, 7)), findsOneWidget);
          expect(tester.takeException(), isNull, reason: '$lang step $i');
          await snap(tester, 'tutorial_${lang.code}_${i + 1}');
          if (i < 6) {
            await tester.tap(find.text(rs.next));
            await _settle(tester);
          }
        }
      }
    });

    testWidgets('Next, Back and Close', (tester) async {
      useSize(tester, const Size(390, 844));
      final log = _Log();
      await tester.pumpWidget(_host(ReportTutorialScreen(speech: _Speech(), log: log)));
      await _settle(tester);

      expect(find.text('Back'), findsNothing); // nothing before step 1
      await tester.tap(find.text('Next'));
      await _settle(tester);
      expect(find.text('Step 2 of 7'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await _settle(tester);
      expect(find.text('Step 1 of 7'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await _settle(tester);
      await tester.tap(find.text('Next'));
      await _settle(tester);
      await tester.tap(find.text('Close'));
      await _settle(tester);
      // Closed early: recorded as not completed, having seen 3 steps.
      expect(log.progress_.last, (3, false));
    });

    testWidgets('finishing records that it was completed', (tester) async {
      useSize(tester, const Size(390, 844));
      final log = _Log();
      await tester.pumpWidget(_host(ReportTutorialScreen(speech: _Speech(), log: log)));
      await _settle(tester);
      for (var i = 0; i < 6; i++) {
        await tester.tap(find.text('Next'));
        await _settle(tester);
      }
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Try it — practice'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await _settle(tester);
      expect(log.progress_.last, (7, true));
      expect(log.opens.single, ('button', false));
    });

    testWidgets('the form\'s "?" opens it at the step the person is on', (tester) async {
      useSize(tester, const Size(390, 844));
      final log = _Log();
      await tester.pumpWidget(_host(
        ReportTutorialScreen(source: 'form_help', initialStep: 2, speech: _Speech(), log: log),
      ));
      await _settle(tester);
      expect(find.text('Step 3 of 7'), findsOneWidget);
      expect(find.text('Confirm your location'), findsOneWidget);
      expect(log.opens.single.$1, 'form_help');
    });
  });

  group('built for people who forget and who see poorly', () {
    testWidgets('title is 26, body is 20, and buttons are at least 56 tall', (tester) async {
      useSize(tester, const Size(390, 844));
      await tester.pumpWidget(_host(ReportTutorialScreen(speech: _Speech(), log: _Log())));
      await _settle(tester);

      final title = tester.widget<Text>(find.text('Tap the Report button'));
      expect(title.style!.fontSize, greaterThanOrEqualTo(24));
      final body = tester.widget<Text>(find.textContaining('big blue button'));
      expect(body.style!.fontSize, greaterThanOrEqualTo(18));

      for (final label in ['Next', 'Close', 'Read aloud']) {
        final box = tester.getRect(find
            .ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton))
            .first);
        expect(box.height, greaterThanOrEqualTo(56), reason: label);
      }
    });

    testWidgets('survives the biggest system font setting without overflowing', (tester) async {
      for (final scale in [1.5, 2.0, 3.0]) {
        useSize(tester, const Size(360, 640));
        await tester.pumpWidget(_host(
          ReportTutorialScreen(initialStep: 5, speech: _Speech(), log: _Log()),
          textScale: scale,
        ));
        await _settle(tester);
        expect(tester.takeException(), isNull, reason: 'font scale $scale');
        expect(find.text('Next'), findsOneWidget);
      }
    });

    testWidgets('the home button: big, high contrast, with the exact label', (tester) async {
      useSize(tester, const Size(390, 844));
      var tapped = 0;
      await tester.pumpWidget(_host(Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: HowToReportButton(onTap: () => tapped++),
        ),
      )));
      await _settle(tester);
      expect(find.text('Paano Mag-report? / How to Report'), findsOneWidget);
      final box = tester.getRect(find.byType(HowToReportButton));
      expect(box.height, greaterThanOrEqualTo(56));
      final text = tester.widget<Text>(find.text('Paano Mag-report? / How to Report'));
      expect(text.style!.fontSize, greaterThanOrEqualTo(18));
      await snap(tester, 'tutorial_home_button');
      await tester.tap(find.byType(HowToReportButton));
      expect(tapped, 1);
    });
  });

  group('read aloud', () {
    testWidgets('speaks the title and text in English', (tester) async {
      useSize(tester, const Size(390, 844));
      final speech = _Speech();
      await tester.pumpWidget(_host(ReportTutorialScreen(speech: speech, log: _Log())));
      await _settle(tester);
      await tester.tap(find.text('Read aloud'));
      await _settle(tester);
      expect(speech.spoken.single.$1,
          'Tap the Report button. On the first screen, tap the big blue button that says "Report an Incident".');
      expect(speech.spoken.single.$2, AppLanguage.english);
      // While it speaks, the button offers to stop.
      expect(find.text('Stop reading'), findsOneWidget);
    });

    testWidgets('speaks Filipino when the app is in Filipino', (tester) async {
      useSize(tester, const Size(390, 844));
      final speech = _Speech();
      await tester.pumpWidget(_host(ReportTutorialScreen(speech: speech, log: _Log()), lang: AppLanguage.tagalog));
      await _settle(tester);
      await tester.tap(find.text('Basahin nang malakas'));
      await _settle(tester);
      expect(speech.spoken.single.$2, AppLanguage.tagalog);
      expect(speech.spoken.single.$1, startsWith('Pindutin ang Report button.'));
    });

    testWidgets('stops speaking when the person moves to the next step', (tester) async {
      useSize(tester, const Size(390, 844));
      final speech = _Speech();
      await tester.pumpWidget(_host(ReportTutorialScreen(speech: speech, log: _Log())));
      await _settle(tester);
      await tester.tap(find.text('Read aloud'));
      await _settle(tester);
      final before = speech.stops;
      await tester.tap(find.text('Next'));
      await _settle(tester);
      expect(speech.stops, greaterThan(before));
      expect(find.text('Read aloud'), findsOneWidget);
    });

    testWidgets('a phone with no voice for the language says so instead of staying silent', (tester) async {
      useSize(tester, const Size(390, 844));
      await tester.pumpWidget(_host(ReportTutorialScreen(speech: _Speech(hasVoice: false), log: _Log()),
          lang: AppLanguage.tagalog));
      await _settle(tester);
      await tester.tap(find.text('Basahin nang malakas'));
      await _settle(tester);
      expect(find.textContaining('Hindi available ang pagbasa'), findsOneWidget);
    });

    test('voices tried, best first', () {
      expect(FlutterTtsSpeech.localesFor(AppLanguage.tagalog), ['fil-PH', 'tl-PH']);
      expect(FlutterTtsSpeech.localesFor(AppLanguage.english).first, 'en-PH');
    });
  });

  group('practice mode', () {
    // Mounted with NO providers and NO Supabase at all: if the screen tried to
    // submit anything it could not even start. That is the proof it is sealed.
    testWidgets('a full run-through sends nothing and is always labelled', (tester) async {
      useSize(tester, const Size(390, 844));
      final log = _Log();
      await tester.pumpWidget(_host(PracticeReportScreen(log: log)));
      await _settle(tester);

      expect(find.text('Practice only / Pagsasanay lang'), findsOneWidget);
      expect(log.opens.single, ('button', true)); // recorded as practice

      await tester.tap(find.text('Noise Disturbance'));
      await _settle(tester);
      expect(find.text('Practice only / Pagsasanay lang'), findsOneWidget);
      expect(find.text('2. Write a few words (you can skip)'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Loud music next door');
      await tester.tap(find.text('Next'));
      await _settle(tester);
      expect(find.text('3. Tap Submit'), findsOneWidget);
      expect(find.text('Submit Report'), findsOneWidget);
      expect(find.text('Loud music next door'), findsOneWidget);

      await tester.tap(find.text('Submit Report'));
      await _settle(tester);
      expect(find.textContaining('this would go to your barangay'), findsOneWidget);
      expect(find.text('Practice only / Pagsasanay lang'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await snap(tester, 'practice_done');

      await tester.tap(find.text('Practice again'));
      await _settle(tester);
      expect(find.text('1. Tap what happened'), findsOneWidget);
    });

    testWidgets('the practice choices are calm categories, not ones the real app diverts', (tester) async {
      useSize(tester, const Size(390, 844));
      await tester.pumpWidget(_host(PracticeReportScreen(log: _Log())));
      await _settle(tester);
      // Fire, theft, accident send the real app to a "call this agency" screen.
      expect(find.text('Fire'), findsNothing);
      expect(find.text('Theft / Robbery'), findsNothing);
      expect(find.text('Vehicular Accident'), findsNothing);
    });
  });
}
