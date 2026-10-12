import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/features/generation/widgets/browser_photo_swipe_viewer.dart';
import 'package:naiweaver/features/generation/widgets/generation_results_workspace.dart';

import 'support/generation_rig.dart';
import 'test_harness.dart';

void main() {
  testWidgets(
    'selected pending batch item does not show another completed image',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('naiweaver_results');
      addTearDown(() => dir.deleteSync(recursive: true));
      final png = File('assets/logo.png').readAsBytesSync();
      late final GatewayRig rig;
      await tester.runAsync(() async {
        rig = await GatewayRig.create(dir, png);
        final generation = rig.generation;
        await generation.toggleAutoSave(false);
        generation.promptController.text = '1girl';
        generation.updateSettings(batchCount: 2, isStyleEnabled: false);
        unawaited(generation.generate(batchLimit: 2));
        await eventually(() => generation.state.generatedImages.length == 2);

        // The first image is done, the second is still being made and selected.
        rig.gateway.status[rig.gateway.itemIds[1]] = 'running';
        rig.gateway.status[rig.gateway.itemIds[0]] = 'success';
        await eventually(() => generation.state.generatedImages[0].isComplete);
        generation.selectGeneratedImage(generation.state.generatedImages[1].id);
      });
      addTearDown(rig.generation.dispose);

      await pumpHarness(
        tester,
        GenerationResultsWorkspace(
          notifier: rig.generation,
          state: rig.generation.state,
          mobile: true,
          pulseAnimation: const AlwaysStoppedAnimation(0),
          showQuickActions: false,
        ),
      );
      await tester.tap(find.byIcon(Icons.image_outlined));
      await tester.pump();

      expect(find.byType(BrowserPhotoSwipeViewer), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(
        find.byKey(const ValueKey<String>('result-set-preview-status')),
        findsOneWidget,
      );
    },
  );
}
