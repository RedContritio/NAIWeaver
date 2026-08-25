import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/features/tools/widgets/manager_shell.dart';

void main() {
  Widget shell({
    required bool mobile,
    required bool showDetail,
    bool showMasterHeaderOnMobile = true,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ManagerMasterDetailShell(
          mobile: mobile,
          showDetail: showDetail,
          masterHeader: const Text('master header'),
          detailHeader: const Text('detail header'),
          master: const SizedBox(width: 220, child: Text('master body')),
          detail: const Text('detail body'),
          dividerColor: Colors.grey,
          showMasterHeaderOnMobile: showMasterHeaderOnMobile,
        ),
      ),
    );
  }

  testWidgets('mobile shell switches one header and one pane together', (
    tester,
  ) async {
    await tester.pumpWidget(shell(mobile: true, showDetail: false));

    expect(
      find.byKey(ManagerMasterDetailShell.activeHeaderKey),
      findsOneWidget,
    );
    expect(find.text('master header'), findsOneWidget);
    expect(find.text('detail header'), findsNothing);
    expect(find.byKey(ManagerMasterDetailShell.masterPaneKey), findsOneWidget);
    expect(find.byKey(ManagerMasterDetailShell.detailPaneKey), findsNothing);

    await tester.pumpWidget(shell(mobile: true, showDetail: true));
    await tester.pump();

    expect(
      find.byKey(ManagerMasterDetailShell.activeHeaderKey),
      findsOneWidget,
    );
    expect(find.text('master header'), findsNothing);
    expect(find.text('detail header'), findsOneWidget);
    expect(find.byKey(ManagerMasterDetailShell.masterPaneKey), findsNothing);
    expect(find.byKey(ManagerMasterDetailShell.detailPaneKey), findsOneWidget);
  });

  testWidgets('mobile master can rely on the owning ToolsHub app bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      shell(mobile: true, showDetail: false, showMasterHeaderOnMobile: false),
    );

    expect(find.byKey(ManagerMasterDetailShell.activeHeaderKey), findsNothing);
    expect(find.text('master header'), findsNothing);
    expect(find.byKey(ManagerMasterDetailShell.masterPaneKey), findsOneWidget);
  });

  testWidgets('desktop shell keeps one header and both panes', (tester) async {
    await tester.pumpWidget(shell(mobile: false, showDetail: true));

    expect(find.text('master header'), findsOneWidget);
    expect(find.text('detail header'), findsNothing);
    expect(find.byKey(ManagerMasterDetailShell.masterPaneKey), findsOneWidget);
    expect(find.byKey(ManagerMasterDetailShell.detailPaneKey), findsOneWidget);
  });

  testWidgets('mobile detail exposes only its save action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManagerMasterDetailShell(
            mobile: true,
            showDetail: true,
            masterHeader: IconButton(
              key: const ValueKey<String>('master-save'),
              onPressed: () {},
              icon: const Icon(Icons.save),
            ),
            detailHeader: IconButton(
              key: const ValueKey<String>('detail-save'),
              onPressed: () {},
              icon: const Icon(Icons.save_outlined),
            ),
            master: const SizedBox.shrink(),
            detail: const SizedBox.shrink(),
            dividerColor: Colors.grey,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey<String>('master-save')), findsNothing);
    expect(find.byKey(const ValueKey<String>('detail-save')), findsOneWidget);
  });

  testWidgets('detail header constrains long names and keeps actions visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            child: ManagerDetailHeader(
              title: 'A VERY LONG PRESET NAME THAT MUST NOT PUSH SAVE AWAY',
              backgroundColor: Colors.black,
              iconColor: Colors.white,
              textStyle: const TextStyle(color: Colors.white),
              onBack: () {},
              actions: [
                IconButton(
                  key: const ValueKey<String>('save-action'),
                  onPressed: () {},
                  icon: const Icon(Icons.save),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final title = tester.widget<Text>(find.byKey(ManagerDetailHeader.titleKey));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(find.byKey(const ValueKey<String>('save-action')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('count toolbar retains clear and count actions without a title', (
    tester,
  ) async {
    var cleared = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManagerCountToolbar(
            countLabel: '3 REFERENCES',
            clearLabel: 'CLEAR ALL',
            onClear: () => cleared = true,
            countStyle: const TextStyle(),
            clearStyle: const TextStyle(),
          ),
        ),
      ),
    );

    expect(find.byKey(ManagerCountToolbar.toolbarKey), findsOneWidget);
    expect(find.text('3 REFERENCES'), findsOneWidget);
    await tester.tap(find.text('CLEAR ALL'));
    expect(cleared, isTrue);
  });
}
