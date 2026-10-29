import 'package:barangay_safety_app/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Password-recovery deep links.
///
/// The primary mechanism is `AuthChangeEvent.passwordRecovery` — the SDK
/// consumes the link itself and announces it. The URL matcher in main.dart is
/// only the fallback, but it is the part that silently did nothing: it tested
/// for a `reset-password` host or a `type=recovery` *fragment*, and
/// supabase_flutter v2 defaults to PKCE, where the redirect carries `?code=…`
/// in the query and there is no such fragment.
///
/// The failure is invisible — no error, no crash, the user simply lands on
/// Login — so the shapes are pinned here.
///
/// Mirrors `_handleDeepLink` in main.dart. Kept in step by hand; if the
/// matcher there changes, change it here.
bool isRecoveryLink(Uri uri) =>
    uri.host == 'reset-password' ||
    uri.path.contains('reset-password') ||
    uri.fragment.contains('type=recovery') ||
    uri.queryParameters['type'] == 'recovery';

/// Mirrors `_recoveryLinkError` in main.dart.
///
/// Confirmed live (2026-09-16): a recovery link tapped a second time — after
/// the code had already been exchanged, or consumed by an email client's
/// link-prefetch before the real tap — redirects with
/// `?error=access_denied&error_code=otp_expired&...` rather than a usable
/// code. `isRecoveryLink` alone still returns true for that URL (the host is
/// still `reset-password`), so without this check the app navigated to the
/// change-password form anyway, with no session behind it and no sign
/// anything was wrong until a submit failed.
bool recoveryLinkError(Uri uri) {
  final fromQuery = uri.queryParameters['error_description'] ??
      (uri.queryParameters.containsKey('error') ? uri.queryParameters['error'] : null);
  if (fromQuery != null) return true;
  return uri.fragment.contains('error=') || uri.fragment.contains('error_code=');
}

/// Mirrors `_recoveryLinkErrorMessage` in main.dart.
String recoveryLinkErrorMessage(Uri uri) {
  final fromQuery = uri.queryParameters['error_description'];
  if (fromQuery != null && fromQuery.isNotEmpty) {
    return fromQuery.replaceAll('+', ' ');
  }
  final frag = uri.fragment;
  final m = RegExp(r'error_description=([^&]+)').firstMatch(frag);
  if (m != null) {
    return Uri.decodeComponent(m.group(1)!).replaceAll('+', ' ');
  }
  return 'This reset link no longer works. Please request a new one.';
}

void main() {
  group('links that must be recognised', () {
    test('the registered reset-password host', () {
      expect(
        isRecoveryLink(Uri.parse('com.barangaysafety.app://reset-password')),
        isTrue,
      );
    });

    test('implicit flow — type=recovery in the fragment', () {
      expect(
        isRecoveryLink(Uri.parse(
            'com.barangaysafety.app://callback#access_token=abc&type=recovery')),
        isTrue,
      );
    });

    test('PKCE flow — type in the query', () {
      // The shape the old matcher could not see.
      expect(
        isRecoveryLink(Uri.parse(
            'com.barangaysafety.app://callback?code=xyz&type=recovery')),
        isTrue,
      );
    });

    test('a redirect that carries the path rather than the host', () {
      expect(
        isRecoveryLink(
            Uri.parse('com.barangaysafety.app://callback/reset-password')),
        isTrue,
      );
    });

    test('trailing slash does not break it', () {
      expect(
        isRecoveryLink(Uri.parse('com.barangaysafety.app://reset-password/')),
        isTrue,
      );
    });
  });

  group('links that must NOT be treated as recovery', () {
    test('a plain app launch', () {
      expect(isRecoveryLink(Uri.parse('com.barangaysafety.app://callback')),
          isFalse);
    });

    test('an email confirmation is not a password recovery', () {
      // Sending someone confirming their email to a change-password screen
      // would be worse than doing nothing.
      expect(
        isRecoveryLink(Uri.parse(
            'com.barangaysafety.app://callback?code=xyz&type=signup')),
        isFalse,
      );
    });

    test('an incident deep link', () {
      expect(
        isRecoveryLink(Uri.parse('com.barangaysafety.app://incident/abc-123')),
        isFalse,
      );
    });
  });

  group('the redirect target', () {
    test('matches a scheme registered in AndroidManifest.xml', () {
      // Both `reset-password` and `callback` hosts are declared there. If this
      // value drifts from the manifest, the email link opens a browser and the
      // app never sees it — the original bug.
      expect(AppConfig.passwordResetRedirect,
          'com.barangaysafety.app://reset-password');
    });

    test('the redirect is itself recognised by the matcher', () {
      // The loop has to close: what Supabase sends back must be what the app
      // can detect.
      expect(isRecoveryLink(Uri.parse(AppConfig.passwordResetRedirect)),
          isTrue);
    });
  });

  group('an expired or already-used link is told apart from a working one',
      () {
    test('the exact URL captured from a live device (2026-09-16)', () {
      // A second tap of a link whose code had already been exchanged — or
      // consumed earlier by an email client's link-prefetch. Recorded
      // verbatim from logcat rather than constructed, so this test cannot
      // drift from what Supabase actually sends.
      final uri = Uri.parse(
        'com.barangaysafety.app://reset-password'
        '?error=access_denied&error_code=otp_expired'
        '&error_description=Email+link+is+invalid+or+has+expired'
        '#error=access_denied&error_code=otp_expired'
        '&error_description=Email+link+is+invalid+or+has+expired&sb=',
      );

      // Still recovery-shaped — the host is still reset-password — which is
      // exactly why a second, separate check is needed.
      expect(isRecoveryLink(uri), isTrue);
      expect(recoveryLinkError(uri), isTrue);
      expect(recoveryLinkErrorMessage(uri),
          'Email link is invalid or has expired');
    });

    test('a working link with a real code is not flagged as an error', () {
      final uri = Uri.parse(
        'com.barangaysafety.app://reset-password'
        '?code=ec9b16dd-e06f-40cf-8ab9-ce6931cba5c6',
      );
      expect(isRecoveryLink(uri), isTrue);
      expect(recoveryLinkError(uri), isFalse);
    });

    test('an error with no description falls back to a plain message', () {
      final uri =
          Uri.parse('com.barangaysafety.app://reset-password?error=server_error');
      expect(recoveryLinkError(uri), isTrue);
      expect(recoveryLinkErrorMessage(uri), isNotEmpty);
    });

    test('an error carried only in the fragment is still caught', () {
      // The implicit-flow shape, as opposed to the PKCE query-string shape
      // captured above — both need to work, since which one Supabase sends
      // is not something the app controls.
      final uri = Uri.parse(
        'com.barangaysafety.app://reset-password'
        '#error=access_denied&error_code=otp_expired'
        '&error_description=Link+expired',
      );
      expect(recoveryLinkError(uri), isTrue);
      expect(recoveryLinkErrorMessage(uri), 'Link expired');
    });

    test('a plain successful link has no error to report', () {
      final uri = Uri.parse(AppConfig.passwordResetRedirect);
      expect(recoveryLinkError(uri), isFalse);
    });
  });
}
