import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_tokens.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/utils/file_picker_helper.dart';
import '../../../core/services/novel_ai_service.dart';
import '../../director_ref/models/director_reference.dart';
import '../../director_ref/providers/director_ref_notifier.dart';
import '../../director_ref/widgets/director_ref_editor_sheet.dart';
import '../../vibe_transfer/providers/vibe_transfer_notifier.dart';
import '../../vibe_transfer/widgets/vibe_transfer_editor_sheet.dart';

/// Vertical rail of REF/VIBE thumbnails for sidebar mode.
/// Positioned on the right edge of the image viewer area.
class SidebarRefVibeRail extends StatelessWidget {
  final bool showRef;
  final bool showVibe;

  const SidebarRefVibeRail({
    super.key,
    required this.showRef,
    required this.showVibe,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      width: 48,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: t.background.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showRef) _RefSection(t: t),
          if (showRef && showVibe) SizedBox(height: 8, child: Divider(color: t.borderSubtle, indent: 8, endIndent: 8)),
          if (showVibe) _VibeSection(t: t),
        ],
      ),
    );
  }
}

class _RefSection extends StatelessWidget {
  final VisionTokens t;
  const _RefSection({required this.t});

  Future<void> _pickAndAdd(BuildContext context) async {
    final result = await pickImageFiles();
    if (result != null && result.files.single.path != null) {
      final bytes = await File(result.files.single.path!).readAsBytes();
      if (context.mounted) {
        context.read<DirectorRefNotifier>().addReference(bytes);
      }
    }
  }

  void _openEditor(BuildContext context, DirectorRefNotifier notifier, DirectorReference ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DirectorRefEditorSheet(
        reference: ref,
        onTypeChanged: (v) => notifier.updateType(ref.id, v),
        onStrengthChanged: (v) => notifier.updateStrength(ref.id, v),
        onFidelityChanged: (v) => notifier.updateFidelity(ref.id, v),
        onRemove: () => notifier.removeReference(ref.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DirectorRefNotifier>(
      builder: (context, notifier, _) {
        final refs = notifier.references;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...refs.map((ref) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _RailChip(
                imageBytes: ref.originalImageBytes,
                borderColor: _refBorderColor(ref.type, t),
                icon: _refIcon(ref.type),
                onTap: () => _openEditor(context, notifier, ref),
                onLongPress: () => notifier.removeReference(ref.id),
              ),
            )),
            _RailAddButton(
              label: 'REF',
              color: t.accentRefCharacter,
              isProcessing: notifier.isProcessing,
              onTap: () => _pickAndAdd(context),
            ),
          ],
        );
      },
    );
  }

  Color _refBorderColor(DirectorReferenceType type, VisionTokens t) {
    switch (type) {
      case DirectorReferenceType.character:
        return t.accentRefCharacter;
      case DirectorReferenceType.style:
        return t.accentRefStyle;
      case DirectorReferenceType.characterAndStyle:
        return t.accentRefCharStyle;
    }
  }

  IconData _refIcon(DirectorReferenceType type) {
    switch (type) {
      case DirectorReferenceType.character:
        return Icons.person;
      case DirectorReferenceType.style:
        return Icons.palette;
      case DirectorReferenceType.characterAndStyle:
        return Icons.auto_awesome;
    }
  }
}

class _VibeSection extends StatelessWidget {
  final VisionTokens t;
  const _VibeSection({required this.t});

  Future<void> _pickAndAdd(BuildContext context) async {
    final result = await pickImageFiles(allowMultiple: true);
    if (result != null && context.mounted) {
      final notifier = context.read<VibeTransferNotifier>();
      for (final file in result.files) {
        if (file.path != null) {
          final bytes = await File(file.path!).readAsBytes();
          if (!context.mounted) return;
          try {
            await notifier.addVibe(bytes);
          } on UnauthorizedException {
            if (context.mounted) {
              showErrorSnackBar(context, 'API key missing or invalid');
            }
            return;
          } catch (e) {
            if (context.mounted) {
              showErrorSnackBar(context, 'Failed to encode vibe image');
            }
            return;
          }
        }
      }
    }
  }

  void _openEditor(BuildContext context, VibeTransferNotifier notifier, vibe) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VibeTransferEditorSheet(
        vibe: vibe,
        onStrengthChanged: (v) => notifier.updateStrength(vibe.id, v),
        onInfoExtractedChanged: (v) => notifier.updateInfoExtracted(vibe.id, v),
        onRemove: () => notifier.removeVibe(vibe.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VibeTransferNotifier>(
      builder: (context, notifier, _) {
        final vibes = notifier.vibes;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...vibes.map((vibe) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _RailChip(
                imageBytes: vibe.originalImageBytes,
                borderColor: t.accent,
                onTap: () => _openEditor(context, notifier, vibe),
                onLongPress: () => notifier.removeVibe(vibe.id),
              ),
            )),
            _RailAddButton(
              label: 'VIBE',
              color: t.accent,
              isProcessing: notifier.isProcessing,
              onTap: () => _pickAndAdd(context),
            ),
          ],
        );
      },
    );
  }
}

/// Small image thumbnail for the vertical rail.
class _RailChip extends StatelessWidget {
  final dynamic imageBytes;
  final Color borderColor;
  final IconData? icon;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _RailChip({
    required this.imageBytes,
    required this.borderColor,
    this.icon,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: borderColor, width: 1.5),
          image: DecorationImage(
            image: MemoryImage(imageBytes),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          ),
        ),
        child: icon != null
            ? Align(
                alignment: Alignment.bottomRight,
                child: Container(
                  padding: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    color: t.background.withValues(alpha: 0.7),
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(3)),
                  ),
                  child: Icon(icon, size: 10, color: borderColor),
                ),
              )
            : null,
      ),
    );
  }
}

/// Small labeled add button for the vertical rail.
class _RailAddButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool isProcessing;
  final VoidCallback onTap;

  const _RailAddButton({
    required this.label,
    required this.color,
    required this.isProcessing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return GestureDetector(
      onTap: isProcessing ? null : onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isProcessing)
              SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: color))
            else
              Icon(Icons.add, size: 14, color: color),
            Text(
              label,
              style: TextStyle(
                fontSize: t.fontSize(6),
                color: color,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
