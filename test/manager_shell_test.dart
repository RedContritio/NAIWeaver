import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/widgets/manager_list_tile.dart';
import 'package:naiweaver/core/widgets/manager_shell.dart';

import 'test_harness.dart';

const _mobile = Size(360, 720);
const _desktop = Size(900, 720);

/// Hosts a shell whose editor opens from the list and records guard calls.
class _ShellHost extends StatefulWidget {
  const _ShellHost({required this.dirty, required this.log});

  final bool dirty;
  final List<String> log;

  @override
  State<_ShellHost> createState() => _ShellHostState();
}

class _ShellHostState extends State<_ShellHost> {
  bool _showDetail = false;
  late bool _dirty = widget.dirty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ManagerMasterDetailShell(
        showDetail: _showDetail,
        masterHeader: const ManagerHeader(title: 'MANAGER', subtitle: 'desc'),
        master: TextButton(
          onPressed: () => setState(() => _showDetail = true),
          child: const Text('open item'),
        ),
        detail: const Text('editor body'),
        detailTitle: 'ITEM',
        onCloseDetail: () => setState(() => _showDetail = false),
        guard: UnsavedChangesGuard(
          hasChanges: _dirty,
          onSave: () async {
            widget.log.add('save');
            setState(() => _dirty = false);
            return true;
          },
          onDiscard: () {
            widget.log.add('discard');
            setState(() => _dirty = false);
          },
        ),
      ),
    );
  }
}

Future<void> _pushHost(
  WidgetTester tester, {
  required Size size,
  bool dirty = false,
  List<String>? log,
}) async {
  setSurfaceSize(tester, size);
  final preferences = await testPreferences();
  await tester.pumpWidget(
    harnessApp(
      preferences: preferences,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _ShellHost(dirty: dirty, log: log ?? []),
              ),
            ),
            child: const Text('launch'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('launch'));
  await tester.pumpAndSettle();
}

/// Sends the platform back gesture (Android back / browser back).
Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  group('ManagerMasterDetailShell', () {
    testWidgets('phone list keeps the manager header; editor has a back tooltip', (
      tester,
    ) async {
      await _pushHost(tester, size: _mobile);

      expect(find.text('MANAGER'), findsOneWidget);
      expect(find.byKey(ManagerMasterDetailShell.masterPaneKey), findsOneWidget);
      expect(find.byKey(ManagerMasterDetailShell.detailPaneKey), findsNothing);

      await tester.tap(find.text('open item'));
      await tester.pumpAndSettle();

      expect(find.text('MANAGER'), findsNothing);
      expect(find.text('ITEM'), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(tester.getSize(find.byTooltip('Back')).width, greaterThanOrEqualTo(40));
    });

    testWidgets('system back returns from the editor to the list, not out of Tools', (
      tester,
    ) async {
      await _pushHost(tester, size: _mobile);
      await tester.tap(find.text('open item'));
      await tester.pumpAndSettle();

      await _systemBack(tester);

      expect(find.byType(_ShellHost), findsOneWidget);
      expect(find.byKey(ManagerMasterDetailShell.masterPaneKey), findsOneWidget);

      await _systemBack(tester);
      expect(find.byType(_ShellHost), findsNothing);
    });

    testWidgets('back with unsaved changes asks first; cancel stays, discard leaves', (
      tester,
    ) async {
      final log = <String>[];
      await _pushHost(tester, size: _mobile, dirty: true, log: log);
      await tester.tap(find.text('open item'));
      await tester.pumpAndSettle();

      await _systemBack(tester);
      expect(find.text('UNSAVED CHANGES'), findsOneWidget);
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
      expect(find.text('editor body'), findsOneWidget);
      expect(log, isEmpty);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DISCARD'));
      await tester.pumpAndSettle();
      expect(log, ['discard']);
      expect(find.byKey(ManagerMasterDetailShell.masterPaneKey), findsOneWidget);
      expect(find.byType(_ShellHost), findsOneWidget);
    });

    testWidgets('leaving Tools with unsaved changes on a wide screen asks first', (
      tester,
    ) async {
      final log = <String>[];
      await _pushHost(tester, size: _desktop, dirty: true, log: log);
      expect(find.byKey(ManagerMasterDetailShell.detailPaneKey), findsOneWidget);

      await _systemBack(tester);
      expect(find.text('UNSAVED CHANGES'), findsOneWidget);
      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();

      expect(log, ['save']);
      expect(find.byType(_ShellHost), findsNothing);
    });

    testWidgets('a clean wide-screen manager closes on back without asking', (
      tester,
    ) async {
      await _pushHost(tester, size: _desktop);
      await _systemBack(tester);
      expect(find.text('UNSAVED CHANGES'), findsNothing);
      expect(find.byType(_ShellHost), findsNothing);
    });
  });

  testWidgets('header truncates long names and keeps its actions', (tester) async {
    await pumpHarness(
      tester,
      SizedBox(
        width: 260,
        child: ManagerHeader(
          title: 'A VERY LONG PRESET NAME THAT MUST NOT PUSH SAVE AWAY',
          onBack: () {},
          actions: [
            ManagerIconButton(
              key: const ValueKey<String>('save-action'),
              icon: Icons.save,
              tooltip: 'Save',
              onPressed: () {},
            ),
          ],
        ),
      ),
    );

    final title = tester.widget<Text>(find.byKey(ManagerHeader.titleKey));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(find.byKey(const ValueKey<String>('save-action')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('list tile truncates, keeps a 40px menu and runs its actions', (
    tester,
  ) async {
    var duplicated = false;
    await pumpHarness(
      tester,
      SizedBox(
        width: 180,
        child: ManagerListTile(
          title: 'AN EXTREMELY LONG WILDCARD FILE NAME WITHOUT ANY BREAKS',
          dragIndex: 0,
          leading: const Icon(Icons.description_outlined, size: 12),
          menuActions: [
            ManagerListAction(
              label: 'Duplicate',
              icon: Icons.copy,
              onSelected: () => duplicated = true,
            ),
          ],
        ),
      ),
    );

    final title = tester.widget<Text>(find.byKey(ManagerListTile.titleKey));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);

    final menu = tester.getSize(find.byKey(ManagerListTile.menuKey));
    expect(menu.width, greaterThanOrEqualTo(kManagerTouchTarget));
    expect(menu.height, greaterThanOrEqualTo(kManagerTouchTarget));

    await tester.tap(find.byKey(ManagerListTile.menuKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DUPLICATE'));
    await tester.pumpAndSettle();
    expect(duplicated, isTrue);
  });

  testWidgets('count toolbar retains clear and count actions without a title', (
    tester,
  ) async {
    var cleared = false;
    await pumpHarness(
      tester,
      ManagerCountToolbar(
        countLabel: '3 REFERENCES',
        clearLabel: 'CLEAR ALL',
        onClear: () => cleared = true,
        countStyle: const TextStyle(),
        clearStyle: const TextStyle(),
      ),
    );

    expect(find.byKey(ManagerCountToolbar.toolbarKey), findsOneWidget);
    expect(find.text('3 REFERENCES'), findsOneWidget);
    await tester.tap(find.text('CLEAR ALL'));
    expect(cleared, isTrue);
  });
}
