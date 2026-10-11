import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme_notifier.dart';
import 'vision_metrics.dart';
import 'vision_tokens.dart';

extension ThemeTokensExtension on BuildContext {
  /// Shorthand for accessing VisionTokens: `context.t.background`
  /// Use in build() methods only (reactive via watch).
  VisionTokens get t => watch<ThemeNotifier>().tokens;

  /// Non-reactive read for event handlers, callbacks, and async methods.
  VisionTokens get tRead => read<ThemeNotifier>().tokens;

  /// Window-dependent visual control size (48 touch, 32 pointer).
  double get touchSize => VisionMetrics.touchTargetFor(this);

  /// Hit area (at least 40) for the current window.
  double get hitSize => VisionMetrics.hitTargetFor(this);
}
