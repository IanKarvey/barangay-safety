import 'dart:async';

import 'package:flutter/services.dart';

/// Phone / desktop-app alert: a repeating strong vibration (and the platform's
/// alert sound where one exists) until [stop] is called.
class AlertSound {
  AlertSound._();

  static Timer? _timer;

  static bool get isPlaying => _timer != null;

  static void start() {
    stop();
    _pulse();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _pulse());
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  static void _pulse() {
    try {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.vibrate();
    } catch (_) {
      // Feedback is a courtesy; the pop-up is the alert.
    }
  }
}
