import 'package:flutter/material.dart';

/// A display-only narration caption rendered over the bottom of an image using
/// the "scrim" technique: a transparent→dark bottom gradient that guarantees
/// legible white text on top of any image, bright or dark.
///
/// Pure presentation — it never alters the underlying image bytes. Wrap it in a
/// [Stack] above the image (it positions itself at the bottom):
///
/// ```dart
/// Stack(children: [Image.memory(bytes), CaptionOverlay(text: caption)])
/// ```
class CaptionOverlay extends StatelessWidget {
  final String text;

  /// Fraction of the available height the scrim gradient occupies (0–1).
  final double scrimHeightFraction;

  /// Caption font size in logical pixels.
  final double fontSize;

  const CaptionOverlay({
    super.key,
    required this.text,
    this.scrimHeightFraction = 0.4,
    this.fontSize = 13,
  });

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 0.0;
            return Container(
              padding: const EdgeInsets.fromLTRB(14, 28, 14, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: const [
                    Colors.transparent,
                    Color(0x99000000), // black @ ~60%
                  ],
                ),
              ),
              constraints: h > 0
                  ? BoxConstraints(maxHeight: h * scrimHeightFraction + 40)
                  : const BoxConstraints(),
              child: Text(
                text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                  // Outline + shadow so text stays legible even where the scrim
                  // is faint (top edge) over a bright image.
                  shadows: const [
                    Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 1)),
                    Shadow(color: Color(0xCC000000), blurRadius: 8),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
