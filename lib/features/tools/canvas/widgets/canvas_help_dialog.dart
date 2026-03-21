import 'package:flutter/material.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/theme/vision_tokens.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/utils/responsive.dart';

void showCanvasHelpDialog(BuildContext context) {
  final t = context.tRead;
  final l = context.l;
  final mobile = isMobile(context);

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
                _sectionHeader(t, 'TOOLS', mobile),
                const SizedBox(height: 8),
                _shortcutRow(t, 'B', 'Paint — freehand brush', mobile),
                _shortcutRow(t, 'E', 'Erase — remove strokes', mobile),
                _shortcutRow(t, 'L', 'Line — straight line', mobile),
                _shortcutRow(t, 'R', 'Rectangle — outline or filled', mobile),
                _shortcutRow(t, 'O', 'Circle / Ellipse', mobile),
                _shortcutRow(t, 'G', 'Fill — flood fill area', mobile),
                _shortcutRow(t, 'T', 'Text — add text to canvas', mobile),
                _shortcutRow(t, 'C', 'Eyedropper — pick color', mobile),
                _shortcutRow(t, 'V', 'Transform — move/scale layer', mobile),
                _shortcutRow(t, 'S', 'Select — rectangular selection', mobile),
                _shortcutRow(t, 'A', 'Lasso — freehand selection', mobile),
                _shortcutRow(t, '—', 'Blur — Gaussian blur brush', mobile),
                _shortcutRow(t, '—', 'Clone Stamp — copy from source', mobile),

                const SizedBox(height: 16),
                Divider(color: t.textDisabled.withValues(alpha: 0.3), height: 1),
                const SizedBox(height: 16),

                _sectionHeader(t, 'NAVIGATION', mobile),
                const SizedBox(height: 8),
                _shortcutRow(t, 'Space + drag', 'Pan canvas', mobile),
                _shortcutRow(t, 'Scroll', 'Zoom in / out', mobile),
                _shortcutRow(t, 'Ctrl + Scroll', 'Adjust brush size', mobile),
                _shortcutRow(t, '[ / ]', 'Decrease / increase brush', mobile),

                const SizedBox(height: 16),
                Divider(color: t.textDisabled.withValues(alpha: 0.3), height: 1),
                const SizedBox(height: 16),

                _sectionHeader(t, 'ACTIONS', mobile),
                const SizedBox(height: 8),
                _shortcutRow(t, 'Ctrl + Z', 'Undo', mobile),
                _shortcutRow(t, 'Ctrl + Y', 'Redo', mobile),
                _shortcutRow(t, 'Escape', 'Cancel selection', mobile),
                _shortcutRow(t, 'Alt + click', 'Set clone stamp source', mobile),

                const SizedBox(height: 16),
                Divider(color: t.textDisabled.withValues(alpha: 0.3), height: 1),
                const SizedBox(height: 16),

                _sectionHeader(t, 'MODES', mobile),
                const SizedBox(height: 8),
                _modeRow(t, 'Select', 'Rectangular selection with corner handles for move, rotate, and scale.', mobile),
                _modeRow(t, 'Lasso', 'Freehand selection path with bounding box handles.', mobile),
                _modeRow(t, 'Blur', 'Applies Gaussian blur. Adjust sigma with the size slider.', mobile),
                _modeRow(t, 'Clone Stamp', 'Copies pixels from a source point. Alt+click to set source, then paint.', mobile),
                _modeRow(t, 'Smooth', 'Toggle in toolbar for anti-aliased brush strokes.', mobile),
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

Widget _shortcutRow(VisionTokens t, String syntax, String description, bool mobile) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
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
    padding: const EdgeInsets.symmetric(vertical: 4),
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
