import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Translation of Flutter text styling into CSS for the DOM-backed widgets
/// (`BrowserNativeTextArea`, `BrowserNativeSelectableText`).
///
/// Everything here is pure Dart so the mapping can be unit tested on the VM;
/// the Web implementations only copy [BrowserTextCss.properties] onto an
/// element's inline style.

/// iOS Safari zooms the page when a focused form control's font size is below
/// 16 CSS pixels. Mobile browsers therefore get a 16px floor for editable DOM
/// controls; desktop browsers keep the theme size.
double browserInputMinFontSize(TargetPlatform platform) => switch (platform) {
  TargetPlatform.iOS || TargetPlatform.android => 16,
  _ => 0,
};

/// The font size, in CSS pixels, the browser-native editor actually renders
/// for a Flutter [fontSize]: scaled by [textScaler] and floored by
/// [browserInputMinFontSize]. Layout that sizes a native textarea from its
/// line count must use this, not the themed size.
double browserInputFontSize(
  double fontSize, {
  required TextScaler textScaler,
  required TargetPlatform platform,
}) {
  final scaled = textScaler.scale(fontSize);
  final floor = browserInputMinFontSize(platform);
  return scaled < floor ? floor : scaled;
}

/// Formats [color] as a CSS `rgba()` value.
String cssColor(Color color) {
  final argb = color.toARGB32();
  final red = (argb >> 16) & 0xff;
  final green = (argb >> 8) & 0xff;
  final blue = argb & 0xff;
  final alpha = ((argb >> 24) & 0xff) / 255;
  return 'rgba($red, $green, $blue, ${_trimNumber(alpha, 3)})';
}

/// `light` or `dark`, for the CSS `color-scheme` property of a control drawn
/// over [background]. It drives the browser-painted parts of the control such
/// as the scrollbar and the autofill highlight.
String cssColorScheme(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark
    ? 'dark'
    : 'light';

const Set<String> _cssGenericFamilies = {
  'serif',
  'sans-serif',
  'monospace',
  'cursive',
  'fantasy',
  'system-ui',
  'ui-serif',
  'ui-sans-serif',
  'ui-monospace',
  'ui-rounded',
  'math',
  'emoji',
  'fangsong',
};

/// google_fonts registers every variant under `"$family_$variant"`, e.g.
/// `JetBrains Mono_regular` or `Inter_700italic`. That name only exists inside
/// the Flutter engine; the DOM knows the face by its real family name.
final RegExp _googleFontsVariantSuffix = RegExp(
  r'_(?:regular|italic|[1-9]00(?:italic)?)$',
);

final RegExp _monospaceFamily = RegExp(
  r'\b(?:mono|monospace|code)\b',
  caseSensitive: false,
);

/// Converts Flutter font family names into a CSS `font-family` list that a
/// browser can resolve, ending with a generic family so the DOM never falls
/// back to the browser default serif face.
String cssFontFamily(String? family, [List<String>? fallback]) {
  final families = <String>[];
  for (final raw in [family, ...?fallback]) {
    if (raw == null) continue;
    final name = raw.replaceFirst(_googleFontsVariantSuffix, '').trim();
    if (name.isNotEmpty && !families.contains(name)) families.add(name);
  }
  final generic = families.any(_monospaceFamily.hasMatch)
      ? 'monospace'
      : 'sans-serif';
  return [
    for (final name in families)
      _cssGenericFamilies.contains(name) ? name : _cssString(name),
    if (!families.contains(generic)) generic,
  ].join(', ');
}

/// The inline CSS that renders text the way a Flutter [TextStyle] would.
@immutable
class BrowserTextCss {
  const BrowserTextCss._(this.fontSize, this.properties);

  /// Resolves [style] (usually already merged with the ambient
  /// `DefaultTextStyle`) into CSS. [textScaler] applies the user's text
  /// scaling, as Flutter's own text widgets do; [minFontSize] is a floor for
  /// the scaled size (see [browserInputMinFontSize]).
  factory BrowserTextCss.fromTextStyle(
    TextStyle style, {
    TextScaler textScaler = TextScaler.noScaling,
    double minFontSize = 0,
  }) {
    final scaled = textScaler.scale(style.fontSize ?? 14);
    final fontSize = scaled < minFontSize ? minFontSize : scaled;
    final color = style.color;
    return BrowserTextCss._(fontSize, {
      'font-family': cssFontFamily(style.fontFamily, style.fontFamilyFallback),
      'font-size': '${_trimNumber(fontSize, 2)}px',
      'font-weight': '${(style.fontWeight ?? FontWeight.normal).value}',
      'font-style': style.fontStyle == FontStyle.italic ? 'italic' : 'normal',
      'letter-spacing': '${_trimNumber(style.letterSpacing ?? 0, 2)}px',
      'line-height': style.height == null
          ? 'normal'
          : _trimNumber(style.height!, 3),
      if (color != null) 'color': cssColor(color),
    });
  }

  /// The resolved (scaled and floored) font size in CSS pixels.
  final double fontSize;

  /// CSS property name → value, ready for `style.setProperty`.
  final Map<String, String> properties;

  @override
  bool operator ==(Object other) =>
      other is BrowserTextCss && mapEquals(other.properties, properties);

  @override
  int get hashCode => Object.hashAllUnordered(
    properties.entries.map((entry) => Object.hash(entry.key, entry.value)),
  );
}

String _cssString(String value) =>
    '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

String _trimNumber(double value, int fractionDigits) {
  final fixed = value.toStringAsFixed(fractionDigits);
  if (!fixed.contains('.')) return fixed;
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}
