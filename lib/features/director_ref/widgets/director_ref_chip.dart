import 'package:flutter/material.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_metrics.dart';
import '../models/director_reference.dart';

class DirectorRefChip extends StatelessWidget {
  final DirectorReference reference;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Why the reference is held back although the user enabled it; null when
  /// it is not paused.
  final String? pausedReason;

  const DirectorRefChip({
    super.key,
    required this.reference,
    required this.onTap,
    required this.onLongPress,
    this.pausedReason,
  });

  IconData get _typeIcon {
    switch (reference.type) {
      case DirectorReferenceType.character:
        return Icons.person;
      case DirectorReferenceType.style:
        return Icons.palette;
      case DirectorReferenceType.characterAndStyle:
        return Icons.auto_awesome;
    }
  }

  Color _borderColor(BuildContext context) {
    final t = context.t;
    switch (reference.type) {
      case DirectorReferenceType.character:
        return t.accentRefCharacter;
      case DirectorReferenceType.style:
        return t.accentRefStyle;
      case DirectorReferenceType.characterAndStyle:
        return t.accentRefCharStyle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final paused = pausedReason != null;
    final disabled = !reference.enabled || paused;
    final border = disabled ? t.textDisabled : _borderColor(context);
    final chip = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          height: context.hitSize,
          child: Center(
            child: Opacity(
              opacity: disabled ? VisionMetrics.opacityDisabled : 1.0,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: border, width: 1.5),
                  image: DecorationImage(
                    image: MemoryImage(reference.originalImageBytes),
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    colorFilter: disabled
                        ? ColorFilter.mode(t.textDisabled, BlendMode.saturation)
                        : null,
                  ),
                ),
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Container(
                    padding: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      color: t.background.withValues(alpha: 0.7),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(3),
                      ),
                    ),
                    child: Icon(
                      paused
                          ? Icons.pause_circle_outline
                          : disabled
                          ? Icons.visibility_off
                          : _typeIcon,
                      size: 10,
                      color: border,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return paused ? Tooltip(message: pausedReason!, child: chip) : chip;
  }
}
