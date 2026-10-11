import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/theme/vision_metrics.dart';

/// Img2Img workspace header.
///
/// Back and Generate stay pinned at the edges. The tool buttons between them
/// scroll horizontally: how many there are depends on the installed local
/// models and on whether a result exists, so no fixed row fits every
/// combination on a 360dp phone, and the primary action must never be the
/// one that gets clipped. A null callback hides its button.
///
/// Settings are not here: like the other tool workspaces, Img2Img opens them
/// from the bottom dock (touch-sized windows) or shows them in a side panel
/// (see `ToolSettingsLayout`).
class Img2ImgHeader extends StatelessWidget {
  const Img2ImgHeader({
    super.key,
    required this.compact,
    required this.onBack,
    required this.isLoading,
    required this.onGenerate,
    this.onOpenCanvas,
    this.mlProcessing = false,
    this.onRemoveBackground,
    this.onUpscale,
    this.onSegment,
    this.showingResult = false,
    this.onToggleResult,
  });

  static const toolsScrollKey = ValueKey<String>('img2img-header-tools');

  /// Icon-only buttons (compact windows).
  final bool compact;
  final VoidCallback onBack;
  final bool isLoading;
  final VoidCallback onGenerate;
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
    final height = context.hitSize;
    const gap = SizedBox(width: VisionMetrics.space4);
    return [
      if (onOpenCanvas != null) ...[
        SizedBox(
          height: height,
          child: compact
              ? IconButton(
                  onPressed: onOpenCanvas,
                  icon: const Icon(
                    Icons.palette,
                    size: VisionMetrics.iconSmall,
                  ),
                  tooltip: l.canvasEditInCanvas,
                  style: IconButton.styleFrom(foregroundColor: t.accentEdit),
                )
              : TextButton.icon(
                  onPressed: onOpenCanvas,
                  icon: const Icon(
                    Icons.palette,
                    size: VisionMetrics.iconSmall,
                  ),
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
        gap,
      ],

      if (onRemoveBackground != null) ...[
        SizedBox(
          height: height,
          child: mlProcessing
              ? const Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: VisionMetrics.space8,
                  ),
                  child: Center(
                    child: SizedBox(
                      width: VisionMetrics.iconSmall,
                      height: VisionMetrics.iconSmall,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : _mlButton(
                  context,
                  Icons.content_cut,
                  l.mlRemoveBg,
                  onRemoveBackground!,
                ),
        ),
        gap,
      ],

      if (onUpscale != null) ...[
        SizedBox(
          height: height,
          child: mlProcessing
              ? const SizedBox.shrink()
              : _mlButton(context, Icons.zoom_out_map, l.mlUpscale, onUpscale!),
        ),
        gap,
      ],

      if (onSegment != null) ...[
        SizedBox(
          height: height,
          child: mlProcessing
              ? const SizedBox.shrink()
              : _mlButton(context, Icons.auto_awesome, l.mlSegment, onSegment!),
        ),
        gap,
      ],

      if (onToggleResult != null) ...[
        SizedBox(
          height: height,
          child: IconButton(
            onPressed: onToggleResult,
            icon: const Icon(Icons.swap_horiz, size: VisionMetrics.iconMedium),
            tooltip: showingResult ? l.img2imgCanvas : l.img2imgResult,
            style: IconButton.styleFrom(foregroundColor: t.textTertiary),
          ),
        ),
        gap,
      ],
    ];
  }

  /// A local-model action: icon plus label, icon-only (with a tooltip) when
  /// compact.
  Widget _mlButton(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onPressed,
  ) {
    final t = context.t;
    if (compact) {
      return IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: VisionMetrics.iconSmall),
        tooltip: label,
        style: IconButton.styleFrom(foregroundColor: t.accent),
      );
    }
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: VisionMetrics.iconSmall),
      label: Text(label.toUpperCase()),
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
            width: VisionMetrics.iconSmall,
            height: VisionMetrics.iconSmall,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: t.background,
            ),
          )
        : const Icon(Icons.auto_awesome, size: VisionMetrics.iconSmall);
    final label = isLoading ? l.img2imgGenerating : l.img2imgGenerate;

    // Icon-only on compact windows.
    if (compact) {
      return SizedBox(
        height: context.hitSize,
        child: IconButton(
          onPressed: isLoading ? null : onGenerate,
          icon: icon,
          tooltip: label,
          style: IconButton.styleFrom(
            backgroundColor: t.accent,
            foregroundColor: t.background,
          ),
        ),
      );
    }
    return SizedBox(
      height: context.hitSize,
      child: ElevatedButton.icon(
        onPressed: isLoading ? null : onGenerate,
        icon: icon,
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: t.accent,
          foregroundColor: t.background,
          textStyle: TextStyle(
            fontSize: t.fontSize(10),
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: VisionMetrics.space16 + VisionMetrics.space4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(VisionMetrics.radius4),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}
