import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'supabase_service.dart';

/// What the classifier thinks, and why.
class SeveritySuggestion {
  /// 1–4, matching the app's existing severity levels.
  final int level;

  /// One short sentence, shown to the reporter so they can judge the judgement.
  final String reason;

  const SeveritySuggestion({required this.level, required this.reason});
}

/// §4.1 — suggests a severity level from the incident photo.
///
/// ## It suggests; the person decides
///
/// Nothing here changes the form. The reporter sees the suggestion and either
/// taps it or ignores it. That is the whole design: a barangay may dispatch on
/// this severity, and one photo is thin evidence for a decision with those
/// consequences. An AI that silently set the level would be making a dispatch
/// call with no human in the loop.
///
/// ## Why the key is not in this app
///
/// Goes through the `suggest-severity` Edge Function, which holds the Anthropic
/// key as a server secret. Calling the API directly from here would ship a
/// money-spending key inside the APK.
///
/// ## It never blocks a report
///
/// Every failure path returns null and the form behaves exactly as it did
/// before. A classifier that can delay or block an emergency report is a worse
/// problem than the one it solves.
class SeverityAiService {
  final _supabase = SupabaseService.instance;

  /// Analyses [photo]. Returns null when unavailable, unconfigured, or when the
  /// model declines to guess — all of which are ordinary outcomes, not errors.
  Future<SeveritySuggestion?> suggest({
    required File photo,
    String? description,
    String? category,
  }) async {
    try {
      final bytes = await photo.readAsBytes();

      // Guard the request size before spending a round trip. Anthropic caps
      // image payloads, and a multi-megabyte phone photo can exceed it.
      if (bytes.lengthInBytes > 4 * 1024 * 1024) {
        debugPrint('SeverityAi: photo too large to classify '
            '(${bytes.lengthInBytes} bytes)');
        return null;
      }

      final res = await _supabase.client.functions.invoke(
        'suggest-severity',
        body: {
          'imageBase64': base64Encode(bytes),
          'mediaType': _mediaTypeFor(photo.path),
          'description': description,
          'category': category,
        },
      );

      final data = res.data;
      if (data is! Map) return null;

      final level = data['suggested'];
      if (level is! int) {
        // Includes the model's own "cannot judge" answer. Logged rather than
        // silent so a misconfigured key is distinguishable from a dark photo.
        debugPrint('SeverityAi: no suggestion — ${data['reason']}');
        return null;
      }

      return SeveritySuggestion(
        level: level,
        reason: (data['reason'] as String?)?.trim() ?? '',
      );
    } catch (e) {
      debugPrint('SeverityAi: suggestion failed: $e');
      return null;
    }
  }

  String _mediaTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
