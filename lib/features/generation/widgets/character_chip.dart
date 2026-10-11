import 'package:flutter/material.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_metrics.dart';
import '../models/nai_character.dart';

class CharacterChip extends StatelessWidget {
  final int index;
  final NaiCharacter character;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const CharacterChip({
    super.key,
    required this.index,
    required this.character,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final hasPrompt = character.prompt.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VisionMetrics.space4),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Chip(
          backgroundColor: hasPrompt
              ? t.accent.withValues(alpha: VisionMetrics.opacityPressed)
              : t.textMinimal,
          label: Text(
            'C${index + 1}',
            style: TextStyle(
              fontSize: t.fontSize(10),
              fontWeight: FontWeight.bold,
              color: hasPrompt ? t.accent : t.textSecondary,
            ),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(VisionMetrics.radius4),
            side: BorderSide(
              color: hasPrompt ? t.accent : t.textMinimal,
              width: VisionMetrics.borderWidth,
            ),
          ),
          padding: EdgeInsets.zero,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}
