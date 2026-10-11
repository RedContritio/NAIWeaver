import 'dart:ui' show Color;

import '../../../core/theme/vision_tokens.dart';

/// Accent for a Danbooru tag category, taken from the theme tokens so it
/// follows the active theme: copyright -> style accent, character -> success,
/// artist -> danger, meta -> character accent, anything else -> primary text.
Color tagCategoryColor(VisionTokens t, String? category) {
  switch ((category ?? '').toLowerCase()) {
    case 'copyright':
      return t.accentRefStyle;
    case 'character':
      return t.accentSuccess;
    case 'artist':
      return t.accentDanger;
    case 'meta':
      return t.accentCharacter;
    default:
      return t.textPrimary;
  }
}
