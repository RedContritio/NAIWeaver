import 'package:flutter/material.dart';

/// A text field for a value owned by someone else (a model, a notifier).
///
/// It keeps one controller for its whole life, so rebuilding the parent never
/// resets the caret or drops what is being typed. When [value] changes to
/// something the field does not already show, the text is replaced and the
/// caret moves to the end.
class SyncedTextField extends StatefulWidget {
  const SyncedTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.style,
    this.decoration,
    this.maxLines = 1,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final TextStyle? style;
  final InputDecoration? decoration;
  final int? maxLines;

  @override
  State<SyncedTextField> createState() => _SyncedTextFieldState();
}

class _SyncedTextFieldState extends State<SyncedTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(SyncedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      style: widget.style,
      decoration: widget.decoration,
      maxLines: widget.maxLines,
    );
  }
}
