import 'package:flutter/material.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/theme/vision_tokens.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/theme/vision_metrics.dart';

void showCanvasHelpDialog(BuildContext context) {
  final t = context.tRead;
  final l = context.l;
  final mobile = isTouchSized(context);

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: t.surfaceHigh,
        title: Text(
          l.canvasHelp.toUpperCase(),
          style: TextStyle(
            color: t.textPrimary,
            fontSize: t.fontSize(mobile ? 16 : 14),
            fontWeight: FontWeight.w900,
            letterSpacing: 4,
          ),
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9 > 520
              ? 520
              : MediaQuery.of(context).size.width * 0.9,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader(t, l.canvasHelpToolsHeader, mobile),
                const SizedBox(height: VisionMetrics.space8),
                _shortcutRow(t, 'B', l.canvasHelpPaint, mobile),
                _shortcutRow(t, 'E', l.canvasHelpErase, mobile),
                _shortcutRow(t, 'L', l.canvasHelpLine, mobile),
                _shortcutRow(t, 'R', l.canvasHelpRectangle, mobile),
                _shortcutRow(t, 'O', l.canvasHelpCircle, mobile),
                _shortcutRow(t, 'G', l.canvasHelpFill, mobile),
                _shortcutRow(t, 'T', l.canvasHelpText, mobile),
                _shortcutRow(t, 'C', l.canvasHelpEyedropper, mobile),
                _shortcutRow(t, 'V', l.canvasHelpTransform, mobile),
                _shortcutRow(t, 'S', l.canvasHelpSelect, mobile),
                _shortcutRow(t, 'A', l.canvasHelpLasso, mobile),
                _shortcutRow(t, '—', l.canvasHelpBlur, mobile),
                _shortcutRow(t, '—', l.canvasHelpClone, mobile),

                const SizedBox(height: VisionMetrics.space16),
                Divider(
                  color: t.textDisabled.withValues(
                    alpha: VisionMetrics.opacityDisabled,
                  ),
                  height: 1,
                ),
                const SizedBox(height: VisionMetrics.space16),

                _sectionHeader(t, l.canvasHelpNavigationHeader, mobile),
                const SizedBox(height: VisionMetrics.space8),
                _shortcutRow(t, l.canvasHelpKeySpaceDrag, l.canvasHelpPan, mobile),
                _shortcutRow(t, l.canvasHelpKeyScroll, l.canvasHelpZoom, mobile),
                _shortcutRow(t, l.canvasHelpKeyCtrlScroll, l.canvasHelpBrushSize, mobile),
                _shortcutRow(t, '[ / ]', l.canvasHelpBrushStep, mobile),

                const SizedBox(height: VisionMetrics.space16),
                Divider(
                  color: t.textDisabled.withValues(
                    alpha: VisionMetrics.opacityDisabled,
                  ),
                  height: 1,
                ),
                const SizedBox(height: VisionMetrics.space16),

                _sectionHeader(t, l.canvasHelpActionsHeader, mobile),
                const SizedBox(height: VisionMetrics.space8),
                _shortcutRow(t, 'Ctrl + Z', l.canvasUndo, mobile),
                _shortcutRow(t, 'Ctrl + Y', l.canvasRedo, mobile),
                _shortcutRow(t, l.canvasHelpKeyEscape, l.canvasHelpCancelSelection, mobile),
                _shortcutRow(
                  t,
                  l.canvasHelpKeyAltClick,
                  l.canvasHelpSetCloneSource,
                  mobile,
                ),

                const SizedBox(height: VisionMetrics.space16),
                Divider(
                  color: t.textDisabled.withValues(
                    alpha: VisionMetrics.opacityDisabled,
                  ),
                  height: 1,
                ),
                const SizedBox(height: VisionMetrics.space16),

                _sectionHeader(t, l.canvasHelpModesHeader, mobile),
                const SizedBox(height: VisionMetrics.space8),
                _modeRow(
                  t,
                  l.canvasHelpModeSelect,
                  l.canvasHelpModeSelectDesc,
                  mobile,
                ),
                _modeRow(
                  t,
                  l.canvasHelpModeLasso,
                  l.canvasHelpModeLassoDesc,
                  mobile,
                ),
                _modeRow(
                  t,
                  l.canvasHelpModeBlur,
                  l.canvasHelpModeBlurDesc,
                  mobile,
                ),
                _modeRow(
                  t,
                  l.canvasHelpModeClone,
                  l.canvasHelpModeCloneDesc,
                  mobile,
                ),
                _modeRow(
                  t,
                  l.canvasHelpModeSmooth,
                  l.canvasHelpModeSmoothDesc,
                  mobile,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              l.commonClose.toUpperCase(),
              style: TextStyle(
                color: t.accent,
                fontSize: t.fontSize(12),
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      );
    },
  );
}

Widget _sectionHeader(VisionTokens t, String label, bool mobile) {
  return Text(
    label,
    style: TextStyle(
      color: t.textSecondary,
      fontSize: t.fontSize(mobile ? 11 : 10),
      fontWeight: FontWeight.bold,
      letterSpacing: 2,
    ),
  );
}

Widget _shortcutRow(
  VisionTokens t,
  String syntax,
  String description,
  bool mobile,
) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: VisionMetrics.space4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: mobile ? 120 : 130,
          child: Text(
            syntax,
            style: TextStyle(
              color: t.accent,
              fontSize: t.fontSize(mobile ? 12 : 11),
              fontFamily: 'Consolas',
              fontFamilyFallback: const ['monospace'],
            ),
          ),
        ),
        Expanded(
          child: Text(
            description,
            style: TextStyle(
              color: t.textTertiary,
              fontSize: t.fontSize(mobile ? 12 : 11),
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _modeRow(VisionTokens t, String name, String description, bool mobile) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: VisionMetrics.space4),
    child: RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: name,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: t.fontSize(mobile ? 12 : 11),
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: '  $description',
            style: TextStyle(
              color: t.textTertiary,
              fontSize: t.fontSize(mobile ? 12 : 11),
            ),
          ),
        ],
      ),
    ),
  );
}
