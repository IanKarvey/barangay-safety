import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../l10n/app_strings.dart';

/// Reads text aloud, for residents who find reading small print hard.
///
/// An interface so the tutorial can be tested without a phone's speech engine,
/// and so a phone with no Filipino voice installed is handled in one place.
abstract class SpeechService {
  /// True while something is being read.
  ValueListenable<bool> get speaking;

  /// Reads [text] in the voice for [language]. Returns false — and says nothing —
  /// when the phone has no voice for that language, so the screen can say so
  /// instead of reading Filipino aloud in an English accent.
  Future<bool> speak(String text, AppLanguage language);

  Future<void> stop();

  void dispose();
}

/// The phone's own text-to-speech engine, through `flutter_tts`.
///
/// Nothing is downloaded and no network is used: this is the speech engine
/// already installed on the phone (Google Text-to-speech on most Androids).
class FlutterTtsSpeech implements SpeechService {
  FlutterTtsSpeech() {
    try {
      _tts = FlutterTts();
      _tts!
        ..setStartHandler(() => _speaking.value = true)
        ..setCompletionHandler(() => _speaking.value = false)
        ..setCancelHandler(() => _speaking.value = false)
        ..setErrorHandler((_) => _speaking.value = false);
    } catch (e) {
      debugPrint('Speech: text-to-speech could not start — $e');
    }
  }

  FlutterTts? _tts;
  final ValueNotifier<bool> _speaking = ValueNotifier(false);

  @override
  ValueListenable<bool> get speaking => _speaking;

  /// Voices to try, best first. Filipino is `fil-PH` on current Androids and
  /// `tl-PH` on some older ones.
  static List<String> localesFor(AppLanguage language) =>
      language == AppLanguage.tagalog
          ? const ['fil-PH', 'tl-PH']
          : const ['en-PH', 'en-US', 'en-GB'];

  @override
  Future<bool> speak(String text, AppLanguage language) async {
    final tts = _tts;
    if (tts == null || text.trim().isEmpty) return false;
    try {
      await tts.stop();
      String? chosen;
      for (final locale in localesFor(language)) {
        final available = await tts.isLanguageAvailable(locale);
        if (available == true || available == 1) {
          chosen = locale;
          break;
        }
      }
      if (chosen == null) return false;

      await tts.setLanguage(chosen);
      // Slower than normal: this is for people who need the words to land.
      await tts.setSpeechRate(0.42);
      await tts.setVolume(1.0);
      await tts.setPitch(1.0);
      final result = await tts.speak(text);
      return result == 1 || result == true || result == null;
    } catch (e) {
      debugPrint('Speech: could not read aloud — $e');
      _speaking.value = false;
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {
      // Nothing to stop.
    }
    _speaking.value = false;
  }

  @override
  void dispose() {
    _tts?.stop();
    _speaking.dispose();
  }
}
