import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/presets.dart';
import 'package:naiweaver/core/services/styles.dart';
import 'package:naiweaver/core/services/tag_service.dart';
import 'package:naiweaver/core/services/wildcard_service.dart';
import 'package:naiweaver/core/widgets/manager_shell.dart';
import 'package:naiweaver/features/characters/providers/character_library_notifier.dart';
import 'package:naiweaver/features/generation/providers/generation_notifier.dart';
import 'package:naiweaver/features/tools/providers/tag_library_notifier.dart';
import 'package:naiweaver/features/tools/providers/wildcard_notifier.dart';
import 'package:naiweaver/features/tools/widgets/preset_manager.dart';
import 'package:naiweaver/features/tools/widgets/style_editor.dart';
import 'package:naiweaver/features/tools/widgets/tag_library_manager.dart';
import 'package:naiweaver/features/tools/widgets/wildcard_manager.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'test_harness.dart';

const _longName =
    'AN EXTREMELY LONG NAME THAT KEEPS GOING WELL PAST ANY PANE WIDTH';
const _widths = [360.0, 600.0, 680.0];

class _FakeGeneration extends ChangeNotifier implements GenerationNotifier {
  _FakeGeneration(this.state);

  @override
  GenerationState state;

  @override
  final TagService tagService = TagService(filePath: '/nonexistent/tags.json');

  @override
  final WildcardService wildcardService = WildcardService(
    wildcardDir: '/nonexistent/wildcards',
  );

  @override
  String get presetsFilePath => '/nonexistent/presets.json';

