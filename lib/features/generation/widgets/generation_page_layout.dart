import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../../../core/utils/resizable_lines.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/browser_native_text_area.dart';
import '../../../core/widgets/line_resize_handle.dart';
import '../../../core/widgets/web_style_bridge.dart';

/// Which arrangement the generation page uses.
enum GenerationLayoutMode {
  /// Touch-sized windows (< 840): a bottom sheet holds prompt, inputs and
  /// parameters.
  sheet,

  /// Expanded windows (840-1199): prompt footer plus the bottom settings
  /// panel.
  regular,

  /// Large windows (>= 1200) that allow it: settings in a left sidebar.
  sidebar,
}

/// The one answer to "which layout is this window" for the generation page.
/// Computed once per build from the Material 3 window size class, so no part
/// of the page compares widths on its own.
class GenerationLayoutSpec {
  const GenerationLayoutSpec({required this.sizeClass, required this.mode});

  /// [sidebarMode] is the user's `auto` / `always` / `never` setting: `never`
  /// keeps the regular layout on wide windows, `auto` limits the sidebar to
  /// desktop platforms.
  factory GenerationLayoutSpec.of(
    BuildContext context, {
    required String sidebarMode,
  }) => GenerationLayoutSpec.resolve(
    windowSizeClassOf(context),
    sidebarMode: sidebarMode,
    desktop: isDesktopPlatform(),
  );

  factory GenerationLayoutSpec.resolve(
    WindowSizeClass sizeClass, {
    required String sidebarMode,
    required bool desktop,
  }) {
    final sidebarAllowed =
        sidebarMode == 'always' || (sidebarMode != 'never' && desktop);
    final mode = sizeClass.isTouchSized
        ? GenerationLayoutMode.sheet
        : sizeClass.isSidebarCapable && sidebarAllowed
        ? GenerationLayoutMode.sidebar
        : GenerationLayoutMode.regular;
    return GenerationLayoutSpec(sizeClass: sizeClass, mode: mode);
  }

  final WindowSizeClass sizeClass;
  final GenerationLayoutMode mode;

  /// Compact and medium windows: touch-sized controls.
  bool get touch => sizeClass.isTouchSized;

  /// Phone-width windows: the app bar folds secondary actions away.
  bool get compact => sizeClass == WindowSizeClass.compact;

  bool get isSheet => mode == GenerationLayoutMode.sheet;
  bool get isSidebar => mode == GenerationLayoutMode.sidebar;
}

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
    this.overlayReservedHeightOf,
  }) : assert(overlayReservedHeightOf == null || overlayReservedHeight == 0);

  static const resultsRegionKey = ValueKey<String>(
    'generation-layout-results-region',
  );
  static const footerRegionKey = ValueKey<String>(
    'generation-layout-footer-region',
  );

  final Widget results;
  final Widget footer;
  final Widget? overlay;

  /// Height kept free below the column for [overlay].
  final double overlayReservedHeight;

  /// Resolves the reservation in this layout's own context instead of the
  /// caller's. An overlay that sizes itself from the [MediaQuery] it sees
  /// here (a [Scaffold] body, for one, drops the bottom safe area while the
  /// keyboard is up) then gets exactly the room it occupies.
  final double Function(BuildContext context)? overlayReservedHeightOf;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          bottom:
              overlayReservedHeightOf?.call(context) ?? overlayReservedHeight,
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
    final scaledFontSize = _inputFontSize(context, promptFontSize);
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

/// A generation composer with a grab handle directly above the prompt input.
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
    final scaledFontSize = _inputFontSize(context, promptFontSize);
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

/// The rendered font size of the prompt input: the browser-native textarea
/// raises it to the mobile floor, so the row height must follow.
double _inputFontSize(BuildContext context, double fontSize) {
  final scaler = MediaQuery.textScalerOf(context);
  return supportsBrowserNativeTextArea
      ? browserInputFontSize(
          fontSize,
          textScaler: scaler,
          platform: defaultTargetPlatform,
        )
      : scaler.scale(fontSize);
}
