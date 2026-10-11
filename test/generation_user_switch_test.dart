import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/services/tag_service.dart';
import 'package:naiweaver/core/services/wildcard_service.dart';
import 'package:naiweaver/features/generation/providers/generation_notifier.dart';

import 'test_harness.dart';

class _Tags extends TagService {
  _Tags() : super(filePath: 'isolated-tags');

  @override
  Future<void> loadTags() async {}
}

class _Generation extends GenerationNotifier {
  _Generation(PreferencesService preferences)
    : super(
        preferences: preferences,
        tagService: _Tags(),
        wildcardService: WildcardService(wildcardDir: 'isolated-wildcards'),
        outputDir: 'isolated-output',
        presetsFilePath: 'isolated-presets',
        stylesFilePath: 'isolated-styles',
      );

  @override
  Future<void> fetchAnlas() async {}
}

void main() {
  test('another account never sees the previous account workspace', () async {
    final generation = _Generation(await testPreferences());
    addTearDown(generation.dispose);
    generation.updateBackendUserId(1);
    generation.setGeneratedImage(Uint8List.fromList([1, 2, 3]));

    // Re-reporting the same user keeps the work in place.
    generation.updateBackendUserId(1);
    expect(generation.state.generatedImage, isNotNull);

    generation.updateBackendUserId(2);
    expect(generation.state.generatedImage, isNull);
    expect(generation.state.generatedImages, isEmpty);

    generation.setGeneratedImage(Uint8List.fromList([4]));
    generation.updateBackendUserId(null);
    expect(generation.state.generatedImage, isNull);
  });
}
