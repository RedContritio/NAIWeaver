import 'package:flutter/material.dart';

import '../../theme/theme_extensions.dart';
import '../../utils/responsive.dart';
import '../../theme/vision_metrics.dart';

/// The translucent bordered square used for actions floating over images.
/// Its visual size follows the window ([ThemeTokensExtension.touchSize]).
class OverlayActionFrame extends StatelessWidget {
  const OverlayActionFrame({
    super.key,
    required this.child,
    this.enabled = true,
    this.wide = false,
  });

  final Widget child;
  final bool enabled;

  /// Lets the frame grow wider than a square to fit an icon and a label.
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final size = context.touchSize;
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: size,
        maxWidth: wide ? double.infinity : size,
        minHeight: size,
        maxHeight: size,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.background.withValues(
            alpha: enabled
                ? VisionMetrics.opacityOverlay
                : VisionMetrics.opacityOverlay * VisionMetrics.opacityDisabled,
          ),
          border: Border.all(color: t.borderSubtle),
          borderRadius: BorderRadius.circular(VisionMetrics.radius4),
        ),
        child: child,
      ),
    );
  }
}

/// A tappable icon on an [OverlayActionFrame]. [tooltip] is required for
/// accessibility; a null [onPressed] renders the disabled appearance.
class OverlayActionButton extends StatelessWidget {
  const OverlayActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
    this.label,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Icon color when enabled; defaults to the primary text color.
  final Color? color;

  /// Shown next to the icon from the expanded window size class (840 px) up;
  /// narrower windows show the icon alone. [tooltip] stays either way.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final enabled = onPressed != null;
    final hit = context.hitSize;
    final text = label;
    final showLabel =
        text != null &&
        text.isNotEmpty &&
        windowSizeClassOf(context).atLeast(WindowSizeClass.expanded);
    if (showLabel) {
      final foreground = enabled ? (color ?? t.textPrimary) : t.textDisabled;
      return SizedBox(
        height: hit,
        child: Center(
          child: OverlayActionFrame(
            enabled: enabled,
            wide: true,
            child: Tooltip(
              message: tooltip,
              child: InkWell(
                onTap: onPressed,
                borderRadius: BorderRadius.circular(VisionMetrics.radius4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: VisionMetrics.space8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: VisionMetrics.space4,
                    children: [
                      Icon(
                        icon,
                        size: VisionMetrics.iconMedium,
                        color: foreground,
                      ),
                      Flexible(
                        child: Text(
                          text.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: foreground,
                            fontSize: t.fontSize(10),
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: hit,
      height: hit,
      child: Center(
        child: OverlayActionFrame(
          enabled: enabled,
          child: IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tight(Size.square(context.touchSize)),
            iconSize: VisionMetrics.iconMedium,
            color: color ?? t.textPrimary,
            disabledColor: t.textDisabled,
            icon: Icon(icon),
          ),
        ),
      ),
    );
  }
}
