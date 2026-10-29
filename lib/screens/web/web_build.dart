import 'package:flutter/foundation.dart';

/// Stamped into the bundle by `deploy_web.sh` (`--dart-define=BUILD_ID=...`).
///
/// Shown in the sidebar so "which version am I looking at?" has an answer that
/// does not depend on trusting a browser cache. On 2026-10-14 a deployed fix was
/// verified present in the live JavaScript while the dashboard in the browser
/// still behaved like the build before it, and there was no way to tell from the
/// screen which one was running.
const String kBuildId = String.fromEnvironment('BUILD_ID', defaultValue: 'local');

/// Whether the copy of the dashboard running in a browser tab is out of date.
///
/// [running] is the build baked into this tab ([kBuildId]); [published] is what
/// the server says is current (`version.json`, written by `deploy_web.sh`).
///
/// A `local` build is never "out of date": it is a developer's own run, and there
/// is no published version it could be compared against. An unreadable or empty
/// answer from the server is also not an update — failing to check must never
/// put a "reload" banner in front of someone for no reason.
bool updateAvailable({required String running, String? published}) {
  if (running == 'local') return false;
  if (published == null || published.trim().isEmpty) return false;
  return published.trim() != running;
}

/// The most recent uncaught error, for on-screen display.
///
/// A release Flutter build swallows exceptions silently: a screen that throws
/// while building renders as a blank grey box and the only explanation is in a
/// browser console nobody has open. Surfacing the text on screen turns "it
/// doesn't open" into something that can be screenshotted and fixed.
final ValueNotifier<String?> webLastError = ValueNotifier<String?>(null);
