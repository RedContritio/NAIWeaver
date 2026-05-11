import 'package:flutter/material.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_tokens.dart';

class WardrobeGenerateParams {
  final int count;
  final String eraHint;
  final String vibeHint;
  const WardrobeGenerateParams({
    required this.count,
    this.eraHint = '',
    this.vibeHint = '',
  });
}

/// Dialog asking how many outfits to generate, plus optional era/setting and
/// vibe hints.
class WardrobeGenerateDialog extends StatefulWidget {
  const WardrobeGenerateDialog({super.key});

  static Future<WardrobeGenerateParams?> show(BuildContext context) {
    return showDialog<WardrobeGenerateParams>(
      context: context,
      builder: (_) => const WardrobeGenerateDialog(),
    );
  }

  @override
  State<WardrobeGenerateDialog> createState() => _WardrobeGenerateDialogState();
}

class _WardrobeGenerateDialogState extends State<WardrobeGenerateDialog> {
  double _count = 6;
  final _era = TextEditingController();
  final _vibe = TextEditingController();

  @override
  void dispose() {
    _era.dispose();
    _vibe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AlertDialog(
      backgroundColor: t.surfaceHigh,
      title: Text('GENERATE OUTFITS',
          style: TextStyle(
              color: t.textSecondary,
              fontSize: t.titleSize(11),
              letterSpacing: 3,
              fontWeight: FontWeight.bold)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('HOW MANY: ${_count.round()}',
                style: TextStyle(color: t.textTertiary, fontSize: t.fontSize(9), letterSpacing: 1.5)),
            Slider(
              value: _count,
              min: 3,
              max: 14,
              divisions: 11,
              activeColor: t.accent,
              label: '${_count.round()}',
              onChanged: (v) => setState(() => _count = v),
            ),
            const SizedBox(height: 8),
            Text('ERA / SETTING HINT (optional)',
                style: TextStyle(color: t.textTertiary, fontSize: t.fontSize(8), letterSpacing: 1.5)),
            const SizedBox(height: 4),
            TextField(
              controller: _era,
              style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(12)),
              decoration: _deco(t, 'e.g. 1920s Paris, Heian-era Japan, near-future'),
            ),
            const SizedBox(height: 10),
            Text('VIBE HINT (optional)',
                style: TextStyle(color: t.textTertiary, fontSize: t.fontSize(8), letterSpacing: 1.5)),
            const SizedBox(height: 4),
            TextField(
              controller: _vibe,
              style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(12)),
              decoration: _deco(t, 'e.g. cozy academia, gothic, beachy minimalist'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('CANCEL', style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(9))),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(WardrobeGenerateParams(
            count: _count.round(),
            eraHint: _era.text.trim(),
            vibeHint: _vibe.text.trim(),
          )),
          style: ElevatedButton.styleFrom(
            backgroundColor: t.accent.withValues(alpha: 0.2),
            foregroundColor: t.accent,
            elevation: 0,
          ),
          child: Text('GENERATE', style: TextStyle(fontSize: t.fontSize(9), letterSpacing: 1)),
        ),
      ],
    );
  }

  InputDecoration _deco(VisionTokens t, String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: t.textMinimal, fontSize: t.fontSize(10)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: t.borderSubtle), borderRadius: BorderRadius.circular(4)),
        focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: t.accent), borderRadius: BorderRadius.circular(4)),
      );
}
