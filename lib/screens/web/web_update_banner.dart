// Web only (uses dart:html). Imported by main_web.dart, never by the mobile app.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';

import 'web_build.dart';

/// Tells the person when the dashboard in their tab is out of date.
///
/// ## Why this exists
///
/// An admin dashboard is the kind of page that gets left open all day on a
/// desk. Whatever build was current when the tab was opened is what it keeps
/// running, however many times the site is redeployed afterwards. On 2026-10-14
/// and again on the 15th, that meant buttons that did nothing — an old build
/// with no routes, looking exactly like a bug in the new one — and the only
/// symptom was "it doesn't work".
///
/// So the page now checks, and says so. It asks the server for `version.json`
/// (written by `deploy_web.sh` with the build number) shortly after loading and
/// every couple of minutes, and when that number is not its own it shows a bar
/// with a Reload button.
///
/// ## What it deliberately does not do
///
/// It does not reload by itself. A secretary half way through typing an update
/// to a resident would lose it. The bar is a request, not an action.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  Timer? _timer;
  bool _stale = false;

  @override
  void initState() {
    super.initState();
    // Soon after load, then on a slow cadence. The first check is not
    // immediate so it never competes with the dashboard's own first queries.
    Timer(const Duration(seconds: 8), _check);
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_stale || kBuildId == 'local') return;
    try {
      // The query string defeats any cache between here and the server.
      final body = await html.HttpRequest.getString(
        'version.json?t=${DateTime.now().millisecondsSinceEpoch}',
      );
      final published = (jsonDecode(body) as Map)['build'] as String?;
      if (!mounted) return;
      if (updateAvailable(running: kBuildId, published: published)) {
        setState(() => _stale = true);
      }
    } catch (_) {
      // Offline, or the file is missing: say nothing. See [updateAvailable].
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_stale) return const SizedBox.shrink();
    return Material(
      color: const Color(0xFF1E3A8A),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.system_update_alt_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 10),
              const Flexible(
                child: Text(
                  'A newer version of the dashboard is available. '
                  'Reload to get the latest fixes.',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              const SizedBox(width: 14),
              FilledButton(
                onPressed: () => html.window.location.reload(),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1E3A8A),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Reload',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
