import 'package:flutter/material.dart';
import '../l10n/l10n_extensions.dart';
import '../theme/theme_extensions.dart';

/// Compact pill toggle used to enable/disable an item (vibe / reference)
/// without removing it. Shows an eye / eye-off icon plus the localized
/// "Enabled" label, tinted by [accent] when on and muted when off.
class EnabledToggle extends StatelessWidget {
  final bool enabled;
  final Color accent;
  final VoidCallback onTap;

  const EnabledToggle({
    super.key,
    required this.enabled,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final color = enabled ? accent : t.textDisabled;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: enabled ? accent : t.borderMedium),
          color: enabled ? accent.withValues(alpha: 0.15) : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              enabled ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(
              context.l.panelEnabled.toUpperCase(),
              style: TextStyle(
                color: color,
                fontSize: t.fontSize(8),
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
