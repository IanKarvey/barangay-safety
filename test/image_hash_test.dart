import 'package:flutter_test/flutter_test.dart';
import 'package:barangay_safety_app/services/image_hash_service.dart';

void main() {
  test('all-bits-set hash round-trips and self-matches', () {
    var hi = 0, lo = 0;
    for (var bit = 0; bit < 64; bit++) {
      if (bit < 32) { lo |= 1 << bit; } else { hi |= 1 << (bit - 32); }
    }
    final hex = hi.toRadixString(16).padLeft(8, '0') +
                lo.toRadixString(16).padLeft(8, '0');
    expect(hex, 'ffffffffffffffff');
    expect(hex.length, 16);
    expect(ImageHashService.hammingDistance(hex, hex), 0);
  });

  test('single differing bit measures as distance 1', () {
    expect(ImageHashService.hammingDistance(
        'ffffffffffffffff', 'fffffffffffffffe'), 1);
    expect(ImageHashService.hammingDistance(
        'ffffffffffffffff', '7fffffffffffffff'), 1); // top bit — the old break
  });

  test('opposite hashes are maximally distant', () {
    expect(ImageHashService.hammingDistance(
        'ffffffffffffffff', '0000000000000000'), 64);
  });

  test('threshold behaves', () {
    expect(ImageHashService.looksLikeSameImage(
        'ffffffffffffffff', 'fffffffffffffff0'), isTrue);  // 4 bits apart
    expect(ImageHashService.looksLikeSameImage(
        'ffffffffffffffff', '0000000000000000'), isFalse);
  });

  test('malformed input is treated as nothing-alike, never as a match', () {
    expect(ImageHashService.hammingDistance(null, 'ffffffffffffffff'), 64);
    expect(ImageHashService.hammingDistance('zzzz', 'ffffffffffffffff'), 64);
    expect(ImageHashService.hammingDistance('abc', 'def'), 64);
  });
}
