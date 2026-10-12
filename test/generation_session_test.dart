import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/styles.dart';
import 'package:naiweaver/features/generation/services/metadata_import_service.dart';
import 'package:naiweaver/features/generation/services/session_snapshot_service.dart';

import 'support/generation_rig.dart';
import 'test_harness.dart';

SessionSnapshot _saved({
  int version = SessionSnapshot.currentVersion,
  List<String> styles = const ['Quality (NAI Default)'],
}) => SessionSnapshot(
  version: version,
  prompt: 'saved prompt',
  negativePrompt: 'saved negative',
  seed: '123',
  width: 640,
  height: 960,
  scale: 7,
  steps: 20,
  sampler: 'k_euler',
  smea: false,
  smeaDyn: false,
  decrisper: false,
  randomizeSeed: true,
  batchCount: 3,
  autoPositioning: false,
  activeStyleNames: styles,
  isStyleEnabled: true,
  furryMode: false,
  useCurated: false,
  characters: const [],
  interactions: const [],
  directorReferences: const [],
  vibeTransfers: const [],
);

MetadataImportResult _imported() => MetadataImportResult(
  prompt: 'database prompt',
  negativePrompt: 'database negative',
  seed: '999',
  width: 832,
  height: 1216,
  scale: 5,
  steps: 28,
  sampler: 'k_euler_ancestral',
  smea: false,
  smeaDyn: false,
  decrisper: false,
  activeStyleNames: const [],
  isStyleEnabled: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('naiweaver_session'));
  tearDown(() => dir.deleteSync(recursive: true));

  SessionSnapshotService sessionFile() => SessionSnapshotService(
    sessionFilePath: '${dir.path}/session_snapshot.json',
  );

  Future<RigGeneration> start({Future<void>? gate}) async {
    final generation = RigGeneration(
      preferences: await testPreferences(),
      dir: dir.path,
      initializationGate: gate,
    );
    addTearDown(generation.dispose);
    return generation;
  }

  test('startup restores the saved session', () async {
    await sessionFile().save(_saved());

    final generation = await start();
    await generation.initialized;

    expect(generation.promptController.text, 'saved prompt');
    expect(generation.negativePromptController.text, 'saved negative');
    expect(generation.seedController.text, '123');
    expect(generation.state.width, 640);
    expect(generation.state.batchCount, 3);
  });

  group('an import goes on top of the restored session', () {
    for (final slowStartup in [false, true]) {
      for (final categories in <Set<ImportCategory>>[
        ImportCategory.values.toSet(),
        {ImportCategory.prompt},
        {ImportCategory.seed, ImportCategory.settings},
      ]) {
        final label = categories.length == ImportCategory.values.length
            ? 'everything'
            : categories.map((c) => c.name).join('+');
        test('$label ${slowStartup ? 'before' : 'after'} startup', () async {
          await sessionFile().save(_saved());
          final gate = Completer<void>();
          final generation = await start(
            gate: slowStartup ? gate.future : null,
          );
          if (!slowStartup) await generation.initialized;

          generation.applyImportedMetadata(_imported(), categories);
          if (slowStartup) {
            gate.complete();
            await generation.initialized;
          }
          await generation.flushSessionSave();

          final persisted = (await sessionFile().restore())!;
          // What was imported wins, in the form and in the saved session ...
          final prompt = categories.contains(ImportCategory.prompt)
              ? 'database prompt'
              : 'saved prompt';
          final seed = categories.contains(ImportCategory.seed) ? '999' : '123';
          final width = categories.contains(ImportCategory.settings)
              ? 832
              : 640;
          expect(generation.promptController.text, prompt);
          expect(persisted.prompt, prompt);
          expect(generation.seedController.text, seed);
          expect(persisted.seed, seed);
          expect(generation.state.width, width);
          expect(persisted.width, width.toDouble());
          // ... and what was not imported is the saved session's.
          final negative = categories.contains(ImportCategory.negativePrompt)
              ? 'database negative'
              : 'saved negative';
          expect(generation.negativePromptController.text, negative);
          expect(persisted.negativePrompt, negative);
          expect(generation.state.batchCount, 3);
        });
      }
    }
  });

  group('the styles a session starts with', () {
    Future<void> styles(List<PromptStyle> list) =>
        StyleStorage.saveStyles('${dir.path}/styles.json', list);

    test('are the ones marked as default', () async {
      await styles([
        PromptStyle(name: 'Quality (NAI Default)'),
        PromptStyle(name: 'Mine', isDefault: true),
        PromptStyle(name: 'Other'),
        PromptStyle(name: 'Also mine', isDefault: true),
      ]);

      final generation = await start();
      await generation.initialized;

      expect(generation.state.activeStyleNames, ['Mine', 'Also mine']);
    });

    test('fall back to the quality style without a default', () async {
      await styles([
        PromptStyle(name: 'Other'),
        PromptStyle(name: 'Quality (NAI Default)'),
      ]);

      final generation = await start();
      await generation.initialized;

      expect(generation.state.activeStyleNames, ['Quality (NAI Default)']);
    });

    test(
      'keep a choice of the old default once the snapshot is current',
      () async {
        await styles([
          PromptStyle(name: 'Mine', isDefault: true),
          PromptStyle(name: 'Light - NAI'),
        ]);
        // A snapshot from before versions: the old default is replaced once.
        await sessionFile().save(_saved(version: 0, styles: ['Light - NAI']));
        var generation = await start();
        await generation.initialized;
        expect(generation.state.activeStyleNames, ['Mine']);

        // Chosen by the user afterwards, it stays.
        generation.updateSettings(activeStyleNames: ['Light - NAI']);
        await generation.flushSessionSave();
        generation = await start();
        await generation.initialized;
        expect(generation.state.activeStyleNames, ['Light - NAI']);
      },
    );
  });
}
