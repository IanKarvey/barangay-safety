import 'package:barangay_safety_app/screens/web/web_build.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('when a tab is told it is out of date', () {
    test('the server has a different build', () {
      expect(updateAvailable(running: '1015-2109', published: '1018-0930'), isTrue);
    });

    test('the server has the same build', () {
      expect(updateAvailable(running: '1015-2109', published: '1015-2109'), isFalse);
    });

    test('surrounding whitespace in the file does not count as a difference', () {
      expect(updateAvailable(running: '1015-2109', published: ' 1015-2109\n'), isFalse);
    });

    test('a developer run is never out of date', () {
      expect(updateAvailable(running: 'local', published: '1018-0930'), isFalse);
    });

    test('failing to read the version never shows a banner', () {
      // Offline, a 404, or an empty file must not tell someone to reload.
      expect(updateAvailable(running: '1015-2109', published: null), isFalse);
      expect(updateAvailable(running: '1015-2109', published: ''), isFalse);
      expect(updateAvailable(running: '1015-2109', published: '   '), isFalse);
    });
  });
}
