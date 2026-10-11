import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/widgets/custom_resolution_dialog.dart';
import '../../../generation/providers/generation_notifier.dart';
import '../../../generation/widgets/settings_panel.dart';
import '../../canvas/providers/canvas_notifier.dart';
import '../../canvas/widgets/canvas_editor.dart';
import '../../widgets/tool_source_picker.dart';
import '../providers/img2img_notifier.dart';

/// Picker screen shown when no source image is loaded.
/// Offers: use current generation, upload from device, blank canvas, or pick
/// from gallery. Prompt/UC import follows the "import prompt" preference.
class SourceImagePicker extends StatelessWidget {
  const SourceImagePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ToolSourcePicker(
      icon: Icons.image_search,
      title: 'SELECT SOURCE IMAGE',
      description:
          'Choose an image to use as the base for img2img or inpainting',
      useCurrentLabel: 'USE CURRENT GENERATION',
      useCurrentDescription: 'Use the last generated image as source',
      promptImport: ToolSourcePromptImport.preferenceGated,
      onSelected: (selection) =>
          context.read<Img2ImgNotifier>().loadSourceImage(
            selection.bytes,
            prompt: selection.prompt,
            negativePrompt: selection.negativePrompt,
            filePath: selection.filePath,
          ),
      extraOptions: [
        ToolSourceOption(
          icon: Icons.note_add,
          label: context.l.img2imgBlankCanvas,
          description: context.l.img2imgBlankCanvasDesc,
          accentColor: t.accentSuccess,
          onTap: () => _showBlankCanvasDialog(context),
        ),
      ],
    );
  }
}

void _showBlankCanvasDialog(BuildContext context) {
  final t = context.tRead;
  final l = context.l;
  final genNotifier = context.read<GenerationNotifier>();
  final resOptions = AdvancedSettingsPanel.resolutionOptions(context);

  // Default to current generation resolution
  final currentW = genNotifier.state.width.toInt();
  final currentH = genNotifier.state.height.toInt();
  final currentValue = '${currentW}x$currentH';
  String selectedValue = resOptions.any((o) => o.value == currentValue)
      ? currentValue
      : resOptions.first.value;
  // Track ad-hoc custom entry that isn't in the saved list
  ResolutionOption? adHocCustom;

  showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          // Build items, including ad-hoc custom if present
          final allOptions = [...resOptions, if (adHocCustom != null && !resOptions.any((o) => o.value == adHocCustom!.value)) adHocCustom!];

          return AlertDialog(
            backgroundColor: t.surfaceHigh,
            title: Text(
              l.img2imgBlankCanvasSize,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: t.fontSize(11),
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            content: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: t.borderSubtle,
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButton<String>(
                value: selectedValue,
                dropdownColor: t.surfaceHigh,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: t.fontSize(11),
                  letterSpacing: 1,
                ),
                onChanged: (val) async {
                  if (val == '__custom__') {
                    final result = await showCustomResolutionDialog(ctx);
                    if (result != null) {
                      setDialogState(() {
                        adHocCustom = result;
                        selectedValue = result.value;
                      });
                    }
                    return;
                  }
                  if (val != null) {
                    setDialogState(() => selectedValue = val);
                  }
                },
                items: [
                  ...allOptions.map((opt) => DropdownMenuItem<String>(
                        value: opt.value,
                        child: Text(opt.displayLabel,
                            style: TextStyle(fontSize: t.fontSize(10))),
                      )),
                  DropdownMenuItem<String>(
                    value: '__custom__',
                    child: Row(
                      children: [
                        Icon(Icons.add, size: 14, color: t.accentSuccess),
                        const SizedBox(width: 8),
                        Text(l.resCustomEntry.toUpperCase(),
                            style: TextStyle(fontSize: t.fontSize(10), color: t.accentSuccess)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  l.commonCancel.toUpperCase(),
                  style: TextStyle(
                      color: t.textDisabled, fontSize: t.fontSize(9)),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _createBlankCanvas(context, selectedValue);
                },
                child: Text(
                  l.commonConfirm.toUpperCase(),
                  style: TextStyle(
                      color: t.accentSuccess, fontSize: t.fontSize(9)),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

void _createBlankCanvas(BuildContext context, String resolution) {
  final parts = resolution.split('x');
  final w = int.parse(parts[0]);
  final h = int.parse(parts[1]);

  // Generate a white PNG in-memory
  final blankImage = img.Image(width: w, height: h, numChannels: 4);
  img.fill(blankImage, color: img.ColorRgba8(255, 255, 255, 255));
  final bytes = Uint8List.fromList(img.encodePng(blankImage));

  final img2imgNotifier = context.read<Img2ImgNotifier>();
  final canvasNotifier = context.read<CanvasNotifier>();

  img2imgNotifier.loadSourceImage(bytes);
  canvasNotifier.startSession(bytes, w, h);

  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const CanvasEditor()),
  );
}
