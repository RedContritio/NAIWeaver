import 'package:flutter/material.dart';
import '../../../core/theme/theme_extensions.dart';
import '../models/vibe_transfer.dart';

class VibeTransferChip extends StatelessWidget {
  final VibeTransfer vibe;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const VibeTransferChip({
    super.key,
    required this.vibe,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final disabled = !vibe.enabled;
    final accent = disabled ? t.textDisabled : t.accentVibeTransfer;
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
              border: Border.all(color: accent, width: 1.5),
              image: DecorationImage(
                image: MemoryImage(vibe.processedPreview),
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
                  borderRadius:
                      const BorderRadius.only(topLeft: Radius.circular(3)),
                ),
                child: disabled
                    ? Icon(Icons.visibility_off, size: 10, color: accent)
                    : Text(
                        'V',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: accent,
                          letterSpacing: 0,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
