import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/theme_extensions.dart';
import '../../theme/vision_metrics.dart';
import 'app_tone.dart';

/// Centered placeholder for lists and panels with nothing to show.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.icon,
    this.title,
    this.action,
  });

  final String message;
  final IconData? icon;
  final String? title;

  /// Optional call to action shown under the message.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return _StateFrame(
      children: [
        if (icon != null)
          Icon(icon, size: VisionMetrics.iconLarge * 2, color: t.textMinimal),
        if (title != null)
          Text(
            title!.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: t.titleSize(10),
              letterSpacing: 2,
              fontWeight: FontWeight.bold,
            ),
          ),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: t.textTertiary, fontSize: t.fontSize(11)),
        ),
        if (action != null) action!,
      ],
    );
  }
}

/// Centered progress indicator with an optional label.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return _StateFrame(
      children: [
        Semantics(
          label: label ?? context.l.commonLoading,
          child: SizedBox(
            width: VisionMetrics.iconLarge,
            height: VisionMetrics.iconLarge,
            child: CircularProgressIndicator(strokeWidth: 2, color: t.accent),
          ),
        ),
        if (label != null)
          Text(
            label!,
            textAlign: TextAlign.center,
            style: TextStyle(color: t.textTertiary, fontSize: t.fontSize(11)),
          ),
      ],
    );
  }
}

/// Centered error with an optional retry action.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel,
  });

  final String message;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final color = AppTone.error.color(t);
    return _StateFrame(
      children: [
        Icon(
          Icons.error_outline,
          size: VisionMetrics.iconLarge * 2,
          color: color,
        ),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontSize: t.fontSize(11)),
        ),
        if (onRetry != null)
          TextButton(
            onPressed: onRetry,
            child: Text((retryLabel ?? context.l.commonRetry).toUpperCase()),
          ),
      ],
    );
  }
}

class _StateFrame extends StatelessWidget {
  const _StateFrame({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(VisionMetrics.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: VisionMetrics.space12,
          children: children,
        ),
      ),
    );
  }
}
