import 'package:flutter/material.dart';

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
    bool Function(String key, bool control, bool alt, bool shift)? onKeyDown,
  });

  @override
  Widget build(BuildContext context) => fallback;
}
