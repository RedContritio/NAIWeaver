import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/core/widgets/card_action_layout.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('open menu survives content refresh and badge changes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = PreferencesService(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
    final revision = ValueNotifier(0);
    addTearDown(revision.dispose);
    final imports = <int>[];
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeNotifier(preferences),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 200,
                child: ValueListenableBuilder<int>(
                  valueListenable: revision,
                  builder: (_, value, _) => CardActionLayout(
                    content: value.isEven
                        ? const ColoredBox(color: Colors.grey)
                        : const Text('Updated thumbnail'),
                    badge: value.isEven ? null : const Text('2 images'),
                    action: PopupMenuButton<String>(
                      onSelected: (_) => imports.add(value),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'import', child: Text('Import')),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    Future<void> click(Finder target) async {
      await mouse.moveTo(tester.getCenter(target));
      await tester.pumpAndSettle();
      await mouse.down(tester.getCenter(target));
      await mouse.up();
      await tester.pumpAndSettle();
    }

    final menu = find.byType(PopupMenuButton<String>);
    for (final next in [1, 2]) {
      final originalState = tester.state(menu);
      await click(menu);
      revision.value = next;
      await tester.pumpAndSettle();
      expect(identical(tester.state(menu), originalState), isTrue);
      await click(find.text('Import'));
      expect(imports.last, next);
    }
    expect(imports, [1, 2]);
  });
}
