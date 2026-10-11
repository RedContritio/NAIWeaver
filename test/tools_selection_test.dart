import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/presets.dart';
import 'package:naiweaver/core/services/styles.dart';
import 'package:naiweaver/core/services/tag_service.dart';
import 'package:naiweaver/core/services/wildcard_service.dart';
import 'package:naiweaver/features/tools/providers/preset_notifier.dart';
import 'package:naiweaver/features/tools/providers/style_notifier.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('naiw_selection'));
  tearDown(() => dir.deleteSync(recursive: true));

  final tags = TagService(filePath: '/nonexistent/tags.json');
  final wildcards = WildcardService(wildcardDir: '/nonexistent/wildcards');

  test(
    'selectStyle(null) and deleting the selected style clear the selection',
    () async {
      final style = PromptStyle(name: 'A', prefix: 'x');
      final notifier = StyleNotifier(
        tagService: tags,
        wildcardService: wildcards,
        initialStyles: [style],
        stylesFilePath: '${dir.path}/styles.json',
        onStylesChanged: () {},
      );
      addTearDown(notifier.dispose);

      notifier.selectStyle(style);
      expect(notifier.state.selectedStyle, isNotNull);

      notifier.selectStyle(null);
      expect(notifier.state.selectedStyle, isNull);
      expect(notifier.state.originalName, isNull);

      notifier.selectStyle(style);
      await notifier.deleteStyle(style);
      expect(notifier.state.selectedStyle, isNull);
    },
  );

  test(
    'selectPreset(null) and deleting the selected preset clear the selection',
    () async {
      final preset = GenerationPreset(
        name: 'P',
        prompt: '',
        negativePrompt: '',
        width: 832,
        height: 1216,
        scale: 5,
        steps: 28,
        sampler: 'k_euler',
        smea: false,
        smeaDyn: false,
        decrisper: false,
      );
      final notifier = PresetNotifier(
        tagService: tags,
        wildcardService: wildcards,
        initialPresets: [preset],
        presetsFilePath: '${dir.path}/presets.json',
        onPresetsChanged: () {},
      );
      addTearDown(notifier.dispose);

      notifier.selectPreset(preset);
      notifier.selectPreset(null);
      expect(notifier.state.selectedPreset, isNull);
      expect(notifier.state.originalName, isNull);

      notifier.selectPreset(preset);
      await notifier.deletePreset(preset);
      expect(notifier.state.selectedPreset, isNull);
    },
  );
}
