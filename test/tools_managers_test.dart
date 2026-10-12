
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/presets.dart';
import 'package:naiweaver/core/services/styles.dart';
import 'package:naiweaver/core/services/tag_service.dart';
import 'package:naiweaver/core/services/wildcard_service.dart';
import 'package:naiweaver/core/widgets/manager_shell.dart';
import 'package:naiweaver/features/characters/providers/character_library_notifier.dart';
import 'package:naiweaver/features/generation/providers/generation_notifier.dart';
import 'package:naiweaver/features/tools/widgets/preset_manager.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'test_harness.dart';

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
}
