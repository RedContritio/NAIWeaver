import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    testWidgets(
      'system back returns from the editor to the list, not out of Tools',
      (tester) async {
        await _pushHost(tester, size: _mobile);
        await tester.tap(find.text('open item'));
        await tester.pumpAndSettle();

        await _systemBack(tester);

        expect(find.byType(_ShellHost), findsOneWidget);
        expect(
          find.byKey(ManagerMasterDetailShell.masterPaneKey),
          findsOneWidget,
        );

        await _systemBack(tester);
        expect(find.byType(_ShellHost), findsNothing);
      },
    );

    testWidgets(
      'back with unsaved changes asks first; cancel stays, discard leaves',
      (tester) async {
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
        expect(
          find.byKey(ManagerMasterDetailShell.masterPaneKey),
          findsOneWidget,
        );
        expect(find.byType(_ShellHost), findsOneWidget);
      },
    );

    testWidgets(
      'leaving Tools with unsaved changes on a wide screen asks first',
      (tester) async {
        final log = <String>[];
        await _pushHost(tester, size: _desktop, dirty: true, log: log);
        expect(
          find.byKey(ManagerMasterDetailShell.detailPaneKey),
          findsOneWidget,
        );

        await _systemBack(tester);
        expect(find.text('UNSAVED CHANGES'), findsOneWidget);
        await tester.tap(find.text('SAVE'));
        await tester.pumpAndSettle();

        expect(log, ['save']);
        expect(find.byType(_ShellHost), findsNothing);
      },
    );

  });

}
