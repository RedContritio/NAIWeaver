import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/services/preferences_service.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/utils/file_picker_helper.dart';
import '../../../core/utils/image_utils.dart';
import '../../gallery/providers/gallery_notifier.dart';
import '../../generation/providers/generation_notifier.dart';

/// Where a tool's source image came from.
enum ToolSourceOrigin { currentGeneration, device, gallery }

/// Which prompt text a tool picks up together with its source image. The
/// tools historically differ here, so each one states its rule explicitly.
enum ToolSourcePromptImport {
  /// Image only (Director Tools).
  none,

  /// The main editor's positive prompt, and only when reusing the current
  /// generation (Enhance). The tool fills the UC itself.
  mainPromptForCurrentGeneration,

  /// Gated by the "import prompt" preference (Img2Img): the main prompt and
  /// UC for the current generation, or the clean prompt and UC embedded in
  /// the image's NAI metadata for device and gallery picks.
  preferenceGated,
}

class ToolSourceSelection {
  const ToolSourceSelection({
    required this.bytes,
    required this.origin,
    this.filePath,
    this.prompt,
    this.negativePrompt,
  });

  final Uint8List bytes;
  final ToolSourceOrigin origin;

  /// Gallery file backing the image; null for other origins.
  final String? filePath;
  final String? prompt;
  final String? negativePrompt;
}

/// Prompt and UC from an image's NAI `Comment` chunk. Prefers the clean
/// `original_prompt`: the `prompt` field has the active style's prefix and
/// suffix baked in, and img2img re-applies the current style at generation
/// time, so loading the styled prompt would double it. Older images without
/// `original_prompt` fall back to `prompt`.
({String? prompt, String? negativePrompt}) promptFromImageMetadata(
  Uint8List bytes,
) {
  final comment = extractMetadata(bytes)?['Comment'];
  final json = comment == null ? null : parseCommentJson(comment);
  if (json == null) return (prompt: null, negativePrompt: null);
  return (
    prompt: (json['original_prompt'] as String?) ?? (json['prompt'] as String?),
    negativePrompt: json['uc'] as String?,
  );
}

/// Source picker shared by Img2Img, Enhance and Director Tools: reuse the
/// current generation, upload from the device, or pick from the gallery.
class ToolSourcePicker extends StatelessWidget {
  const ToolSourcePicker({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.useCurrentLabel,
    required this.useCurrentDescription,
    required this.promptImport,
    required this.onSelected,
    this.extraOptions = const [],
  });

  final IconData icon;
  final String title;
  final String description;
  final String useCurrentLabel;
  final String useCurrentDescription;
  final ToolSourcePromptImport promptImport;

  /// Only called while the picker is still mounted, so a tool that was
  /// switched away during the file dialog never sees a late selection.
  final ValueChanged<ToolSourceSelection> onSelected;

  /// Tool-specific options shown after "upload from device".
  final List<ToolSourceOption> extraOptions;

  @override
  Widget build(BuildContext context) {
    final genNotifier = context.watch<GenerationNotifier>();
    final galleryNotifier = context.watch<GalleryNotifier>();
    final currentImage = genNotifier.state.generatedImage;
    final t = context.t;
    final l = context.l;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: t.textMinimal),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: t.textDisabled,
                fontSize: t.fontSize(12),
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(10)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            if (currentImage != null) ...[
              ToolSourceOption(
                icon: Icons.flash_on,
                label: useCurrentLabel,
                description: useCurrentDescription,
                accentColor: t.accent,
                onTap: () => _useCurrentGeneration(context, currentImage),
              ),
              const SizedBox(height: 12),
            ],

            ToolSourceOption(
              icon: Icons.photo_library_outlined,
              label: l.img2imgUploadFromDevice,
              description: l.img2imgUploadFromDeviceDesc,
              accentColor: t.accentEdit,
              onTap: () => _pickFromDevice(context),
            ),
            const SizedBox(height: 12),

            for (final option in extraOptions) ...[
              option,
              const SizedBox(height: 12),
            ],

            if (!galleryNotifier.demoMode &&
                galleryNotifier.items.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    l.directorToolsFromGallery,
                    style: TextStyle(
                      color: t.textDisabled,
                      fontSize: t.fontSize(9),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 280,
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: galleryNotifier.items.length,
                  itemBuilder: (_, index) {
                    final file = galleryNotifier.items[index].file;
                    return _GalleryThumbnail(
                      file: file,
                      onTap: () => _pickFromGallery(context, file),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _importsPrompt(BuildContext context) => switch (promptImport) {
    ToolSourcePromptImport.none => false,
    ToolSourcePromptImport.mainPromptForCurrentGeneration => true,
    ToolSourcePromptImport.preferenceGated =>
      context.read<PreferencesService>().img2imgImportPrompt,
  };

  void _useCurrentGeneration(BuildContext context, Uint8List bytes) {
    final gen = context.read<GenerationNotifier>();
    final importPrompt = _importsPrompt(context);
    final importUc = promptImport == ToolSourcePromptImport.preferenceGated;
    onSelected(
      ToolSourceSelection(
        bytes: bytes,
        origin: ToolSourceOrigin.currentGeneration,
        prompt: importPrompt ? gen.promptController.text : null,
        negativePrompt: importPrompt && importUc
            ? gen.negativePromptController.text
            : null,
      ),
    );
  }

  Future<void> _pickFromDevice(BuildContext context) async {
    final result = await pickImageFiles();
    if (result == null || result.files.isEmpty) return;
    final bytes = await readPickedFileBytes(result.files.single);
    if (bytes == null || !context.mounted) return;
    _selectFile(context, bytes, ToolSourceOrigin.device);
  }

  Future<void> _pickFromGallery(BuildContext context, File file) async {
    final bytes = await file.readAsBytes();
    if (!context.mounted) return;
    _selectFile(context, bytes, ToolSourceOrigin.gallery, filePath: file.path);
  }

  void _selectFile(
    BuildContext context,
    Uint8List bytes,
    ToolSourceOrigin origin, {
    String? filePath,
  }) {
    final fromMetadata =
        promptImport == ToolSourcePromptImport.preferenceGated &&
        _importsPrompt(context);
    final metadata = fromMetadata ? promptFromImageMetadata(bytes) : null;
    onSelected(
      ToolSourceSelection(
        bytes: bytes,
        origin: origin,
        filePath: filePath,
        prompt: metadata?.prompt,
        negativePrompt: metadata?.negativePrompt,
      ),
    );
  }
}

class ToolSourceOption extends StatelessWidget {
  const ToolSourceOption({
    super.key,
    required this.icon,
    required this.label,
    required this.description,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: accentColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: accentColor),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: accentColor,
                      fontSize: t.fontSize(10),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      color: t.textDisabled,
                      fontSize: t.fontSize(9),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 12,
              color: accentColor.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryThumbnail extends StatelessWidget {
  const _GalleryThumbnail({required this.file, required this.onTap});

  final File file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: t.surfaceHigh,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: t.borderSubtle),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Image.file(
            file,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}
