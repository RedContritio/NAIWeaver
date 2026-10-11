import 'package:flutter/material.dart';

import '../../theme/theme_extensions.dart';
import '../../theme/vision_metrics.dart';
import 'app_tone.dart';

/// Unified badge / capsule: an optional icon and text on a tinted outline.
class AppPill extends StatelessWidget {
  const AppPill({
    super.key,
    this.icon,
    this.text,
    this.tone = AppTone.neutral,
    this.tooltip,
    this.onTap,
    this.dense = false,
  }) : assert(icon != null || text != null, 'AppPill needs an icon or text');

  final IconData? icon;
  final String? text;
  final AppTone tone;
  final String? tooltip;
  final VoidCallback? onTap;

  /// Smaller padding and type for use on dense cards.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final color = tone.color(t);
    final iconSize = dense
        ? VisionMetrics.iconSmall - 2
        : VisionMetrics.iconSmall;
    Widget pill = DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: VisionMetrics.opacityHover),
        border: Border.all(
          color: color.withValues(alpha: VisionMetrics.opacityScrim),
        ),
        borderRadius: BorderRadius.circular(VisionMetrics.radius4),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? VisionMetrics.space4 : VisionMetrics.space8,
          vertical: dense ? VisionMetrics.radius2 : VisionMetrics.space4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) Icon(icon, size: iconSize, color: color),
            if (icon != null && text != null)
              const SizedBox(width: VisionMetrics.space4),
            if (text != null)
              Flexible(
                child: Text(
                  text!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: t.fontSize(dense ? 8 : 9),
                    letterSpacing: 1,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (onTap != null) {
      pill = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VisionMetrics.radius4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: VisionMetrics.minHitTarget,
          ),
          child: Center(widthFactor: 1, child: pill),
        ),
      );
    }
    return tooltip == null ? pill : Tooltip(message: tooltip!, child: pill);
  }
}
