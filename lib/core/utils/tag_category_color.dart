import 'dart:ui' show Color;

import '../theme/vision_tokens.dart';

/// Accent for a Danbooru tag category, taken from the theme tokens so it
/// follows the active theme: copyright -> style accent, character -> success,
/// artist -> danger, meta -> character accent, anything else -> primary text.
/// The autocomplete's pseudo categories get their own accents: wildcard ->
/// primary accent, favorite wildcard -> favorite, saved character -> character
/// reference accent, category shortcut -> danger.
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
    case 'wildcard':
      return t.accent;
    case 'wildcard_favorite':
      return t.accentFavorite;
    case 'saved_character':
      return t.accentRefCharacter;
    case 'category_shortcut':
      return t.accentDanger;
    default:
      return t.textPrimary;
  }
}
