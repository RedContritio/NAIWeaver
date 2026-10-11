import 'package:flutter/material.dart';

import '../../../core/utils/resizable_lines.dart';
import '../../../core/widgets/line_resize_handle.dart';

/// Owns the vertical geometry of the generation page.
///
/// Results and the composer are siblings in the same [Column], so neither can
/// paint or receive pointer events through the other's layout region. The
/// optional settings overlay gets an explicit reservation below that column.
class GenerationPageLayout extends StatelessWidget {
  const GenerationPageLayout({
    super.key,
    required this.results,
    required this.footer,
    this.overlay,
    this.overlayReservedHeight = 0,
  });

  static const resultsRegionKey = ValueKey<String>(
    'generation-layout-results-region',
  );
  static const footerRegionKey = ValueKey<String>(
    'generation-layout-footer-region',
  );

  final Widget results;
  final Widget footer;
  final Widget? overlay;
  final double overlayReservedHeight;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          bottom: overlayReservedHeight,
          child: Column(
            children: [
              Expanded(key: resultsRegionKey, child: results),
              KeyedSubtree(key: footerRegionKey, child: footer),
            ],
          ),
        ),
        if (overlay != null) overlay!,
      ],
    );
  }
}

/// Keeps the cost estimate and the generate button inside the prompt field's
/// vertical footprint. It must never add another row to the page footer.
class PromptGenerationAction extends StatelessWidget {
  const PromptGenerationAction({
    super.key,
    required this.generateButton,
    this.estimate,
    this.estimateHeight = 24,
    this.spacing = 4,
  });

  static const regionKey = ValueKey<String>('prompt-generation-action');
  static const estimateKey = ValueKey<String>(
    'prompt-generation-action-estimate',
  );
  static const buttonKey = ValueKey<String>('prompt-generation-action-button');

  final Widget generateButton;
  final Widget? estimate;
  final double estimateHeight;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      key: regionKey,
      child: Column(
        children: [
          if (estimate != null) ...[
            SizedBox(
              key: estimateKey,
              width: double.infinity,
              height: estimateHeight,
              child: estimate,
            ),
            SizedBox(height: spacing),
          ],
          Expanded(
            child: SizedBox(
              key: buttonKey,
              width: double.infinity,
              child: generateButton,
            ),
          ),
        ],
      ),
    );
  }
}

/// Keeps the prompt input and its action rail on one shared vertical contract.
///
/// Callers describe the desired number of text lines rather than separately
/// calculating and passing pixel heights to the input and action widgets.
class GenerationComposerRow extends StatelessWidget {
  const GenerationComposerRow({
    super.key,
    required this.promptInput,
    required this.action,
    required this.promptLines,
    required this.promptFontSize,
    required this.actionWidth,
    this.lineHeight = 1.2,
    this.verticalPadding = 24,
    this.spacing = 4,
  });

  static const promptKey = ValueKey<String>('generation-composer-prompt');
  static const actionKey = ValueKey<String>('generation-composer-action');

  final Widget promptInput;
  final Widget action;
  final int promptLines;
  final double promptFontSize;
  final double actionWidth;
  final double lineHeight;
  final double verticalPadding;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final scaledFontSize = MediaQuery.textScalerOf(
      context,
    ).scale(promptFontSize);
    final extent = scaledFontSize * lineHeight * promptLines + verticalPadding;
    return SizedBox(
      height: extent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: KeyedSubtree(key: promptKey, child: promptInput),
          ),
          SizedBox(width: spacing),
          SizedBox(key: actionKey, width: actionWidth, child: action),
        ],
      ),
    );
  }
}

/// A generation composer with a grab handle directly below the prompt input.
/// The action rail keeps its width and does not become part of the drag target.
class ResizableGenerationComposer extends StatelessWidget {
  const ResizableGenerationComposer({
    super.key,
    required this.promptInput,
    required this.action,
    required this.promptLines,
    required this.promptFontSize,
    required this.actionWidth,
    required this.onPromptLinesChanged,
    required this.onPromptResizeDone,
    this.lineHeight = 1.2,
    this.verticalPadding = 24,
    this.spacing = 4,
    this.minLines = kMainPromptMinLines,
    this.maxLines = kMainPromptMaxLines,
    this.resizeHandleColor,
  });

  static const resizeHandleKey = ValueKey<String>(
    'generation-composer-resize-handle',
  );

  final Widget promptInput;
  final Widget action;
  final int promptLines;
  final double promptFontSize;
  final double actionWidth;
  final ValueChanged<int> onPromptLinesChanged;
  final ValueChanged<int> onPromptResizeDone;
  final double lineHeight;
  final double verticalPadding;
  final double spacing;
  final int minLines;
  final int maxLines;
  final Color? resizeHandleColor;

  @override
  Widget build(BuildContext context) {
    final scaledFontSize = MediaQuery.textScalerOf(
      context,
    ).scale(promptFontSize);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: LineResizeHandle(
                key: resizeHandleKey,
                lines: promptLines,
                lineHeightPx: scaledFontSize * lineHeight,
                minLines: minLines,
                maxLines: maxLines,
                color: resizeHandleColor,
                growUpward: true,
                onLines: onPromptLinesChanged,
                onDone: onPromptResizeDone,
              ),
            ),
            SizedBox(width: spacing + actionWidth),
          ],
        ),
        GenerationComposerRow(
          promptInput: promptInput,
          action: action,
          promptLines: promptLines,
          promptFontSize: promptFontSize,
          actionWidth: actionWidth,
          lineHeight: lineHeight,
          verticalPadding: verticalPadding,
          spacing: spacing,
        ),
      ],
    );
  }
}
