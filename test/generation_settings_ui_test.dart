import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/features/characters/widgets/characters_page.dart';
import 'package:naiweaver/core/widgets/text_input_dialog.dart';
import 'package:naiweaver/features/gallery/providers/gallery_notifier.dart';
import 'package:naiweaver/features/generation/providers/generation_notifier.dart';
import 'package:naiweaver/features/generation/widgets/generation_seed_control.dart';
import 'package:naiweaver/features/generation/widgets/settings_panel.dart';

import 'support/generation_rig.dart';
import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('custom resolutions', () {
    test(
      'deleting by option removes the right entry, whatever list was shown',
      () async {
        final custom = [
          ResolutionOption('A', 640, 960, isCustom: true),
          ResolutionOption('B', 704, 1024, isCustom: true),
          ResolutionOption('C', 768, 1152, isCustom: true),
        ];
        final prefs = await testPreferences(
          initial: {
            'custom_resolutions': jsonEncode([
              for (final o in custom) o.toJson(),
            ]),
          },
        );

        // A free-only account sees a filtered list in which C is not at
        // position 2 + 8 of the saved ones; counting from the dropdown position
        // used to yield a negative or wrong index and deleted nothing.
        await AdvancedSettingsPanel.deleteCustomResolutionOption(
          prefs,
          custom[2],
        );
        var saved = jsonDecode(prefs.customResolutions) as List;
        expect(saved.map((e) => e['label']), ['A', 'B']);

        await AdvancedSettingsPanel.deleteCustomResolutionOption(
          prefs,
          custom[0],
        );
        saved = jsonDecode(prefs.customResolutions) as List;
        expect(saved.map((e) => e['label']), ['B']);

        // An entry that is not saved changes nothing.
        await AdvancedSettingsPanel.deleteCustomResolutionOption(
          prefs,
          custom[2],
        );
        saved = jsonDecode(prefs.customResolutions) as List;
        expect(saved.map((e) => e['label']), ['B']);
      },
    );
  });

  group('new album', () {
    test(
      'a name of only spaces creates nothing; a real one is trimmed',
      () async {
        final prefs = await testPreferences();
        final dir = Directory.systemTemp.createTempSync('naiweaver_album');
        addTearDown(() => dir.deleteSync(recursive: true));
        final gallery = GalleryNotifier(outputDir: dir.path, prefs: prefs);

        expect(
          AdvancedSettingsPanel.createAlbumFromInput('   ', gallery, prefs),
          isFalse,
        );
        expect(gallery.albums, isEmpty);

        expect(
          AdvancedSettingsPanel.createAlbumFromInput(
            '  Trip  ',
            gallery,
            prefs,
          ),
          isTrue,
        );
        expect(gallery.albums.map((a) => a.name), ['Trip']);
        expect(prefs.defaultSaveAlbumId, gallery.albums.single.id);
      },
    );

    testWidgets('the name dialog refuses spaces and stays open', (
      tester,
    ) async {
      String? result = 'unset';
      await pumpHarness(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showTextInputDialog(
                context,
                title: 'NEW',
                confirmLabel: 'Create',
              );
            },
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('CREATE'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(result, 'unset');
    });
  });

  group('seed box', () {
    test('only 0..4294967295 is valid while the seed is fixed', () {
      bool bad(String text, {bool random = false}) =>
          GenerationSeedControl.isInvalidSeed(text, randomize: random);
      expect(bad('0'), isFalse);
      expect(bad('4294967295'), isFalse);
      expect(bad('4294967296'), isTrue);
      expect(bad(''), isTrue);
      expect(bad('4294967296', random: true), isFalse);
    });

    testWidgets('shows the range error as the seed is typed', (tester) async {
      final controller = TextEditingController(text: '42');
      addTearDown(controller.dispose);
      await pumpHarness(
        tester,
        GenerationSeedControl(
          controller: controller,
          randomize: false,
          onRandomizeChanged: (_) {},
        ),
      );
      const message = 'The seed must be a whole number from 0 to 4294967295.';
      expect(find.text(message), findsNothing);

      await tester.enterText(find.byType(TextField), '4294967296');
      await tester.pump();
      expect(find.text(message), findsOneWidget);

      await tester.enterText(find.byType(TextField), '4294967295');
      await tester.pump();
      expect(find.text(message), findsNothing);
    });
  });

  group('insertCharacterTags', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('naiweaver_insert'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<GatewayRig> rigWith(String? target) async {
      final rig = await GatewayRig.create(
        dir,
        File('assets/logo.png').readAsBytesSync(),
        preferences: {if (target != null) 'char_insert_target': target},
      );
      addTearDown(rig.generation.dispose);
      return rig;
    }

    test(
      'follows the charInsertTarget preference: editor adds a card',
      () async {
        final g = (await rigWith('editor')).generation;
        final result = g.insertCharacterTags(
          '1girl, red hair',
          'bad hands',
          name: 'Ann',
        );
        expect(result, ApplyTagResult.addedCharacterCard);
        expect(g.state.characters.single.name, 'Ann');
        expect(g.state.characters.single.prompt, '1girl, red hair');
        expect(g.state.characters.single.uc, 'bad hands');
        expect(g.promptController.text, isEmpty);
      },
    );

    test(
      'main target appends to the prompts and writes the negatives',
      () async {
        final g = (await rigWith('main')).generation;
        g.promptController.text = 'masterpiece';
        g.negativePromptController.text = 'lowres';
        final result = g.insertCharacterTags(
          '1girl, red hair',
          'bad hands, lowres',
        );
        expect(result, ApplyTagResult.insertedIntoPrompt);
        expect(g.promptController.text, 'masterpiece, 1girl, red hair, ');
        // De-duplicated against what is already there.
        expect(g.negativePromptController.text, 'lowres, bad hands, ');
        expect(g.state.characters, isEmpty);
      },
    );

    test(
      'an explicit target beats the preference; replace swaps the prompt',
      () async {
        final g = (await rigWith('editor')).generation;
        g.promptController.text = 'old prompt';
        g.insertCharacterTags(
          'new prompt',
          'worst quality',
          target: 'main',
          replaceMainPrompt: true,
        );
        expect(g.promptController.text, 'new prompt');
        expect(g.negativePromptController.text, 'worst quality, ');
        expect(g.state.characters, isEmpty);
      },
    );

    test(
      'explicit controllers (a card being edited) are filled as given',
      () async {
        final g = (await rigWith('editor')).generation;
        final prompt = TextEditingController(text: 'a');
        final negative = TextEditingController();
        g.insertCharacterTags(
          'b',
          'c',
          promptTarget: prompt,
          negativeTarget: negative,
        );
        expect(prompt.text, 'a, b, ');
        expect(negative.text, 'c, ');
        expect(g.state.characters, isEmpty);
        expect(g.promptController.text, isEmpty);
      },
    );

    test(
      'the characters page apply honours charInsertTarget and negatives',
      () async {
        final editor = (await rigWith('editor')).generation;
        expect(
          applyCharacterToPrompt(
            editor,
            name: 'Ann',
            tags: '1girl, red hair, ',
            negativeTags: 'bad hands',
            dishevelled: true,
          ),
          ApplyTagResult.addedCharacterCard,
        );
        expect(editor.state.characters.single.name, 'Ann');
        expect(editor.state.characters.single.prompt, '1girl, red hair, nsfw');
        expect(editor.state.characters.single.uc, 'bad hands');
        expect(editor.promptController.text, isEmpty);

        final main = (await rigWith('main')).generation;
        applyCharacterToPrompt(
          main,
          name: 'Ann',
          tags: '1girl',
          negativeTags: 'bad hands',
        );
        expect(main.promptController.text, '1girl, ');
        expect(main.negativePromptController.text, 'bad hands, ');
        expect(main.state.characters, isEmpty);
      },
    );
  });
}
