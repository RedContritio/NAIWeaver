import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/theme_extensions.dart';
import '../../theme/vision_metrics.dart';
import 'app_tone.dart';

/// How a panel is separated from its surroundings.
enum AppPanelVariant {
  /// Base background with a subtle border.
  outlined,

  /// Raised surface with a medium border.
  raised,

  /// Borderless tinted block for grouping inside another panel.
  inset,
}

/// A bordered container with the app's standard radius and padding.
class AppPanel extends StatelessWidget {
  const AppPanel({
    super.key,
    required this.child,
    this.variant = AppPanelVariant.outlined,
    this.padding = const EdgeInsets.all(VisionMetrics.space12),
  });

  final Widget child;
  final AppPanelVariant variant;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final (Color fill, Color? border) = switch (variant) {
      AppPanelVariant.outlined => (t.background, t.borderSubtle),
      AppPanelVariant.raised => (t.surfaceHigh, t.borderMedium),
      AppPanelVariant.inset => (t.surfaceMid, null),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        border: border == null
            ? null
            : Border.all(color: border, width: VisionMetrics.borderWidth),
        borderRadius: BorderRadius.circular(VisionMetrics.radius4),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Inline error message with an optional retry action.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel,
  });

  final String message;
  final VoidCallback? onRetry;

  /// Label for the retry button; defaults to the localized "Retry".
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final color = AppTone.error.color(t);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: VisionMetrics.opacityHover),
        border: Border.all(
          color: color.withValues(alpha: VisionMetrics.opacityScrim),
        ),
        borderRadius: BorderRadius.circular(VisionMetrics.radius4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(VisionMetrics.space12),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              size: VisionMetrics.iconMedium,
              color: color,
            ),
            const SizedBox(width: VisionMetrics.space8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: color, fontSize: t.fontSize(11)),
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                child: Text(
                  (retryLabel ?? context.l.commonRetry).toUpperCase(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
