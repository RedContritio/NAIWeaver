import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/widgets/ui/overlay_action_button.dart';

import 'test_harness.dart';

void main() {
  for (final entry in {840.0: true, 600.0: false}.entries) {
    final shown = entry.value;
    testWidgets('label is ${shown ? 'shown' : 'hidden'} at ${entry.key}', (
      tester,
    ) async {
      await pumpHarness(
        tester,
        OverlayActionButton(
          icon: Icons.save,
          tooltip: 'Save',
          label: 'Save',
          onPressed: () {},
        ),
        size: Size(entry.key, 700),
      );
      expect(find.text('SAVE'), shown ? findsOneWidget : findsNothing);
    });
  }
}
