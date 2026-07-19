import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/utils/image_utils.dart';

/// Issue #24: a "PNG" with an intact 8-byte signature but a garbage body is
/// what a failed Vibe+Ref generation used to leave in the gallery. package:image
/// throws (RangeError etc.) on such bytes instead of returning null, so every
/// helper that decodes untrusted bytes must tolerate them.
void main() {
  Uint8List corruptPng() {
    final rng = Random(24); // deterministic garbage
    return Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      ...List.generate(4096, (_) => rng.nextInt(256)),
    ]);
  }

  test('injectMetadata falls back to the original bytes on corrupt PNGs', () {
    final bytes = corruptPng();
    final out = injectMetadata({
      'bytes': bytes,
      'metadata': {'prompt': '1girl'},
    });
    expect(out, bytes);
  });

  test('stripMetadata falls back to the original bytes on corrupt PNGs', () {
    final bytes = corruptPng();
    expect(stripMetadata(bytes), bytes);
  });

  test('extractMetadata does not throw on corrupt PNGs', () {
    expect(() => extractMetadata(corruptPng()), returnsNormally);
  });

  test('extractMetadata does not throw on non-PNG garbage', () {
    // No PNG signature at all — exercises the package:image decode branch
    // (whose format probing can throw on short/garbage buffers).
    final rng = Random(42);
    final garbage =
        Uint8List.fromList(List.generate(64, (_) => rng.nextInt(256)));
    expect(() => extractMetadata(garbage), returnsNormally);
  });
}
