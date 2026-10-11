import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/widgets/text_input_dialog.dart';

import 'test_harness.dart';

void main() {
  Future<Future<String?>> openDialog(WidgetTester tester) async {
    await pumpHarness(tester, const SizedBox.shrink());
    final context = tester.element(find.byType(SizedBox).last);
    final result = showTextInputDialog(
      context,
      title: 'NAME IT',
      confirmLabel: 'Save',
      hintText: 'NAME',
    );
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('whitespace-only names are rejected and the dialog stays open', (
    tester,
  ) async {
    final result = await openDialog(tester);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    expect(find.text('NAME IT'), findsOneWidget);
    expect(find.text('Name cannot be empty'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '  Hero  ');
    await tester.pump();
    expect(find.text('Name cannot be empty'), findsNothing);
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    expect(await result, 'Hero');
    expect(find.text('NAME IT'), findsNothing);
  });

  testWidgets('cancel returns null and the controller is disposed', (
    tester,
  ) async {
    final result = await openDialog(tester);
    final controller = tester
        .widget<EditableText>(find.byType(EditableText))
        .controller;

    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();

    expect(await result, isNull);
    expect(() => controller.addListener(() {}), throwsFlutterError);
  });
}
