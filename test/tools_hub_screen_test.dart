import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/services/tag_service.dart';
import 'package:naiweaver/core/services/wildcard_service.dart';
import 'package:naiweaver/features/tools/providers/wildcard_notifier.dart';
import 'package:naiweaver/features/tools/tools_hub_screen.dart';
import 'package:naiweaver/features/tools/widgets/feedback_panel.dart';
import 'package:provider/provider.dart';

import 'test_harness.dart';

void main() {
  Future<PreferencesService> pumpLauncher(
    WidgetTester tester, {
    String? initialToolId,
    Map<String, Object> initialPrefs = const {},
  }) async {
    setSurfaceSize(tester, const Size(1200, 800));
    final preferences = await testPreferences(initial: initialPrefs);
    const dir = '/nonexistent/naiweaver-test-wildcards';
    await tester.pumpWidget(
      harnessApp(
        preferences: preferences,
        providers: [
          ChangeNotifierProvider(
            create: (_) => WildcardNotifier(
              wildcardDir: dir,
              tagService: TagService(filePath: '$dir/tags.json'),
              wildcardService: WildcardService(wildcardDir: dir),
            ),
          ),
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ToolsHubScreen(initialToolId: initialToolId),
                ),
              ),
              child: const Text('open tools'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open tools'));
    await tester.pumpAndSettle();
    return preferences;
  }

  testWidgets('Escape inside a text field does not close the hub', (
    tester,
  ) async {
    await pumpLauncher(tester, initialToolId: 'feedback');
    expect(find.byType(ToolsHubScreen), findsOneWidget);

    await tester.tap(find.byKey(FeedbackPanel.descriptionKey));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(ToolsHubScreen), findsOneWidget);
  });

  testWidgets('Escape outside text fields still closes the hub', (
    tester,
  ) async {
    await pumpLauncher(tester, initialToolId: 'feedback');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(ToolsHubScreen), findsNothing);
  });

  testWidgets('an unavailable remembered tool is shown as a fallback only', (
    tester,
  ) async {
    final preferences = await pumpLauncher(
      tester,
      initialPrefs: {'tools_last_tool_id': 'retired_tool'},
    );
    await tester.pumpAndSettle();

    expect(find.byType(ToolsHubScreen), findsOneWidget);
    expect(preferences.lastToolId, 'retired_tool');
  });
}
