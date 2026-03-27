import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../../../../core/utils/file_picker_helper.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/theme/vision_tokens.dart';
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: t.surfaceHigh,
        border: Border(top: BorderSide(color: t.borderSubtle)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Undo
              IconButton(
                icon: Icon(Icons.undo, size: 16, color: t.textTertiary),
                onPressed: notifier.hasMask ? notifier.undoLastStroke : null,
                tooltip: 'Undo stroke',
                splashRadius: 16,
              ),
              // Clear
              IconButton(
                icon: Icon(Icons.delete_outline, size: 16, color: t.textTertiary),
                onPressed: notifier.hasMask ? notifier.clearMask : null,
                tooltip: 'Clear mask',
                splashRadius: 16,
              ),

              const SizedBox(width: 8),

              // Brush shape toggle (round/square)
              IconButton(
                icon: Icon(
                  notifier.maskBrushRound ? Icons.circle_outlined : Icons.square_outlined,
                  size: 16,
                  color: t.textTertiary,
                ),
                onPressed: () => notifier.setMaskBrushRound(!notifier.maskBrushRound),
                tooltip: notifier.maskBrushRound ? 'Round brush' : 'Square brush',
                splashRadius: 16,
              ),

              const SizedBox(width: 8),

              // Brush size slider
              Text(
                'SIZE',
                style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(8), letterSpacing: 1),
              ),
              const SizedBox(width: 8),
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

              const Spacer(),

              // Mask display settings toggle
              IconButton(
                icon: Icon(
                  Icons.tune,
                  size: 16,
                  color: _showSettings ? t.accentEdit : t.textTertiary,
                ),
                onPressed: () => setState(() => _showSettings = !_showSettings),
                tooltip: 'Mask display settings',
                splashRadius: 16,
              ),

              // Save mask
              IconButton(
                icon: Icon(Icons.save_outlined, size: 16, color: t.textTertiary),
                onPressed: notifier.hasMask ? () => _saveMask(context, notifier) : null,
                tooltip: 'Save mask',
                splashRadius: 16,
              ),
              // Load mask
              IconButton(
                icon: Icon(Icons.folder_open, size: 16, color: t.textTertiary),
                onPressed: () => _loadMask(context, notifier),
                tooltip: 'Load mask',
                splashRadius: 16,
              ),
            ],
          ),
          // Mask display settings row
          if (_showSettings) ...[
            const SizedBox(height: 6),
            _buildMaskSettingsRow(t, notifier),
          ],
        ],
      ),
    );
  }

  Widget _buildMaskSettingsRow(VisionTokens t, Img2ImgNotifier notifier) {
    return Row(
      children: [
        // Color label + swatches
        Text(
          'COLOR',
          style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(7), letterSpacing: 1),
        ),
        const SizedBox(width: 6),
        ...List.generate(_maskColorPresets.length, (i) {
          final color = _maskColorPresets[i];
          final isSelected = notifier.maskColor == color;
          return Padding(
            padding: const EdgeInsets.only(right: 3),
            child: GestureDetector(
              onTap: () => notifier.setMaskColor(color),
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Color(color),
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: isSelected ? t.textPrimary : t.borderSubtle,
                    width: isSelected ? 2 : 0.5,
                  ),
                ),
              ),
            ),
          );
        }),

        const SizedBox(width: 12),

        // Opacity slider
        Text(
          'OPACITY',
          style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(7), letterSpacing: 1),
        ),
        const SizedBox(width: 4),
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

        const SizedBox(width: 12),

        // Pattern dropdown
        _MiniDropdown<MaskPattern>(
          value: notifier.maskPattern,
          items: const {
            MaskPattern.solid: 'Solid',
            MaskPattern.stripe: 'Stripe',
            MaskPattern.crosshatch: 'Cross',
          },
          onChanged: notifier.setMaskPattern,
          t: t,
        ),

        const SizedBox(width: 8),

        // Border toggle
        Tooltip(
          message: 'Show mask border',
          child: GestureDetector(
            onTap: () => notifier.setMaskShowBorder(!notifier.maskShowBorder),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: notifier.maskShowBorder
                    ? t.accentEdit.withValues(alpha: 0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: notifier.maskShowBorder ? t.accentEdit : t.borderSubtle,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.border_style,
                    size: 12,
                    color: notifier.maskShowBorder ? t.accentEdit : t.textTertiary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'BORDER',
                    style: TextStyle(
                      color: notifier.maskShowBorder ? t.accentEdit : t.textTertiary,
                      fontSize: t.fontSize(7),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
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

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save mask',
      fileName: 'mask.png',
      type: FileType.custom,
      allowedExtensions: ['png'],
    );
    if (result == null) return;

    await File(result).writeAsBytes(maskBytes);
  }

  Future<void> _loadMask(BuildContext context, Img2ImgNotifier notifier) async {
    final result = await pickCustomFiles(
      allowedExtensions: ['png', 'jpg', 'jpeg'],
    );
    if (result == null || result.files.isEmpty || result.files.first.path == null) return;

    final bytes = await File(result.files.first.path!).readAsBytes();
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
      padding: const EdgeInsets.symmetric(horizontal: 6),
      height: 24,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: t.borderSubtle),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          dropdownColor: t.surfaceHigh,
          icon: Icon(Icons.arrow_drop_down, size: 14, color: t.textMinimal),
          items: items.entries.map((e) {
            return DropdownMenuItem<T>(
              value: e.key,
              child: Text(
                e.value,
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: t.fontSize(7),
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
