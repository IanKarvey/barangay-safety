// Picks the right alert-sound implementation for the platform: Web Audio in the
// browser, a vibration pattern on a phone. (A phone gets its sound from the
// push / system notification itself; an app cannot reliably play a custom tone
// over a locked screen.)
export 'alert_sound_stub.dart' if (dart.library.html) 'alert_sound_web.dart';
