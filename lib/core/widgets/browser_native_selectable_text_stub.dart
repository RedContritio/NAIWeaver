import 'package:flutter/material.dart';

class BrowserNativeSelectableText extends StatelessWidget {
  const BrowserNativeSelectableText({
    super.key,
    required this.text,
    this.height,
    this.style,
  });

  final String text;
  final double? height;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final child = SelectableText(text, style: style);
    return height == null
        ? child
        : SizedBox(
            height: height,
            child: Align(alignment: Alignment.centerLeft, child: child),
          );
  }
}
