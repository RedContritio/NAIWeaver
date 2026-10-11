import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';

/// Img2Img workspace header.
///
/// Back and Generate stay pinned at the edges. The tool buttons between them
/// scroll horizontally: how many there are depends on the installed local
/// models and on whether a result exists, so no fixed row fits every
/// combination on a 360dp phone, and the primary action must never be the
/// one that gets clipped. A null callback hides its button.
class Img2ImgHeader extends StatelessWidget {
  const Img2ImgHeader({
    super.key,
    required this.mobile,
    required this.onBack,
    required this.isLoading,
    required this.onGenerate,
    this.onOpenSettings,
    this.onOpenCanvas,
    this.mlProcessing = false,
    this.onRemoveBackground,
    this.onUpscale,
    this.onSegment,
    this.showingResult = false,
    this.onToggleResult,
  });

  static const toolsScrollKey = ValueKey<String>('img2img-header-tools');

  final bool mobile;
  final VoidCallback onBack;
  final bool isLoading;
  final VoidCallback onGenerate;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenCanvas;
  final bool mlProcessing;
  final VoidCallback? onRemoveBackground;
  final VoidCallback? onUpscale;
  final VoidCallback? onSegment;
  final bool showingResult;
  final VoidCallback? onToggleResult;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: t.surfaceHigh,
        border: Border(bottom: BorderSide(color: t.borderSubtle)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, size: 16, color: t.textDisabled),
            onPressed: onBack,
            tooltip: l.img2imgBackToPicker,
          ),
          Expanded(
            // Reversed so the tools hug Generate when they fit and the ones
            // next to it stay visible when they do not.
            child: SingleChildScrollView(
              key: toolsScrollKey,
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: _buildTools(context),
              ),
            ),
          ),
          _buildGenerateButton(context),
        ],
      ),
    );
  }

  List<Widget> _buildTools(BuildContext context) {
    final t = context.t;
    final l = context.l;
    return [
      if (onOpenSettings != null)
        IconButton(
          onPressed: onOpenSettings,
          icon: const Icon(Icons.tune, size: 17),
          tooltip: l.img2imgSettings,
          style: IconButton.styleFrom(foregroundColor: t.accentEdit),
        ),

      if (onOpenCanvas != null) ...[
        SizedBox(
          height: 36,
          child: mobile
              ? IconButton(
                  onPressed: onOpenCanvas,
                  icon: const Icon(Icons.palette, size: 14),
                  tooltip: l.canvasEditInCanvas,
                  style: IconButton.styleFrom(foregroundColor: t.accentEdit),
                )
              : TextButton.icon(
                  onPressed: onOpenCanvas,
                  icon: const Icon(Icons.palette, size: 14),
                  label: Text(l.canvasEditInCanvas),
                  style: TextButton.styleFrom(
                    foregroundColor: t.accentEdit,
                    textStyle: TextStyle(
                      fontSize: t.fontSize(10),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 4),
      ],

      if (onRemoveBackground != null) ...[
        SizedBox(
          height: 36,
          child: mlProcessing
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : _mlButton(
                  context,
                  Icons.content_cut,
                  l.mlRemoveBg,
                  onRemoveBackground!,
                ),
        ),
        const SizedBox(width: 4),
      ],

      if (onUpscale != null) ...[
        SizedBox(
          height: 36,
          child: mlProcessing
              ? const SizedBox.shrink()
              : _mlButton(context, Icons.zoom_out_map, l.mlUpscale, onUpscale!),
        ),
        const SizedBox(width: 4),
      ],

      if (onSegment != null) ...[
        SizedBox(
          height: 36,
          child: mlProcessing
              ? const SizedBox.shrink()
              : _mlButton(context, Icons.auto_awesome, l.mlSegment, onSegment!),
        ),
        const SizedBox(width: 4),
      ],

      if (onToggleResult != null) ...[
        SizedBox(
          height: 36,
          child: IconButton(
            onPressed: onToggleResult,
            icon: const Icon(Icons.swap_horiz, size: 18),
            tooltip: showingResult ? l.img2imgCanvas : l.img2imgResult,
            style: IconButton.styleFrom(foregroundColor: t.textTertiary),
          ),
        ),
        const SizedBox(width: 4),
      ],
    ];
  }

  Widget _mlButton(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onPressed,
  ) {
    final t = context.t;
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: mobile ? const SizedBox.shrink() : Text(label.toUpperCase()),
      style: TextButton.styleFrom(
        foregroundColor: t.accent,
        textStyle: TextStyle(
          fontSize: t.fontSize(10),
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildGenerateButton(BuildContext context) {
    final t = context.t;
    final l = context.l;
    final icon = isLoading
        ? SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: t.background,
            ),
          )
        : const Icon(Icons.auto_awesome, size: 14);

    // Icon-only on mobile.
    if (mobile) {
      return SizedBox(
        height: 36,
        child: IconButton(
          onPressed: isLoading ? null : onGenerate,
          icon: icon,
          tooltip: isLoading ? l.img2imgGenerating : l.img2imgGenerate,
          style: IconButton.styleFrom(
            backgroundColor: t.accent,
            foregroundColor: t.background,
          ),
        ),
      );
    }
    return SizedBox(
      height: 36,
      child: ElevatedButton.icon(
        onPressed: isLoading ? null : onGenerate,
        icon: icon,
        label: Text(isLoading ? l.img2imgGenerating : l.img2imgGenerate),
        style: ElevatedButton.styleFrom(
          backgroundColor: t.accent,
          foregroundColor: t.background,
          textStyle: TextStyle(
            fontSize: t.fontSize(10),
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          elevation: 0,
        ),
      ),
    );
  }
}
