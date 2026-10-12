import 'package:flutter/material.dart';
import '../../../core/theme/vision_metrics.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/widgets/enabled_toggle.dart';
import '../../../core/widgets/manager_list_tile.dart';
import '../../director_ref/widgets/reference_fields.dart';
import '../models/vibe_transfer.dart';

class VibeTransferEditorSheet extends StatefulWidget {
  final VibeTransfer vibe;
  final Function(double) onStrengthChanged;
  final Function(double) onInfoExtractedChanged;
  final VoidCallback onToggleEnabled;
  final VoidCallback onRemove;

  const VibeTransferEditorSheet({
    super.key,
    required this.vibe,
    required this.onStrengthChanged,
    required this.onInfoExtractedChanged,
    required this.onToggleEnabled,
    required this.onRemove,
  });

  @override
  State<VibeTransferEditorSheet> createState() =>
      _VibeTransferEditorSheetState();
}

class _VibeTransferEditorSheetState extends State<VibeTransferEditorSheet> {
  late double _strength;
  late double _infoExtracted;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _strength = widget.vibe.strength;
    _infoExtracted = widget.vibe.infoExtracted;
    _enabled = widget.vibe.enabled;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    final accent = t.accentVibeTransfer;
    return Padding(
      // showAppSheet supplies the background, keyboard inset and safe area.
      padding: const EdgeInsets.only(
        left: VisionMetrics.space24,
        right: VisionMetrics.space24,
        top: VisionMetrics.space16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  l.refVibeEditorTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: t.fontSize(12),
                    letterSpacing: 4,
                    color: t.textPrimary,
                  ),
                ),
              ),
              EnabledToggle(
                enabled: _enabled,
                accent: accent,
                onTap: () {
                  setState(() => _enabled = !_enabled);
                  widget.onToggleEnabled();
                },
              ),
              const SizedBox(width: 4),
              ManagerIconButton(
                icon: Icons.delete_outline,
                tooltip: l.refRemove,
                color: t.accentDanger,
                onPressed: () {
                  widget.onRemove();
                  Navigator.pop(context);
                },
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Image preview
          Center(
            child: Container(
              height: 160,
              width: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: accent, width: 1.5),
                image: DecorationImage(
                  image: MemoryImage(widget.vibe.originalImageBytes),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          ReferenceSliderField(
            label: l.refStrength,
            value: _strength,
            accent: accent,
            onChanged: (v) {
              setState(() => _strength = v);
              widget.onStrengthChanged(v);
            },
          ),
          const SizedBox(height: 16),

          ReferenceSliderField(
            label: l.refInfoExtracted,
            value: _infoExtracted,
            accent: accent,
            onChanged: (v) {
              setState(() => _infoExtracted = v);
              widget.onInfoExtractedChanged(v);
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
