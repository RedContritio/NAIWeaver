import 'package:flutter/material.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_tokens.dart';
import '../models/closet_outfit.dart';
import 'tag_text_field.dart';

/// Modal editor for one closet outfit: name, clothing tags (autocomplete),
/// season/weather/activity multi-selects, temperature range slider, time-slot
/// selects, set-as-primary toggle.
class OutfitEditorSheet extends StatefulWidget {
  final ClosetOutfit outfit;
  final bool isPrimary;
  final void Function(ClosetOutfit outfit, bool makePrimary) onSave;

  const OutfitEditorSheet({
    super.key,
    required this.outfit,
    required this.isPrimary,
    required this.onSave,
  });

  static Future<void> show(
    BuildContext context, {
    required ClosetOutfit outfit,
    required bool isPrimary,
    required void Function(ClosetOutfit, bool) onSave,
  }) {
    return showDialog(
      context: context,
      builder: (_) => OutfitEditorSheet(
        outfit: outfit,
        isPrimary: isPrimary,
        onSave: onSave,
      ),
    );
  }

  @override
  State<OutfitEditorSheet> createState() => _OutfitEditorSheetState();
}

class _OutfitEditorSheetState extends State<OutfitEditorSheet> {
  late TextEditingController _name;
  late TextEditingController _tags;
  late Set<String> _seasons;
  late Set<String> _weather;
  late Set<String> _activities;
  late Set<String> _slots;
  late RangeValues _temp;
  late bool _makePrimary;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.outfit.name);
    _tags = TextEditingController(text: widget.outfit.tags);
    _seasons = widget.outfit.seasons.toSet();
    _weather = widget.outfit.weather.toSet();
    _activities = widget.outfit.activities.toSet();
    _slots = widget.outfit.slots.toSet();
    final tr = widget.outfit.temperatureRange;
    _temp = RangeValues(
      (tr.isNotEmpty ? tr[0] : -10).toDouble().clamp(-20, 45),
      (tr.length > 1 ? tr[1] : 35).toDouble().clamp(-20, 45),
    );
    _makePrimary = widget.isPrimary;
  }

  @override
  void dispose() {
    _name.dispose();
    _tags.dispose();
    super.dispose();
  }

  void _save() {
    final updated = widget.outfit.copyWith(
      name: _name.text.trim().isEmpty ? 'Outfit' : _name.text.trim(),
      tags: _tags.text.trim(),
      seasons: _seasons.toList(),
      weather: _weather.toList(),
      activities: _activities.toList(),
      slots: _slots.toList(),
      temperatureRange: [_temp.start.round(), _temp.end.round()],
      // Tags changed → drop the stale parsed state; the panel/re-parse will
      // rebuild it.
      items: _tags.text.trim() == widget.outfit.tags ? widget.outfit.items : null,
    );
    widget.onSave(updated, _makePrimary);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Dialog(
      backgroundColor: t.surfaceHigh,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.outfit.name.isEmpty ? 'NEW OUTFIT' : 'EDIT OUTFIT',
                  style: TextStyle(
                      color: t.textSecondary,
                      fontSize: t.titleSize(11),
                      letterSpacing: 3,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _labelled(t, 'NAME'),
                      TextField(
                        controller: _name,
                        style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(13)),
                        decoration: _inputDeco(t, 'Rainy Day Chic'),
                      ),
                      const SizedBox(height: 12),
                      TagTextField(
                        controller: _tags,
                        label: 'Clothing tags (4–7 garments)',
                        hint: 'cream knit sweater, navy pleated skirt, charcoal tights, brown ankle boots',
                        minLines: 2,
                        maxLines: 4,
                      ),
                      const SizedBox(height: 12),
                      _chips(t, 'SEASONS', ClosetOutfit.kSeasons, _seasons),
                      const SizedBox(height: 10),
                      _chips(t, 'WEATHER', ClosetOutfit.kWeather, _weather),
                      const SizedBox(height: 10),
                      _chips(t, 'ACTIVITIES', ClosetOutfit.kActivities, _activities),
                      const SizedBox(height: 10),
                      _chips(t, 'TIME SLOTS', ClosetOutfit.kTimeSlots, _slots),
                      const SizedBox(height: 14),
                      _labelled(t, 'COMFORTABLE TEMPERATURE  ${_temp.start.round()}°C – ${_temp.end.round()}°C'),
                      RangeSlider(
                        values: _temp,
                        min: -20,
                        max: 45,
                        divisions: 65,
                        activeColor: t.accent,
                        labels: RangeLabels('${_temp.start.round()}°', '${_temp.end.round()}°'),
                        onChanged: (v) => setState(() => _temp = v),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Checkbox(
                            value: _makePrimary,
                            onChanged: (v) => setState(() => _makePrimary = v ?? false),
                            activeColor: t.accent,
                          ),
                          Text('Set as primary outfit',
                              style: TextStyle(color: t.textSecondary, fontSize: t.fontSize(11))),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('CANCEL',
                        style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(9))),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.accent.withValues(alpha: 0.2),
                      foregroundColor: t.accent,
                      elevation: 0,
                    ),
                    child: Text('SAVE',
                        style: TextStyle(fontSize: t.fontSize(9), letterSpacing: 1)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _labelled(VisionTokens t, String s) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(s,
            style: TextStyle(
                color: t.textTertiary,
                fontSize: t.fontSize(8),
                letterSpacing: 1.5,
                fontWeight: FontWeight.bold)),
      );

  InputDecoration _inputDeco(VisionTokens t, String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: t.textMinimal, fontSize: t.fontSize(10)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: t.borderSubtle),
          borderRadius: BorderRadius.circular(4),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: t.accent),
          borderRadius: BorderRadius.circular(4),
        ),
      );

  Widget _chips(VisionTokens t, String label, List<String> all, Set<String> selected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelled(t, label),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final v in all)
              FilterChip(
                label: Text(v, style: TextStyle(fontSize: t.fontSize(9))),
                selected: selected.contains(v),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                backgroundColor: t.surfaceMid,
                selectedColor: t.accent.withValues(alpha: 0.25),
                side: BorderSide(
                    color: selected.contains(v) ? t.accent : t.borderSubtle),
                labelStyle: TextStyle(
                    color: selected.contains(v) ? t.accent : t.textTertiary),
                onSelected: (on) => setState(() {
                  if (on) {
                    selected.add(v);
                  } else {
                    selected.remove(v);
                  }
                }),
              ),
          ],
        ),
      ],
    );
  }
}
