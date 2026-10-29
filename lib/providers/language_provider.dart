import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_strings.dart';

/// Holds the chosen interface language and remembers it across launches.
///
/// Persisted because the people this matters most to — barangay officials who
/// read English poorly — would otherwise have to switch it every single time
/// they open the app.
class LanguageProvider with ChangeNotifier {
  static const _prefsKey = 'app_language';

  AppLanguage _language = AppLanguage.english;
  AppLanguage get language => _language;

  AppStrings get strings => AppStrings.of(_language);
  bool get isTagalog => _language == AppLanguage.tagalog;

  /// Loads the saved choice. Called before the first frame so the app never
  /// flashes English at someone who chose Tagalog.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _language = AppLanguage.fromCode(prefs.getString(_prefsKey));
      _safeNotify();
    } catch (e) {
      debugPrint('LanguageProvider: could not load saved language: $e');
    }
  }

  Future<void> setLanguage(AppLanguage language) async {
    if (_language == language) return;
    _language = language;
    _safeNotify();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, language.code);
    } catch (e) {
      // Not fatal — the switch still applies for this session.
      debugPrint('LanguageProvider: could not persist language: $e');
    }
  }

  Future<void> toggle() => setLanguage(
        _language == AppLanguage.english
            ? AppLanguage.tagalog
            : AppLanguage.english,
      );

  // ── Disposal safety ───────────────────────────────────────────────────
  // Providers are torn down on logout and on navigation while their async
  // work is still in flight. `notifyListeners()` after `dispose()` throws
  // `A ChangeNotifier was used after being disposed` — an unhandled error on
  // a background future, which the user sees as a crash they cannot retry.
  bool _disposed = false;

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
