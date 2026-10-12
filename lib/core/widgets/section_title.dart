import 'package:flutter/material.dart';
import '../theme/vision_metrics.dart';
import '../theme/vision_tokens.dart';

/// Visual weight of a [SectionTitle].
enum SectionTitleVariant {
  /// Default panel section label.
  standard,

  /// Tighter spacing for dense lists and nested groups.
  compact,
}

/// A standardized section title used across tool panels.
class SectionTitle extends StatelessWidget {
  final String title;
  final VisionTokens t;
  final SectionTitleVariant variant;

  /// Optional widget aligned to the end of the title row (e.g. an action).
  final Widget? trailing;

  const SectionTitle(
    this.title, {
    super.key,
    required this.t,
    this.variant = SectionTitleVariant.standard,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final compact = variant == SectionTitleVariant.compact;
    final text = Text(
      title,
      style: TextStyle(
        color: t.textTertiary,
        fontSize: t.titleSize(8),
        letterSpacing: compact ? 1 : 2,
        fontWeight: FontWeight.bold,
      ),
    );
    return Padding(
      padding: EdgeInsets.only(
        bottom: compact ? VisionMetrics.space8 : VisionMetrics.space12,
      ),
      child: trailing == null
          ? text
          : Row(
              children: [
                Expanded(child: text),
                const SizedBox(width: VisionMetrics.space8),
                trailing!,
              ],
            ),
    );
  }
}
