import 'package:flutter/material.dart';
import '../theme/theme_extensions.dart';
import '../theme/vision_metrics.dart';
import '../widgets/ui/app_tone.dart';

/// Shows a floating snack bar. The look comes from [tone] (default success);
/// the legacy [color] still overrides the accent for existing callers.
void showAppSnackBar(
  BuildContext context,
  String message, {
  Color? color,
  SnackBarAction? action,
  AppTone tone = AppTone.success,
}) {
  final t = context.tRead;
  final c = color ?? tone.color(t);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: TextStyle(color: c, fontSize: t.fontSize(11)),
      ),
      backgroundColor: Color.alphaBlend(
        c.withValues(alpha: VisionMetrics.opacityHover),
        t.background,
      ),
      behavior: SnackBarBehavior.floating,
      action: action,
      duration: action != null
          ? const Duration(seconds: 6)
          : const Duration(seconds: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VisionMetrics.radius4),
        side: BorderSide(
          color: c.withValues(alpha: VisionMetrics.opacityScrim),
        ),
      ),
    ),
  );
}

void showErrorSnackBar(BuildContext context, String message) =>
    showAppSnackBar(context, message, tone: AppTone.error);
