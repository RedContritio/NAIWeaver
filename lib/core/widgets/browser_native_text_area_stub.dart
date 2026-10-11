import 'package:flutter/material.dart';

import 'browser_native_key_event.dart';

const bool supportsBrowserNativeTextArea = false;

class BrowserNativeTextArea extends StatelessWidget {
  final Widget fallback;

  const BrowserNativeTextArea({
    super.key,
    required TextEditingController controller,
    required this.fallback,
    TextStyle? style,
    String? hintText,
    Color? backgroundColor,
    Color? borderColor,
    Color? selectionColor,
    Color? selectionTextColor,
    EdgeInsets? padding,
    double? height,
    ValueChanged<String>? onChanged,
    VoidCallback? onTap,
    FocusNode? focusNode,
    VoidCallback? onBlur,
    BrowserNativeKeyHandler? onKeyDown,
  });

  @override
  Widget build(BuildContext context) => fallback;
}
