import 'package:flutter/material.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/widgets/enabled_toggle.dart';
import '../../../core/widgets/manager_list_tile.dart';
import '../models/director_reference.dart';
import 'reference_fields.dart';

class DirectorRefEditorSheet extends StatefulWidget {
  final DirectorReference reference;
  final Function(DirectorReferenceType) onTypeChanged;
  final Function(double) onStrengthChanged;
  final Function(double) onFidelityChanged;
  final VoidCallback onToggleEnabled;
  final VoidCallback onRemove;

  const DirectorRefEditorSheet({
    super.key,
    required this.reference,
    required this.onTypeChanged,
    required this.onStrengthChanged,
    required this.onFidelityChanged,
    required this.onToggleEnabled,
    required this.onRemove,
  });

  @override
  State<DirectorRefEditorSheet> createState() => _DirectorRefEditorSheetState();
}

class _DirectorRefEditorSheetState extends State<DirectorRefEditorSheet> {
  late DirectorReferenceType _type;
  late double _strength;
  late double _fidelity;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _type = widget.reference.type;
    _strength = widget.reference.strength;
    _fidelity = widget.reference.fidelity;
    _enabled = widget.reference.enabled;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    final accent = refTypeColor(t, _type);
    return Container(
      color: t.surfaceMid,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 24,
        right: 24,
        top: 16,
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
                  l.refEditorTitle,
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
                  image: MemoryImage(widget.reference.originalImageBytes),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Type selector
          Text(
            l.refTypeLabel,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: t.fontSize(9),
              letterSpacing: 2,
              color: t.textDisabled,
            ),
          ),
          const SizedBox(height: 8),
          DirectorRefTypeSelector(
            type: _type,
            onChanged: (type) {
              setState(() => _type = type);
              widget.onTypeChanged(type);
            },
          ),
          const SizedBox(height: 20),

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
            label: l.refFidelity,
            value: _fidelity,
            accent: accent,
            onChanged: (v) {
              setState(() => _fidelity = v);
              widget.onFidelityChanged(v);
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
