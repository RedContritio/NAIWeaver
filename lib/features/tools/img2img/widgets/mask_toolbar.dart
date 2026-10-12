import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../../../../core/utils/file_picker_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/theme/vision_metrics.dart';
import '../../../../core/theme/vision_tokens.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/web_download.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/widgets/ui/app_pill.dart';
import '../../../../core/widgets/ui/app_tone.dart';
import '../../../../core/widgets/vision_slider.dart';
import '../providers/img2img_notifier.dart';
import '../services/mask_encoder.dart';

/// Preset mask colors for the dropdown.
const _maskColorPresets = <int>[
  0xFFFF0066, // pink (default)
  0xFF2196F3, // blue
  0xFF4CAF50, // green
  0xFFFF9800, // orange
  0xFFFFEB3B, // yellow
  0xFFE040FB, // purple
  0xFFFFFFFF, // white
  0xFFFF0000, // red
];

class MaskToolbar extends StatefulWidget {
  const MaskToolbar({super.key});

  @override
  State<MaskToolbar> createState() => _MaskToolbarState();
}

class _MaskToolbarState extends State<MaskToolbar> {
  bool _showSettings = false;

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<Img2ImgNotifier>();
    final t = context.t;
    final l = context.l;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: VisionMetrics.space16,
        vertical: VisionMetrics.space8,
      ),
      decoration: BoxDecoration(
        color: t.surfaceHigh,
        border: Border(top: BorderSide(color: t.borderSubtle)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              key: const ValueKey<String>('mask-toolbar-primary-scroll'),
              scrollDirection: Axis.horizontal,
              // Wide: fill the row so the Spacer pushes the display and mask
              // file actions to the right edge. Narrow: scroll instead.
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: IntrinsicWidth(
                  child: Row(
                    children: [
                      // Undo
                      IconButton(
                        icon: Icon(
                          Icons.undo,
                          size: VisionMetrics.iconMedium,
                          color: t.textTertiary,
                        ),
                        onPressed: notifier.hasMask
                            ? notifier.undoLastStroke
                            : null,
                        tooltip: l.img2imgMaskUndoStroke,
                      ),
                      // Clear
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          size: VisionMetrics.iconMedium,
                          color: t.textTertiary,
                        ),
                        onPressed: notifier.hasMask
                            ? () => _confirmClearMask(context, notifier)
                            : null,
                        tooltip: l.img2imgMaskClearTooltip,
                      ),

                      const SizedBox(width: VisionMetrics.space8),

                      // Brush shape toggle (round/square)
                      IconButton(
                        icon: Icon(
                          notifier.maskBrushRound
                              ? Icons.circle_outlined
                              : Icons.square_outlined,
                          size: VisionMetrics.iconMedium,
                          color: t.textTertiary,
                        ),
                        onPressed: () => notifier.setMaskBrushRound(
                          !notifier.maskBrushRound,
                        ),
                        tooltip: notifier.maskBrushRound
                            ? l.img2imgBrushRound
                            : l.img2imgBrushSquare,
                      ),

                      const SizedBox(width: VisionMetrics.space8),

                      // Brush size slider
                      Text(
                        l.img2imgBrushSize,
                        style: TextStyle(
                          color: t.textDisabled,
                          fontSize: t.fontSize(8),
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(width: VisionMetrics.space8),
                      SizedBox(
                        width: 120,
                        child: VisionSlider.subtle(
                          value: notifier.brushRadius,
                          min: 0.005,
                          max: 0.15,
                          onChanged: notifier.setBrushRadius,
                          t: t,
                        ),
                      ),

                      const SizedBox(width: VisionMetrics.space8),
                      const Spacer(),

                      // Mask display settings toggle. Not Icons.tune: that
                      // is the tool's own settings entry.
                      IconButton(
                        icon: Icon(
                          Icons.opacity,
                          size: VisionMetrics.iconMedium,
                          color: _showSettings ? t.accentEdit : t.textTertiary,
                        ),
                        onPressed: () =>
                            setState(() => _showSettings = !_showSettings),
                        tooltip: l.img2imgMaskDisplay,
                      ),

                      // Save mask
                      IconButton(
                        icon: Icon(
                          Icons.save_outlined,
                          size: VisionMetrics.iconMedium,
                          color: t.textTertiary,
                        ),
                        onPressed: notifier.hasMask
                            ? () => _saveMask(context, notifier)
                            : null,
                        tooltip: l.img2imgMaskSave,
                      ),
                      // Load mask
                      IconButton(
                        icon: Icon(
                          Icons.folder_open,
                          size: VisionMetrics.iconMedium,
                          color: t.textTertiary,
                        ),
                        onPressed: () => _loadMask(context, notifier),
                        tooltip: l.img2imgMaskLoad,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Mask display settings row
          if (_showSettings) ...[
            const SizedBox(height: VisionMetrics.space8),
            SingleChildScrollView(
              key: const ValueKey<String>('mask-toolbar-settings-scroll'),
              scrollDirection: Axis.horizontal,
              child: _buildMaskSettingsRow(context, t, notifier),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMaskSettingsRow(
    BuildContext context,
    VisionTokens t,
    Img2ImgNotifier notifier,
  ) {
    final l = context.l;
    final cell = context.hitSize;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Color label + swatches
        Text(
          l.img2imgMaskColor,
          style: TextStyle(
            color: t.textDisabled,
            fontSize: t.fontSize(8),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(width: VisionMetrics.space8),
        ...List.generate(_maskColorPresets.length, (i) {
          final color = _maskColorPresets[i];
          final isSelected = notifier.maskColor == color;
          return InkWell(
            onTap: () => notifier.setMaskColor(color),
            borderRadius: BorderRadius.circular(VisionMetrics.radius4),
            child: SizedBox(
              width: cell,
              height: cell,
              child: Center(
                child: Container(
                  width: VisionMetrics.iconMedium,
                  height: VisionMetrics.iconMedium,
                  decoration: BoxDecoration(
                    color: Color(color),
                    borderRadius: BorderRadius.circular(VisionMetrics.radius2),
                    border: Border.all(
                      color: isSelected ? t.textPrimary : t.borderMedium,
                      width: isSelected ? 2 : VisionMetrics.borderWidth,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),

        const SizedBox(width: VisionMetrics.space12),

        // Opacity slider
        Text(
          l.img2imgMaskOpacity,
          style: TextStyle(
            color: t.textDisabled,
            fontSize: t.fontSize(8),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(width: VisionMetrics.space4),
        SizedBox(
          width: 80,
          child: VisionSlider.subtle(
            value: notifier.maskOpacity,
            min: 0.05,
            onChanged: notifier.setMaskOpacity,
            t: t,
            thumbRadius: 5,
            overlayRadius: 10,
          ),
        ),

        const SizedBox(width: VisionMetrics.space12),

        // Pattern dropdown
        _MiniDropdown<MaskPattern>(
          value: notifier.maskPattern,
          items: {
            MaskPattern.solid: l.img2imgMaskPatternSolid,
            MaskPattern.stripe: l.img2imgMaskPatternStripe,
            MaskPattern.crosshatch: l.img2imgMaskPatternCross,
          },
          onChanged: notifier.setMaskPattern,
          t: t,
        ),

        const SizedBox(width: VisionMetrics.space8),

        // Border toggle
        AppPill(
          icon: Icons.border_style,
          text: l.img2imgMaskBorder,
          tone: notifier.maskShowBorder ? AppTone.info : AppTone.neutral,
          tooltip: l.img2imgMaskBorderTooltip,
          onTap: () => notifier.setMaskShowBorder(!notifier.maskShowBorder),
        ),
      ],
    );
  }

  /// Clearing drops every stroke and cannot be undone, so ask first.
  Future<void> _confirmClearMask(
    BuildContext context,
    Img2ImgNotifier notifier,
  ) async {
    final l = context.l;
    final confirmed = await showConfirmDialog(
      context,
      title: l.img2imgClearMaskTitle,
      message: l.img2imgClearMaskMessage,
      confirmLabel: l.img2imgClearMaskConfirm,
      cancelLabel: l.commonCancel,
    );
    if (confirmed == true) notifier.clearMask();
  }

  Future<void> _saveMask(BuildContext context, Img2ImgNotifier notifier) async {
    final session = notifier.session;
    if (session == null) return;

    final maskBytes = await MaskEncoder.encodeMask(
      strokes: session.maskStrokes,
      width: session.sourceWidth,
      height: session.sourceHeight,
      prebakedMaskBytes: session.prebakedMaskBytes,
    );
    if (maskBytes == null) return;
    if (!context.mounted) return;

    // Route through the platform's save/share path the same way every other
    // export in the app does. FilePicker.saveFile silently returns null on
    // Android and is unsupported on web, so without this branch the button
    // no-ops on the most common platforms.
    if (kIsWeb) {
      downloadBytes(maskBytes, 'mask.png');
      showAppSnackBar(context, context.l.img2imgMaskSaved);
      return;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      await Share.shareXFiles([
        XFile.fromData(maskBytes, mimeType: 'image/png', name: 'mask.png'),
      ]);
      return;
    }

    // Desktop: save-file dialog.
    final result = await FilePicker.platform.saveFile(
      dialogTitle: context.l.img2imgMaskSave,
      fileName: 'mask.png',
      type: FileType.custom,
      allowedExtensions: ['png'],
    );
    if (result == null) return;

    await File(result).writeAsBytes(maskBytes);
    if (context.mounted) showAppSnackBar(context, context.l.img2imgMaskSaved);
  }

  Future<void> _loadMask(BuildContext context, Img2ImgNotifier notifier) async {
    final result = await pickCustomFiles(
      allowedExtensions: ['png', 'jpg', 'jpeg'],
    );
    if (result == null || result.files.isEmpty) return;

    final bytes = await readPickedFileBytes(result.files.first);
    if (bytes == null || !context.mounted) return;
    notifier.loadMask(bytes);
  }
}

/// Compact dropdown for mask settings.
class _MiniDropdown<T> extends StatelessWidget {
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  final VisionTokens t;

  const _MiniDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: VisionMetrics.space8),
      height: context.hitSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VisionMetrics.radius4),
        border: Border.all(color: t.borderSubtle),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          dropdownColor: t.surfaceHigh,
          icon: Icon(
            Icons.arrow_drop_down,
            size: VisionMetrics.iconSmall,
            color: t.textMinimal,
          ),
          items: items.entries.map((e) {
            return DropdownMenuItem<T>(
              value: e.key,
              child: Text(
                e.value,
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: t.fontSize(8),
                ),
              ),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
