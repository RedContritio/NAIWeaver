import 'package:flutter/material.dart';
import '../../../core/theme/theme_extensions.dart';
import '../models/director_reference.dart';

class DirectorRefChip extends StatelessWidget {
  final DirectorReference reference;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const DirectorRefChip({
    super.key,
    required this.reference,
    required this.onTap,
    required this.onLongPress,
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
    final disabled = !reference.enabled;
    final border = disabled ? t.textDisabled : _borderColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Opacity(
          opacity: disabled ? 0.4 : 1.0,
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
                    ? const ColorFilter.mode(Colors.grey, BlendMode.saturation)
                    : null,
              ),
            ),
            child: Align(
              alignment: Alignment.bottomRight,
              child: Container(
                padding: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: t.background.withValues(alpha: 0.7),
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(3)),
                ),
                child: Icon(
                  disabled ? Icons.visibility_off : _typeIcon,
                  size: 10,
                  color: border,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
