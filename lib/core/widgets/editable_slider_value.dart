import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/theme_extensions.dart';

/// Tappable numeric readout for a slider. Tapping the value swaps it for an
/// inline text field so a precise value can be typed directly — including
/// values beyond the slider's visible (soft) range, up to an optional hard cap.
///
/// Mirrors NovelAI's "click the number to type a value" behaviour. The slider
/// itself stays clamped to [softMin]..[softMax]; only typed entry can exceed
/// the soft bounds (bounded by [hardMin]..[hardMax] when provided).
class EditableSliderValue extends StatefulWidget {
  /// Current value.
  final double value;

  /// Slider's visible range. Typed values may exceed this when a wider
  /// hard range is supplied.
  final double softMin;
  final double softMax;

  /// Absolute clamp for typed entry. Defaults to the soft range, i.e. typing
  /// cannot exceed the slider unless the caller opts in by widening these.
  final double? hardMin;
  final double? hardMax;

  /// Whether values are whole numbers (controls formatting + keyboard).
  final bool isInteger;

  /// Decimal places when [isInteger] is false.
  final int decimals;

  /// Called with the committed, clamped value.
  final ValueChanged<double> onChanged;

  /// Text style for the readout (also used inside the editor field).
  final TextStyle style;

  const EditableSliderValue({
    super.key,
    required this.value,
    required this.softMin,
    required this.softMax,
    required this.onChanged,
    required this.style,
    this.hardMin,
    this.hardMax,
    this.isInteger = false,
    this.decimals = 2,
  });

  double get _effectiveMin => hardMin ?? softMin;
  double get _effectiveMax => hardMax ?? softMax;

  String format(double v) =>
      isInteger ? v.round().toString() : v.toStringAsFixed(decimals);

  @override
  State<EditableSliderValue> createState() => _EditableSliderValueState();
}

class _EditableSliderValueState extends State<EditableSliderValue> {
  bool _editing = false;
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _editing) _commit();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _beginEdit() {
    _controller.text = widget.format(widget.value);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    setState(() => _editing = true);
    _focusNode.requestFocus();
  }

  void _commit() {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed != null) {
      final clamped =
          parsed.clamp(widget._effectiveMin, widget._effectiveMax).toDouble();
      final value = widget.isInteger ? clamped.roundToDouble() : clamped;
      widget.onChanged(value);
    }
    if (mounted) setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    if (!_editing) {
      return InkWell(
        onTap: _beginEdit,
        borderRadius: BorderRadius.circular(3),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          child: Text(widget.format(widget.value), style: widget.style),
        ),
      );
    }
    return SizedBox(
      width: 56,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: true,
        textAlign: TextAlign.right,
        keyboardType: TextInputType.numberWithOptions(
          decimal: !widget.isInteger,
          signed: widget._effectiveMin < 0,
        ),
        inputFormatters: [
          widget.isInteger
              ? FilteringTextInputFormatter.allow(RegExp(r'[0-9-]'))
              : FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
        ],
        style: widget.style,
        onSubmitted: (_) => _commit(),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: t.borderMedium),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: t.accent),
          ),
        ),
      ),
    );
  }
}
