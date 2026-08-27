import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('business UI uses the browser-native selectable text abstraction', () {
    final violations = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('browser_native_selectable_text_stub.dart')) {
        continue;
      }

      final source = entity.readAsStringSync();
      if (RegExp(
        r'(?<![A-Za-z0-9_])SelectableText(?:\.rich)?\s*\(',
      ).hasMatch(source)) {
        violations.add(entity.path);
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Use BrowserNativeSelectableText so Web selection and copy use the browser.',
    );
  });
}