  @override
  String get stylesFilePath => '/nonexistent/styles.json';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCharacters extends ChangeNotifier
    implements CharacterLibraryNotifier {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GenerationPreset _preset(String name) => GenerationPreset(
  name: name,
  prompt: '',
  negativePrompt: '',
  width: 832,
  height: 1216,
  scale: 6,
  steps: 28,
  sampler: 'k_euler_ancestral',
  smea: false,
  smeaDyn: false,
  decrisper: false,
);

List<SingleChildWidget> _generationProviders({
  List<GenerationPreset> presets = const [],
  List<PromptStyle> styles = const [],
}) => [
  ChangeNotifierProvider<GenerationNotifier>.value(
    value: _FakeGeneration(GenerationState(presets: presets, styles: styles)),
  ),
  ChangeNotifierProvider<CharacterLibraryNotifier>.value(
    value: _FakeCharacters(),
  ),
];

Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

/// Lets real file I/O started by the widget finish, then rebuilds.
Future<void> _settleIo(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  group('PresetManager unsaved edits', () {
    testWidgets(
      'phone: back from edited preset asks; cancel keeps, discard reverts',
      (tester) async {
        await pumpHarness(
          tester,
          const PresetManager(),
          providers: _generationProviders(
            presets: [_preset('ALPHA'), _preset('BETA')],
          ),
          size: const Size(360, 800),
        );

        // The phone list keeps the manager header (save / title live there).
        expect(find.text('PRESET MANAGER'), findsOneWidget);

        await tester.tap(find.text('ALPHA'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'ALPHA'),
          'ALPHA EDITED',
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey<String>('preset-mobile-save')),
          findsOneWidget,
        );

        await _systemBack(tester);
        expect(find.text('UNSAVED CHANGES'), findsOneWidget);
        await tester.tap(find.text('CANCEL'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextField, 'ALPHA EDITED'), findsOneWidget);

        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('DISCARD'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(ManagerMasterDetailShell.masterPaneKey),
          findsOneWidget,
        );
        expect(find.text('ALPHA EDITED'), findsNothing);

        // Nothing is pending any more, so opening another preset is direct.
        await tester.tap(find.text('BETA'));
        await tester.pumpAndSettle();
        expect(find.text('UNSAVED CHANGES'), findsNothing);
        expect(find.widgetWithText(TextField, 'BETA'), findsOneWidget);
      },
    );

    testWidgets(
      'opening another preset with pending edits asks instead of dropping them',
      (tester) async {
        await pumpHarness(
          tester,
          const PresetManager(),
          providers: _generationProviders(
            presets: [_preset('ALPHA'), _preset('BETA')],
          ),
          size: const Size(680, 800),
        );

        await tester.tap(find.text('ALPHA'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'ALPHA'),
          'ALPHA EDITED',
        );
        await tester.pump();

        await tester.tap(find.text('BETA'));
        await tester.pumpAndSettle();
        expect(find.text('UNSAVED CHANGES'), findsOneWidget);
        await tester.tap(find.text('CANCEL'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextField, 'ALPHA EDITED'), findsOneWidget);
        expect(find.text('SAVE CHANGES'), findsOneWidget);

        await tester.tap(find.text('BETA'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('DISCARD'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextField, 'BETA'), findsOneWidget);
        expect(find.text('SAVE CHANGES'), findsNothing);
      },
    );
  });

  group('managers fit 360/600/680 px with long names', () {
    for (final width in _widths) {
      testWidgets('presets at ${width.toInt()}', (tester) async {
        await pumpHarness(
          tester,
          const PresetManager(),
          providers: _generationProviders(presets: [_preset(_longName)]),
          size: Size(width, 800),
        );
        await tester.tap(find.text(_longName));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, _longName),
          '$_longName!',
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('styles at ${width.toInt()}', (tester) async {
        await pumpHarness(
          tester,
          const StyleEditor(),
          providers: _generationProviders(
            styles: [PromptStyle(name: _longName)],
          ),
          size: Size(width, 800),
        );
        await tester.tap(find.text(_longName));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, _longName),
          '$_longName!',
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('wildcards at ${width.toInt()}', (tester) async {
        final dir = Directory.systemTemp.createTempSync('naiweaver_wildcards');
        addTearDown(() => dir.deleteSync(recursive: true));
        File(
          '${dir.path}/${_longName.replaceAll(' ', '.')}.txt',
        ).writeAsStringSync('red\nblue\n');

        final service = WildcardService(wildcardDir: dir.path);
        late WildcardNotifier notifier;
        await tester.runAsync(() async {
          await service.refresh();
          notifier = WildcardNotifier(
            wildcardDir: dir.path,
            tagService: TagService(filePath: '${dir.path}/tags.json'),
            wildcardService: service,
          );
          await notifier.refreshFiles();
        });

        await pumpHarness(
          tester,
          const WildcardManager(),
          providers: [
            ChangeNotifierProvider<WildcardNotifier>.value(value: notifier),
          ],
          size: Size(width, 800),
        );
        await tester.tap(find.text(_longName.replaceAll(' ', '.')));
        await _settleIo(tester);

        expect(
          find.byKey(ManagerMasterDetailShell.detailPaneKey),
          findsOneWidget,
        );
        // The help stays reachable from the editor on phones too.
        expect(find.byTooltip('WILDCARD HELP'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('tag library at ${width.toInt()}', (tester) async {
        final dir = Directory.systemTemp.createTempSync('naiweaver_tags');
        addTearDown(() => dir.deleteSync(recursive: true));
        final tagFile = File('${dir.path}/tags.json')
          ..writeAsStringSync(
            jsonEncode([
              {
                'tag': _longName.toLowerCase().replaceAll(' ', '_'),
                'count': 123456,
                'type_name': 'character',
              },
              {'tag': 'short', 'count': 1, 'type_name': 'general'},
            ]),
          );
        final preferences = await testPreferences(
          initial: {'examples_v2_migrated': true},
        );
        final tagService = TagService(filePath: tagFile.path);
        late TagLibraryNotifier notifier;
        await tester.runAsync(() async {
          await tagService.loadTags();
          notifier = TagLibraryNotifier(
            tagService: tagService,
            examplesDir: '${dir.path}/examples',
          );
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });

        setSurfaceSize(tester, Size(width, 800));
        await tester.pumpWidget(
          harnessApp(
            preferences: preferences,
            providers: [
              ChangeNotifierProvider<TagLibraryNotifier>.value(value: notifier),
            ],
            home: const Scaffold(body: TagLibraryManager()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('short'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
