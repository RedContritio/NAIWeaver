import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/features/generation/widgets/generation_page_layout.dart';
import 'package:naiweaver/features/generation/widgets/settings_panel.dart';

void main() {
  testWidgets('results and prompt regions never overlap', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: GenerationPageLayout(
              overlayReservedHeight: 48,
              results: ColoredBox(color: Colors.black),
              footer: SizedBox(
                height: 180,
                child: ColoredBox(color: Colors.red),
              ),
              overlay: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  height: 48,
                  child: ColoredBox(color: Colors.blue),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final resultsRect = tester.getRect(
      find.byKey(GenerationPageLayout.resultsRegionKey),
    );
    final footerRect = tester.getRect(
      find.byKey(GenerationPageLayout.footerRegionKey),
    );

    expect(resultsRect.bottom, footerRect.top);
    expect(footerRect.bottom, 552);
  });

  testWidgets('composer gives prompt and action the same height', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: GenerationComposerRow(
              promptLines: 4,
              promptFontSize: 12,
              actionWidth: 72,
              promptInput: ColoredBox(color: Colors.red),
              action: PromptGenerationAction(
                estimateHeight: 23,
                estimate: ColoredBox(color: Colors.green),
                generateButton: ColoredBox(color: Colors.blue),
              ),
            ),
          ),
        ),
      ),
    );

    final region = tester.getRect(find.byKey(PromptGenerationAction.regionKey));
    final estimate = tester.getRect(
      find.byKey(PromptGenerationAction.estimateKey),
    );
    final button = tester.getRect(find.byKey(PromptGenerationAction.buttonKey));
    final prompt = tester.getRect(find.byKey(GenerationComposerRow.promptKey));

    expect(region.height, prompt.height);
    expect(estimate.top, region.top);
    expect(button.top, estimate.bottom + 4);
    expect(button.bottom, region.bottom);
  });

  testWidgets('composer scales prompt and action together', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Scaffold(
            body: GenerationComposerRow(
              promptLines: 5,
              promptFontSize: 12,
              actionWidth: 68,
              promptInput: ColoredBox(color: Colors.red),
              action: PromptGenerationAction(
                generateButton: ColoredBox(color: Colors.blue),
              ),
            ),
          ),
        ),
      ),
    );

    final prompt = tester.getRect(find.byKey(GenerationComposerRow.promptKey));
    final action = tester.getRect(find.byKey(GenerationComposerRow.actionKey));
    expect(prompt.height, action.height);
    expect(prompt.height, 12 * 1.8 * 1.2 * 5 + 24);
  });

  testWidgets('settings collapsed extent is shared with safe area', (
    tester,
  ) async {
    double? extent;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(800, 600),
            viewPadding: EdgeInsets.only(bottom: 18),
          ),
          child: Builder(
            builder: (context) {
              extent = AdvancedSettingsPanel.collapsedExtent(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(extent, 58);
  });
}
