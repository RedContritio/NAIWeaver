import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/widgets/browser_native_selectable_text.dart';

void main() {
  testWidgets('renders selectable output through the platform abstraction', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BrowserNativeSelectableText(text: 'fb_test_ticket', height: 38),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(BrowserNativeSelectableText), findsOneWidget);
  });
}
