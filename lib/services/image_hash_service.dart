import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// §4.3 — perceptual hashing, for spotting the same photograph twice.
///
/// ## What problem this actually solves
///
/// Proximity matching (§4.2) catches five people standing around one fire.
/// It cannot catch the other pattern: one photograph forwarded around a group
/// chat and re-uploaded by five people, hours later, from wherever they
/// happened to be standing. There the GPS is different, the time is different,
/// and the wording is different — the only thing in common is the image.
///
/// ## dHash, not a checksum
///
/// A cryptographic hash changes completely when a single byte changes, so
/// re-saving a photo at a different quality defeats it entirely. A difference
/// hash compares neighbouring pixel brightnesses in a 9×8 thumbnail, so
/// resizing, recompression, minor crops and brightness shifts all still land
/// within a few bits of the original.
///
/// That is also why comparison is [hammingDistance] and never `==`.
class ImageHashService {
  /// Below this many differing bits, two images are treated as the same photo.
  ///
  /// 10/64 is the usual working threshold for dHash. Tightening it to 0 would
  /// only catch byte-identical files, which is the case that needed no
  /// perceptual hash to begin with; loosening it much past 12 starts matching
  /// any two photographs of the same dim street at night.
  static const int duplicateThreshold = 10;

  /// A 64-bit difference hash as 16 lowercase hex characters, or null if the
  /// image could not be decoded.
  ///
  /// Runs the decode on a background isolate: a full-size phone photo takes
  /// long enough to decode that doing it on the main thread drops frames on
  /// the report form while someone is filing an emergency.
  static Future<String?> hashFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      return compute(_hashBytes, bytes);
    } catch (e) {
      // A hash is an enhancement to duplicate detection, never a precondition
      // for filing a report. Failing quietly is correct here.
      debugPrint('ImageHashService: could not hash image — $e');
      return null;
    }
  }

  /// Number of differing bits between two hex hashes.
  ///
  /// Returns 64 (maximum distance, i.e. "nothing alike") when either hash is
  /// missing or malformed, so a bad value can never masquerade as a match.
  static int hammingDistance(String? a, String? b) {
    if (a == null || b == null) return 64;
    if (a.length != 16 || b.length != 16) return 64;

    try {
      // Parsed as two 32-bit halves, never as one 64-bit value.
      //
      // Dart's int is 64-bit SIGNED. A hash with bit 63 set is a negative
      // number, and `toRadixString(16)` renders that as "-1" rather than
      // "ffffffffffffffff" — which `padLeft` then turned into the garbage
      // string "00000000000000-1". Two identical images produced two identical
      // garbage strings, both failed to parse, and the function returned 64
      // ("nothing alike") for a perfect match. Roughly half of all images set
      // that bit, so duplicate-photo detection silently never fired for them.
      final xHi = int.parse(a.substring(0, 8), radix: 16);
      final xLo = int.parse(a.substring(8), radix: 16);
      final yHi = int.parse(b.substring(0, 8), radix: 16);
      final yLo = int.parse(b.substring(8), radix: 16);

      return _popCount(xHi ^ yHi) + _popCount(xLo ^ yLo);
    } catch (_) {
      return 64;
    }
  }

  /// Number of set bits in a non-negative 32-bit value.
  static int _popCount(int v) {
    var n = v;
    var count = 0;
    while (n != 0) {
      count += n & 1;
      n >>>= 1;
    }
    return count;
  }

  /// Whether two hashes are close enough to be the same photograph.
  static bool looksLikeSameImage(String? a, String? b) =>
      hammingDistance(a, b) <= duplicateThreshold;
}

/// Top-level so it can run on an isolate — `compute` cannot take a closure.
String? _hashBytes(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  // 9×8 greyscale: 8 rows of 9 pixels give 8 comparisons per row = 64 bits.
  final small = img.copyResize(
    img.grayscale(decoded),
    width: 9,
    height: 8,
    interpolation: img.Interpolation.average,
  );

  // Two 32-bit halves rather than one 64-bit int: Dart's int is signed, so
  // setting bit 63 would make the value negative and `toRadixString(16)` would
  // emit "-..." instead of hex. See hammingDistance for what that broke.
  var hi = 0;
  var lo = 0;
  var bit = 0;
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      // Each bit answers "is this pixel brighter than the one to its right?".
      // Relative comparisons are what make the hash survive a brightness or
      // contrast shift — absolute values would not.
      final left = small.getPixel(x, y).luminance;
      final right = small.getPixel(x + 1, y).luminance;
      if (left > right) {
        if (bit < 32) {
          lo |= 1 << bit;
        } else {
          hi |= 1 << (bit - 32);
        }
      }
      bit++;
    }
  }

  return hi.toRadixString(16).padLeft(8, '0') +
      lo.toRadixString(16).padLeft(8, '0');
}
