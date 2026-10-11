import 'package:flutter/material.dart';

import '../../theme/theme_extensions.dart';
import '../../theme/vision_metrics.dart';

/// The translucent bordered square used for actions floating over images.
/// Its visual size follows the window ([ThemeTokensExtension.touchSize]).
class OverlayActionFrame extends StatelessWidget {
  const OverlayActionFrame({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final size = context.touchSize;
    return SizedBox(
      width: size,
      height: size,
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
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Icon color when enabled; defaults to the primary text color.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final enabled = onPressed != null;
    final hit = context.hitSize;
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
