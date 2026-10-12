import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../theme/theme_extensions.dart';
import '../../utils/app_snackbar.dart';
import '../../utils/responsive.dart';
import '../../widgets/comparison_slider.dart';
import '../../widgets/side_by_side_comparison.dart';
import '../../../l10n/app_localizations.dart';
import '../../theme/vision_metrics.dart';

class UpscaleComparisonView extends StatefulWidget {
  final Uint8List originalBytes;
  final Uint8List upscaledBytes;
  final String outputName;

  /// Returns whether the result was saved; the caller reports failures.
  final Future<bool> Function() onSave;
  final bool autoSave;

  const UpscaleComparisonView({
    super.key,
    required this.originalBytes,
    required this.upscaledBytes,
    required this.outputName,
    required this.onSave,
    this.autoSave = false,
  });

  @override
  State<UpscaleComparisonView> createState() => _UpscaleComparisonViewState();
}

class _UpscaleComparisonViewState extends State<UpscaleComparisonView> {
  bool _saved = false;
  bool _saving = false;
  bool _saveFailed = false;
  bool _sideBySide = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoSave) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handleSave();
      });
    }
  }

  Future<void> _handleSave() async {
    if (_saved || _saving) return;
    setState(() => _saving = true);
    final saved = await widget.onSave();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = saved;
      _saveFailed = !saved;
    });
    if (saved) {
      showAppSnackBar(
        context,
        AppLocalizations.of(context).mlSavedFile(widget.outputName),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = AppLocalizations.of(context);
    final mobile = isTouchSized(context);

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        backgroundColor: t.background,
        elevation: 0,
        toolbarHeight: mobile ? 48 : 32,
        leading: IconButton(
          icon: Icon(
            Icons.close,
            size: mobile ? 22 : 16,
            color: t.textSecondary,
          ),
          tooltip: l.commonClose,
          onPressed: () => Navigator.pop(context, _saved),
        ),
        title: Text(
          l.mlUpscaleCompare,
          style: TextStyle(
            letterSpacing: 4,
            fontSize: t.fontSize(mobile ? 14 : 10),
            fontWeight: FontWeight.w900,
            color: t.textSecondary,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _sideBySide ? Icons.compare : Icons.view_column,
              size: mobile ? 22 : 16,
              color: t.textDisabled,
            ),
            tooltip: _sideBySide
                ? l.comparisonSliderMode
                : l.comparisonSideBySide,
            onPressed: () => setState(() => _sideBySide = !_sideBySide),
          ),
          // A failed auto-save falls back to the manual button for a retry.
          if (!widget.autoSave || _saveFailed)
            TextButton(
              onPressed: _saved || _saving ? null : _handleSave,
              child: Text(
                _saved ? l.mlSaved : l.mlSave,
                style: TextStyle(
                  color: _saved ? t.textDisabled : t.accentSuccess,
                  fontSize: t.fontSize(mobile ? 12 : 9),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ),
          const SizedBox(width: VisionMetrics.space4),
        ],
      ),
      body: _sideBySide
          ? SideBySideComparison(
              beforeBytes: widget.originalBytes,
              afterBytes: widget.upscaledBytes,
              beforeLabel: l.comparisonBefore.toUpperCase(),
              afterLabel: l.comparisonAfter.toUpperCase(),
            )
          : ComparisonSlider(
              beforeBytes: widget.originalBytes,
              afterBytes: widget.upscaledBytes,
              beforeLabel: l.comparisonBefore.toUpperCase(),
              afterLabel: l.comparisonAfter.toUpperCase(),
            ),
    );
  }
}
