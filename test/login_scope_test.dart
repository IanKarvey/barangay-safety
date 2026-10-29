import 'package:barangay_safety_app/config/app_config.dart';
import 'package:barangay_safety_app/providers/language_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the system covers Barangays 1, 2, 3, 7 and 10 — in numeric order', () {
    // Pinned on purpose. This is the scope the login screen tells people about,
    // so widening or narrowing it should be a visible edit to this test and not
    // a side effect of touching the barangay config.
    expect(AppConfig.coveredBarangays, [1, 2, 3, 7, 10]);
  });

  test('the login notice reads naturally in English', () {
    SharedPreferences.setMockInitialValues({});
    final t = LanguageProvider().strings;

    expect(t.loginScopeTitle('1, 2, 3, 7 ${t.listAnd} 10'),
        'Serving Barangays 1, 2, 3, 7 and 10');
    expect(t.loginScopeBody, contains('Residents of other barangays'));
  });
}
