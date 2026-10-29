// Web only (uses dart:html). Imported through alert_sound.dart, never by the
// mobile app.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:math' as math;
import 'dart:typed_data';

/// Browser alert: three short tones, repeated every three seconds until [stop].
///
/// The tone is generated in code as a tiny WAV file, so there is no audio asset
/// to ship or to fail to load.
///
/// Browsers refuse to play audio before the page has had a click or key press.
/// An official has always signed in to reach this screen, so the page has had
/// one; if it somehow has not, the pop-up still appears and only the tone is
/// skipped.
class AlertSound {
  AlertSound._();

  static Timer? _timer;
  static String? _src;

  static bool get isPlaying => _timer != null;

  static void start() {
    stop();
    _play();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _play());
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  static void _play() {
    try {
      final audio = html.AudioElement(_src ??= _buildTone())..volume = 0.6;
      // play() returns a Future that rejects when the browser blocks autoplay;
      // that must not become an unhandled error.
      unawaited(audio.play().catchError((Object _) {}));
    } catch (_) {
      // No audio available — the visual alert still shows.
    }
  }

  /// 880 Hz, 660 Hz, 880 Hz with short gaps, as a data: URI.
  static String _buildTone() {
    const rate = 22050;
    final samples = <int>[];
    void tone(double hz, double seconds) {
      final n = (rate * seconds).round();
      for (var i = 0; i < n; i++) {
        // Square-ish wave with a short fade at each end so it doesn't click.
        final edge = math.min(i, n - 1 - i) / (rate * 0.01);
        final gain = edge >= 1 ? 1.0 : edge;
        final v = math.sin(2 * math.pi * hz * i / rate) >= 0 ? 1.0 : -1.0;
        samples.add((v * gain * 9000).round());
      }
    }

    void gap(double seconds) =>
        samples.addAll(List.filled((rate * seconds).round(), 0));

    tone(880, 0.18);
    gap(0.06);
    tone(660, 0.18);
    gap(0.06);
    tone(880, 0.18);

    final data = ByteData(44 + samples.length * 2);
    void text(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        data.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    text(0, 'RIFF');
    data.setUint32(4, 36 + samples.length * 2, Endian.little);
    text(8, 'WAVEfmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little); // PCM
    data.setUint16(22, 1, Endian.little); // mono
    data.setUint32(24, rate, Endian.little);
    data.setUint32(28, rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    text(36, 'data');
    data.setUint32(40, samples.length * 2, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      data.setInt16(44 + i * 2, samples[i], Endian.little);
    }
    return 'data:audio/wav;base64,${base64Encode(data.buffer.asUint8List())}';
  }
}
