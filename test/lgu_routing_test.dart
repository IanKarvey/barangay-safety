import 'package:barangay_safety_app/config/app_config.dart';
import 'package:barangay_safety_app/l10n/app_strings.dart';
import 'package:barangay_safety_app/providers/language_provider.dart';
import 'package:barangay_safety_app/utils/lgu_routing.dart';
import 'package:barangay_safety_app/widgets/lgu_referral_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('which categories are referred out', () {
    // Pinned as explicit lists on purpose: this is the panel's rule, and a
    // change to it — including one caused by re-ranking a category in
    // severity.dart — should have to be a visible edit to this test.
    // Blocked: the person is sent to call and no report can be started.
    const referred = {
      'Fire',
      'Medical Emergency',
      'Physical Assault',
      'Vehicular Accident',
      'Theft / Robbery',
      'Flooding',
    };
    // Advisory: the police number is shown, but the barangay still takes the
    // report (decided 2026-10-15: both are partly the barangay's own job).
    const advised = {'Domestic Violence', 'Drug-Related'};
    const stayWithBarangay = {
      'Suspicious Activity',
      'Vandalism',
      'Public Disturbance',
      'Noise Disturbance',
      'Other',
    };

    test('these categories are blocked: a pop-up and no report', () {
      for (final c in referred) {
        expect(LguRouting.shouldRedirect(c), isTrue, reason: c);
        expect(LguRouting.blocksReporting(c), isTrue, reason: c);
        expect(LguRouting.referralFor(c)!.allowsReporting, isFalse, reason: c);
      }
    });

    test('domestic violence and drug-related show the police but still allow '
        'a report', () {
      for (final c in advised) {
        final r = LguRouting.referralFor(c);
        expect(r, isNotNull, reason: '$c should still show the police number');
        expect(r!.allowsReporting, isTrue, reason: c);
        expect(LguRouting.blocksReporting(c), isFalse, reason: c);
        expect(r.agency, LguAgency.police, reason: c);
        expect(r.dial, '+639000000001', reason: c);
      }
    });

    test('Medium and Low categories are still reportable', () {
      for (final c in stayWithBarangay) {
        expect(LguRouting.shouldRedirect(c), isFalse, reason: c);
        expect(LguRouting.blocksReporting(c), isFalse, reason: c);
        expect(LguRouting.referralFor(c), isNull, reason: c);
      }
    });

    test('the three lists cover every category the app offers', () {
      final all = {...referred, ...advised, ...stayWithBarangay};
      expect(all, AppConfig.incidentCategories.toSet(),
          reason: 'a category was added or removed without deciding its routing');
    });

    test('an unknown or missing category is not blocked', () {
      expect(LguRouting.shouldRedirect(null), isFalse);
      expect(LguRouting.shouldRedirect('Something New'), isFalse,
          reason: 'unknown files as Medium; blocking it would stop a real report');
    });
  });

  group('which agency is called', () {
    test('each category goes to the right agency', () {
      expect(LguRouting.agencyFor('Fire'), LguAgency.fire);
      expect(LguRouting.agencyFor('Medical Emergency'), LguAgency.medical);
      expect(LguRouting.agencyFor('Flooding'), LguAgency.disaster);
      expect(LguRouting.agenciesFor('Vehicular Accident'),
          [LguAgency.lto, LguAgency.medical]);
      for (final c in [
        'Physical Assault',
        'Domestic Violence',
        'Theft / Robbery',
        'Drug-Related',
      ]) {
        expect(LguRouting.agencyFor(c), LguAgency.police, reason: c);
      }
    });

    test('fire dials the BFP landline', () {
      final r = LguRouting.referralFor('Fire')!;
      expect(r.dial, '+63437574168');
      expect(r.display, '(043) 757 4168');
    });

    test('a vehicular accident offers LTO first, then an ambulance', () {
      final r = LguRouting.referralFor('Vehicular Accident')!;

      expect(r.options.map((o) => o.agency), [LguAgency.lto, LguAgency.medical]);
      expect(r.options.first.primary.dial, '+63437562345');
      expect(r.options.first.primary.display, '(043) 756 2345');
      // The ambulance is the CDRRMO rescue lines, same as a medical emergency.
      expect(r.options.last.numbers.map((n) => n.dial),
          LguRouting.referralFor('Medical Emergency')!.numbers.map((n) => n.dial));
    });

    test('every other category offers exactly one agency', () {
      for (final c in AppConfig.incidentCategories) {
        final r = LguRouting.referralFor(c);
        if (r == null || c == 'Vehicular Accident') continue;
        expect(r.options.length, 1, reason: c);
      }
    });

    test('a medical emergency dials the same CDRRMO lines as flooding', () {
      final medical = LguRouting.referralFor('Medical Emergency')!;
      final flood = LguRouting.referralFor('Flooding')!;
      expect(medical.agency, LguAgency.medical);
      expect(medical.numbers.map((n) => n.dial),
          flood.numbers.map((n) => n.dial));
      expect(medical.dial, '+639000000002');
    });

    test('flooding offers all three CDRRMO numbers, mobile first', () {
      final r = LguRouting.referralFor('Flooding')!;
      expect(r.numbers.map((n) => n.dial),
          ['+639000000002', '+63437560217', '+63437575164']);
      expect(r.alternates.length, 2);
    });
  });

  group('the configured numbers', () {
    // A number is only useful if the phone can actually dial it. The police
    // number was first supplied with +64 (New Zealand) where +63 (Philippines)
    // was meant — this is the check that would have caught it.
    final dialable = RegExp(r'^(\+63\d{9,10}|911)$');

    test('every number is a Philippine number or 911', () {
      final all = [
        ...AppConfig.referralFire,
        ...AppConfig.referralPolice,
        ...AppConfig.referralMedical,
        ...AppConfig.referralDisaster,
        ...AppConfig.referralLto,
      ];
      for (final n in all) {
        expect(dialable.hasMatch(n.dial), isTrue,
            reason: '"${n.dial}" is not +63… or 911');
        expect(n.display, isNotEmpty);
      }
    });

    test('every referred category resolves to at least one number', () {
      for (final c in AppConfig.incidentCategories) {
        final r = LguRouting.referralFor(c);
        if (r != null) expect(r.numbers, isNotEmpty, reason: c);
      }
    });
  });

  group('the pop-up', () {
    // The pop-up has looping animations (a ripple, a breathing button), so a
    // test that waits for it to settle would wait forever. Reduce-motion is the
    // switch the app itself honours, so tests use it by default and one test
    // below turns it off to check the animated version.
    Future<void> show(
      WidgetTester tester,
      String category, {
      bool reduceMotion = true,
      void Function(bool?)? onResult,
    }) async {
      // Tall enough that nothing is scrolled out of reach; the advisory pop-up
      // has an extra button.
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: reduceMotion);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LanguageProvider(),
          child: Consumer<LanguageProvider>(
            builder: (context, lang, _) => AppStringsScope(
              language: lang.language,
              strings: lang.strings,
              child: MaterialApp(
                home: Builder(
                  builder: (context) => Scaffold(
                    body: Center(
                      child: ElevatedButton(
                        onPressed: () => showLguReferralSheet(
                          context,
                          category: category,
                          referral: LguRouting.referralFor(category)!,
                        ).then((r) => onResult?.call(r)),
                        child: const Text('open'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      if (reduceMotion) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump(const Duration(milliseconds: 1500));
      }
    }

    testWidgets('fire shows the BFP number and a way back', (tester) async {
      await show(tester, 'Fire');

      expect(find.text('This needs emergency responders'), findsOneWidget);
      expect(find.text('(043) 757 4168'), findsOneWidget);
      expect(find.textContaining('Fire Department (BFP)'), findsWidgets);
      expect(find.text('Choose another category'), findsOneWidget);
    });

    testWidgets('flooding shows all three CDRRMO numbers', (tester) async {
      await show(tester, 'Flooding');

      expect(find.text('+63 900 000 0002'), findsOneWidget);
      expect(find.text('(043) 756 0217'), findsOneWidget);
      expect(find.text('(043) 757 5164'), findsOneWidget);
    });

    testWidgets(
        'if the phone cannot place the call, it copies the number and says so',
        (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      // No dialer exists under test, so the launch fails — which is exactly the
      // case on an emulator, a tablet, or a phone with no phone app.
      await show(tester, 'Fire');
      await tester.tap(find.text('(043) 757 4168'));
      await tester.pump();
      // The platform channel replies on the real event loop, not the fake test
      // clock, so give it one genuine turn before pumping the notice in.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      expect(find.textContaining('No phone app on this device'), findsOneWidget,
          reason: 'the notice must be inside the dialog, not a hidden snackbar');
      expect(copied, ['+63437574168'],
          reason: 'the dialable form is copied so it pastes into any phone app');
    });

    testWidgets('the copy button copies without trying to call', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await show(tester, 'Fire');
      await tester.tap(find.byTooltip('Copy').first);
      await tester.pumpAndSettle();

      expect(copied, ['+63437574168']);
      expect(find.text('Number copied'), findsOneWidget);
      expect(find.textContaining('No phone app'), findsNothing,
          reason: 'copying is not a failed call');
    });

    testWidgets('a vehicular accident offers LTO and an ambulance together',
        (tester) async {
      await show(tester, 'Vehicular Accident');

      // The sentence names both agencies.
      expect(
        find.textContaining(
            'Land Transportation Office (LTO) or Ambulance / Emergency Medical'),
        findsOneWidget,
      );
      // LTO's number, and the ambulance's (CDRRMO) numbers, all on screen.
      expect(find.text('(043) 756 2345'), findsOneWidget);
      expect(find.text('+63 900 000 0002'), findsOneWidget);
      // The ambulance is introduced as the "if it's worse" option.
      expect(find.text('IF ANYONE IS HURT'), findsOneWidget);
    });

    testWidgets('the animated version renders and keeps running without errors',
        (tester) async {
      await show(tester, 'Fire', reduceMotion: false);

      expect(find.text('This needs emergency responders'), findsOneWidget);
      expect(find.text('(043) 757 4168'), findsOneWidget);

      // Let the looping ripple and breathing run for several seconds.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 700));
      }
      expect(find.text('(043) 757 4168'), findsOneWidget);
    });

    testWidgets('domestic violence is advice, with a way to keep reporting',
        (tester) async {
      await show(tester, 'Domestic Violence');

      expect(find.text('This may need emergency responders too'),
          findsOneWidget);
      expect(find.text('+63 900 000 0001'), findsOneWidget,
          reason: 'the police number must still be one tap away');
      expect(find.text('Report to the barangay'), findsOneWidget);
    });

    testWidgets('"Report to the barangay" hands back true', (tester) async {
      bool? result;
      await show(tester, 'Drug-Related', onResult: (r) => result = r);

      await tester.tap(find.text('Report to the barangay'));
      await tester.pumpAndSettle();

      expect(result, isTrue, reason: 'the form selects the category on true');
      expect(find.text('This may need emergency responders too'), findsNothing);
    });

    testWidgets('"Choose another category" hands back false', (tester) async {
      bool? result;
      await show(tester, 'Domestic Violence', onResult: (r) => result = r);

      await tester.tap(find.text('Choose another category'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('a blocked category offers no way to continue', (tester) async {
      await show(tester, 'Fire');

      expect(find.text('Report to the barangay'), findsNothing,
          reason: 'a fire report reaches no one who can put out a fire');
    });

    testWidgets('"Choose another category" closes it', (tester) async {
      await show(tester, 'Fire');

      await tester.tap(find.text('Choose another category'));
      await tester.pumpAndSettle();

      expect(find.text('This needs emergency responders'), findsNothing);
    });
  });
}
