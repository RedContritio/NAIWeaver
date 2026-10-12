import 'package:flutter/painting.dart';

import '../../theme/vision_tokens.dart';

/// Semantic emphasis shared by pills, banners and snack bars.
enum AppTone { neutral, info, success, warning, error }

extension AppToneColor on AppTone {
  /// Foreground / border color for this tone, taken from [t].
  Color color(VisionTokens t) => switch (this) {
    AppTone.neutral => t.textSecondary,
    AppTone.info => t.accent,
    AppTone.success => t.accentSuccess,
    AppTone.warning => t.accentFavorite,
    AppTone.error => t.accentDanger,
  };
}
