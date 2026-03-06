import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/widgets/vision_slider.dart';
import '../providers/img2img_notifier.dart';
import '../services/mask_encoder.dart';

class MaskToolbar extends StatelessWidget {
  const MaskToolbar({super.key});

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
      child: Row(
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

          const SizedBox(width: 16),

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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
    );
    if (result == null || result.files.isEmpty || result.files.first.path == null) return;

    final bytes = await File(result.files.first.path!).readAsBytes();
    notifier.loadMask(bytes);
  }
}
