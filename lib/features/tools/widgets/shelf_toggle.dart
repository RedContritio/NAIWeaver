import 'package:flutter/material.dart';

import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_metrics.dart';

/// Labelled on/off switch row shared by the settings-style panels.
///
/// The whole row is the touch target. A null [onChanged] renders it disabled.
class ShelfToggle extends StatelessWidget {
  const ShelfToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
  });

  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final enabled = onChanged != null;
    final dim = enabled ? 1.0 : VisionMetrics.opacityDisabled;
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: label,
      child: InkWell(
        onTap: enabled ? () => onChanged!(!value) : null,
        borderRadius: BorderRadius.circular(VisionMetrics.radius4),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: context.hitSize),
          child: Row(
            children: [
              Expanded(
                child: Opacity(
                  opacity: dim,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: t.headerText,
                          fontSize: t.fontSize(11),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (description != null) ...[
                        const SizedBox(height: VisionMetrics.space4),
                        Text(
                          description!,
                          style: TextStyle(
                            color: t.textTertiary,
                            fontSize: t.fontSize(9),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: t.accent,
                activeTrackColor: t.borderStrong,
                inactiveThumbColor: t.textDisabled,
                inactiveTrackColor: t.borderSubtle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
