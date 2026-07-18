import 'package:flutter/material.dart';

/// A [TextEditingController] that provides syntax highlighting for
/// NovelAI prompt syntax: `{...}` (emphasis up), `[...]` (emphasis down),
/// and `N::...` (strength/weight).
class SyntaxHighlightController extends TextEditingController {
  bool enabled;

  SyntaxHighlightController({super.text, this.enabled = true});

  static const Color _emphasisUpColor = Color(0xFFFFA726); // orange
  static const Color _emphasisDownColor = Color(0xFF42A5F5); // blue
  static const Color _strengthColor = Color(0xFF66BB6A); // green

  /// Numerical emphasis opener: `N::` where N may be negative or fractional
  /// (e.g. `2::`, `1.5::`, `-1::`).
  static final RegExp _strengthPrefix = RegExp(r'^-?\d+(?:\.\d+)?::');

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (!enabled || text.isEmpty) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }

    final spans = <InlineSpan>[];
    final src = text;
    int i = 0;

    // Track nesting depth for curly and square brackets
    int curlyDepth = 0;
    int squareDepth = 0;

    while (i < src.length) {
      // Numerical emphasis: `N::tags::`. The whole unit — weight prefix, tag
      // body, and closing `::` — is highlighted so it reads as one emphasized
      // span like NAI's editor. An unterminated `N::` (still being typed)
      // gets only the prefix colored. Handled at any bracket depth: the
      // bracket-run collectors below break out at a weight prefix and rely on
      // this branch to consume it.
      final strengthMatch = _strengthPrefix.matchAsPrefix(src, i);
      if (strengthMatch != null) {
        spans.add(TextSpan(
          text: strengthMatch.group(0),
          style: style?.copyWith(color: _strengthColor) ?? TextStyle(color: _strengthColor),
        ));
        i = strengthMatch.end;
        final close = src.indexOf('::', i);
        if (close != -1) {
          if (close > i) {
            spans.add(TextSpan(
              text: src.substring(i, close),
              style: style?.copyWith(color: _strengthColor.withValues(alpha: 0.8)) ??
                  TextStyle(color: _strengthColor.withValues(alpha: 0.8)),
            ));
          }
          spans.add(TextSpan(
            text: '::',
            style: style?.copyWith(color: _strengthColor) ?? TextStyle(color: _strengthColor),
          ));
          i = close + 2;
        }
        continue;
      }

      if (src[i] == '{') {
        curlyDepth++;
        final alpha = (0.5 + 0.15 * curlyDepth).clamp(0.5, 1.0);
        spans.add(TextSpan(
          text: '{',
          style: style?.copyWith(color: _emphasisUpColor.withValues(alpha: alpha)) ??
              TextStyle(color: _emphasisUpColor.withValues(alpha: alpha)),
        ));
        i++;
        continue;
      }

      if (src[i] == '}' && curlyDepth > 0) {
        final alpha = (0.5 + 0.15 * curlyDepth).clamp(0.5, 1.0);
        spans.add(TextSpan(
          text: '}',
          style: style?.copyWith(color: _emphasisUpColor.withValues(alpha: alpha)) ??
              TextStyle(color: _emphasisUpColor.withValues(alpha: alpha)),
        ));
        curlyDepth--;
        i++;
        continue;
      }

      if (src[i] == '[') {
        squareDepth++;
        final alpha = (0.5 + 0.15 * squareDepth).clamp(0.5, 1.0);
        spans.add(TextSpan(
          text: '[',
          style: style?.copyWith(color: _emphasisDownColor.withValues(alpha: alpha)) ??
              TextStyle(color: _emphasisDownColor.withValues(alpha: alpha)),
        ));
        i++;
        continue;
      }

      if (src[i] == ']' && squareDepth > 0) {
        final alpha = (0.5 + 0.15 * squareDepth).clamp(0.5, 1.0);
        spans.add(TextSpan(
          text: ']',
          style: style?.copyWith(color: _emphasisDownColor.withValues(alpha: alpha)) ??
              TextStyle(color: _emphasisDownColor.withValues(alpha: alpha)),
        ));
        squareDepth--;
        i++;
        continue;
      }

      // Unmatched closing brackets at depth 0 — render as plain text
      if (src[i] == '}') {
        spans.add(TextSpan(text: '}', style: style));
        i++;
        continue;
      }

      if (src[i] == ']') {
        spans.add(TextSpan(text: ']', style: style));
        i++;
        continue;
      }

      // Inside emphasis brackets — color the text
      if (curlyDepth > 0) {
        // Collect run of non-bracket chars
        final start = i;
        while (i < src.length && src[i] != '{' && src[i] != '}' && src[i] != '[' && src[i] != ']') {
          // Check for strength prefix inside brackets
          final strengthMatch = _strengthPrefix.matchAsPrefix(src, i);
          if (strengthMatch != null) break;
          i++;
        }
        if (i > start) {
          final alpha = (0.5 + 0.15 * curlyDepth).clamp(0.5, 1.0);
          spans.add(TextSpan(
            text: src.substring(start, i),
            style: style?.copyWith(color: _emphasisUpColor.withValues(alpha: alpha)) ??
                TextStyle(color: _emphasisUpColor.withValues(alpha: alpha)),
          ));
        }
        continue;
      }

      if (squareDepth > 0) {
        final start = i;
        while (i < src.length && src[i] != '{' && src[i] != '}' && src[i] != '[' && src[i] != ']') {
          final strengthMatch = _strengthPrefix.matchAsPrefix(src, i);
          if (strengthMatch != null) break;
          i++;
        }
        if (i > start) {
          final alpha = (0.5 + 0.15 * squareDepth).clamp(0.5, 1.0);
          spans.add(TextSpan(
            text: src.substring(start, i),
            style: style?.copyWith(color: _emphasisDownColor.withValues(alpha: alpha)) ??
                TextStyle(color: _emphasisDownColor.withValues(alpha: alpha)),
          ));
        }
        continue;
      }

      // Plain text — collect run
      final start = i;
      while (i < src.length && src[i] != '{' && src[i] != '}' && src[i] != '[' && src[i] != ']') {
        final strengthMatch = _strengthPrefix.matchAsPrefix(src, i);
        if (strengthMatch != null) break;
        i++;
      }
      if (i > start) {
        spans.add(TextSpan(text: src.substring(start, i), style: style));
      }
    }

    return TextSpan(children: spans, style: style);
  }
}
