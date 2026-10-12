import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/gateway/backend_error_messages.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/services/novel_ai_service.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_metrics.dart';
import '../../../core/utils/responsive.dart';
import '../../../l10n/app_localizations.dart';

/// True for Ctrl+Enter or Cmd+Enter (main or numpad Enter), the shortcut that
/// runs a tool's primary action. [event] must be a key-down.
bool isToolRunShortcut(KeyEvent event) {
  if (event is! KeyDownEvent) return false;
  final key = event.logicalKey;
  if (key != LogicalKeyboardKey.enter &&
      key != LogicalKeyboardKey.numpadEnter) {
    return false;
  }
  final keyboard = HardwareKeyboard.instance;
  return keyboard.isControlPressed || keyboard.isMetaPressed;
}

/// Runs [onRun] on Ctrl+Enter / Cmd+Enter anywhere inside [child], including
/// from a focused text field. A null [onRun] (the action is unavailable, for
/// example while a request is running) leaves the key alone.
class ToolRunShortcut extends StatelessWidget {
  const ToolRunShortcut({
    super.key,
    required this.onRun,
    required this.child,
    this.focusNode,
  });

  final VoidCallback? onRun;
  final Widget child;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      // Without a focused descendant (the user clicked the image) the
      // shortcut would otherwise never reach this node.
      autofocus: true,
      skipTraversal: focusNode == null ? true : null,
      onKeyEvent: (node, event) {
        final run = onRun;
        if (run == null || !isToolRunShortcut(event)) {
          return KeyEventResult.ignored;
        }
        run();
        return KeyEventResult.handled;
      },
      child: child,
    );
  }
}

/// The text shown for a failed tool request. The notifiers keep the raw
/// error; this turns it into localized text and never shows exception text.
String toolErrorMessage(AppLocalizations l, Object error) {
  if (error is UnauthorizedException) return l.toolErrApiKeyRejected;
  if (error is DioException) return directApiErrorMessage(l, error);
  return backendErrorMessage(l, error);
}

/// Header of the Enhance and Director Tools workspaces: back, an optional
/// save action for an unsaved result, and the primary process action.
///
/// On compact windows the save action (and the process action once a result
/// exists) shrink to icon buttons with tooltips.
class ToolWorkspaceHeader extends StatelessWidget {
  const ToolWorkspaceHeader({
    super.key,
    required this.onBack,
    required this.processIcon,
    required this.processLabel,
    required this.processingLabel,
    required this.isProcessing,
    required this.onProcess,
    this.hasResult = false,
    this.onSave,
    this.showSave = false,
  });

  final VoidCallback onBack;
  final IconData processIcon;
  final String processLabel;
  final String processingLabel;
  final bool isProcessing;

  /// Runs the tool; the button is disabled while [isProcessing].
  final VoidCallback onProcess;
  final bool hasResult;

  /// Whether an unsaved result is waiting for the save button.
  final bool showSave;

  /// Null disables the save button (a save is already running).
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    final compact = windowSizeClassOf(context) == WindowSizeClass.compact;
    final height = context.hitSize;
    final labelStyle = TextStyle(
      fontSize: t.fontSize(10),
      fontWeight: FontWeight.bold,
      letterSpacing: 1,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(VisionMetrics.radius4),
    );

    final processSpinner = SizedBox(
      width: VisionMetrics.iconSmall,
      height: VisionMetrics.iconSmall,
      child: CircularProgressIndicator(strokeWidth: 2, color: t.background),
    );
    final processGlyph = isProcessing
        ? processSpinner
        : Icon(processIcon, size: VisionMetrics.iconSmall);
    final onPressed = isProcessing ? null : onProcess;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: VisionMetrics.space16,
        vertical: VisionMetrics.space8,
      ),
      decoration: BoxDecoration(
        color: t.surfaceHigh,
        border: Border(bottom: BorderSide(color: t.borderSubtle)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.arrow_back,
              size: VisionMetrics.iconMedium,
              color: t.textDisabled,
            ),
            onPressed: onBack,
            tooltip: l.img2imgBackToPicker,
          ),
          const Spacer(),
          if (showSave) ...[
            SizedBox(
              height: height,
              child: compact
                  ? IconButton(
                      onPressed: onSave,
                      icon: const Icon(
                        Icons.save_alt,
                        size: VisionMetrics.iconSmall,
                      ),
                      tooltip: l.commonSave,
                      style: IconButton.styleFrom(
                        backgroundColor: t.accentSuccess,
                        foregroundColor: t.background,
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: onSave,
                      icon: const Icon(
                        Icons.save_alt,
                        size: VisionMetrics.iconSmall,
                      ),
                      label: Text(l.commonSave),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: t.accentSuccess,
                        foregroundColor: t.background,
                        textStyle: labelStyle,
                        padding: const EdgeInsets.symmetric(
                          horizontal: VisionMetrics.space16,
                        ),
                        shape: shape,
                        elevation: 0,
                      ),
                    ),
            ),
            const SizedBox(width: VisionMetrics.space8),
          ],
          SizedBox(
            height: height,
            child: compact && hasResult
                ? IconButton(
                    onPressed: onPressed,
                    icon: processGlyph,
                    tooltip: isProcessing ? processingLabel : processLabel,
                    style: IconButton.styleFrom(
                      backgroundColor: t.accent,
                      foregroundColor: t.background,
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: onPressed,
                    icon: processGlyph,
                    label: Text(isProcessing ? processingLabel : processLabel),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.accent,
                      foregroundColor: t.background,
                      textStyle: labelStyle,
                      padding: const EdgeInsets.symmetric(
                        horizontal:
                            VisionMetrics.space16 + VisionMetrics.space4,
                      ),
                      shape: shape,
                      elevation: 0,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
