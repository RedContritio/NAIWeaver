import 'package:flutter/material.dart';
import '../l10n/l10n_extensions.dart';
import '../theme/theme_extensions.dart';

/// Asks for a single-line name and returns it trimmed, or `null` when the
/// dialog is cancelled. Blank or whitespace-only input is rejected inline, so
/// callers never receive an empty value.
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? hintText,
  String initialValue = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextInputDialog(
      title: title,
      confirmLabel: confirmLabel,
      hintText: hintText,
      initialValue: initialValue,
    ),
  );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.confirmLabel,
    required this.hintText,
    required this.initialValue,
  });

  final String title;
  final String confirmLabel;
  final String? hintText;
  final String initialValue;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = context.l.commonNameRequired);
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    return AlertDialog(
      backgroundColor: t.surfaceHigh,
      title: Text(
        widget.title,
        style: TextStyle(
          fontSize: t.fontSize(10),
          letterSpacing: 2,
          color: t.textSecondary,
        ),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
        style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(13)),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: TextStyle(color: t.textMinimal, fontSize: t.fontSize(9)),
          errorText: _error,
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: t.borderMedium),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            l.commonCancel.toUpperCase(),
            style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(9)),
          ),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(
            widget.confirmLabel.toUpperCase(),
            style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(9)),
          ),
        ),
      ],
    );
  }
}
