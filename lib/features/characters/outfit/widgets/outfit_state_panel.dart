import 'package:flutter/material.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/theme/vision_tokens.dart';
import '../../models/closet_outfit.dart';
import '../outfit_classifier.dart';
import '../outfit_delta.dart';
import '../outfit_renderer.dart';
import '../outfit_slots.dart';

/// The "Wear / state" panel: dresses/undresses a character's outfit via per-slot
/// dropdowns and shows the live Danbooru tags. Pure Dart — no LLM.
///
/// Operates on a working copy of [outfit.items]; emits the mutated outfit back
/// via [onChanged] so the caller can persist it.
class OutfitStatePanel extends StatefulWidget {
  final ClosetOutfit outfit;
  final ValueChanged<ClosetOutfit> onChanged;

  /// Inserts the rendered tag string (+ `nsfw` if dishevelled) into the current
  /// generation prompt at the cursor.
  final void Function(String renderedTags, bool dishevelled) onApplyToPrompt;

  const OutfitStatePanel({
    super.key,
    required this.outfit,
    required this.onChanged,
    required this.onApplyToPrompt,
  });

  @override
  State<OutfitStatePanel> createState() => _OutfitStatePanelState();
}

class _OutfitStatePanelState extends State<OutfitStatePanel> {
  late Map<String, dynamic> _items;

  @override
  void initState() {
    super.initState();
    _items = _ensureItems(widget.outfit);
  }

  @override
  void didUpdateWidget(covariant OutfitStatePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.outfit.id != widget.outfit.id) {
      _items = _ensureItems(widget.outfit);
    }
  }

  Map<String, dynamic> _ensureItems(ClosetOutfit o) {
    final existing = o.items;
    if (existing != null && existing.isNotEmpty) {
      // Deep-ish copy so edits don't mutate the model in place.
      return _deepCopy(existing.cast<String, dynamic>());
    }
    return classifyOutfitTags(o.tags);
  }

  Map<String, dynamic> _deepCopy(Map<String, dynamic> src) {
    Map<String, dynamic> copyMap(Map m) => {
          for (final e in m.entries)
            e.key as String:
                e.value is Map ? copyMap(e.value as Map) : e.value,
        };
    return copyMap(src);
  }

  void _persist() {
    widget.onChanged(widget.outfit.copyWith(items: _deepCopy(_items)));
  }

  void _setSlotState(String slot, String state) {
    final it = _items[slot];
    if (it is! Map<String, dynamic>) return;
    if (it['state'] != state) {
      it['state'] = state;
      it['turns_in_state'] = 0;
    }
    setState(() {});
    _persist();
  }

  void _setDressState(String which, String state) {
    final it = _items['dress'];
    if (it is! Map<String, dynamic>) return;
    final key = which == 'top' ? 'top_state' : 'bottom_state';
    if (it[key] != state) {
      it[key] = state;
      it['turns_in_state'] = 0;
    }
    setState(() {});
    _persist();
  }

  void _setAccessorySubState(String subKey, String state) {
    final acc = _items['accessory'];
    if (acc is! Map<String, dynamic>) return;
    final subs = acc['items'];
    if (subs is! Map) return;
    final sub = subs[subKey];
    if (sub is Map && sub['state'] != state) {
      sub['state'] = state;
      sub['turns_in_state'] = 0;
      // recompute parent
      final states = subs.values
          .map((s) => (s is Map ? (s['state'] as String?) : null) ?? 'intact')
          .toSet();
      acc['state'] = states.length == 1
          ? states.first
          : 'partial';
    }
    setState(() {});
    _persist();
  }

  void _resetIntact() {
    resetItemsToIntact(_items);
    setState(() {});
    _persist();
  }

  void _reparse() {
    _items = classifyOutfitTags(widget.outfit.tags);
    setState(() {});
    _persist();
  }

  // -- Concealment helpers (mirror the renderer's so the panel can grey out
  //    concealed underwear rows) --------------------------------------------
  bool _braConcealed() {
    final rendered = renderItemsToTags(_items); // side-effect free; cheap
    // The renderer doesn't expose concealment directly; re-derive via the same
    // rule: a bra is concealed if it has no row in the rendered output but is
    // present and intact.
    final bra = _items['bra'];
    if (bra is! Map) return false;
    if ((bra['state'] ?? 'intact') != 'intact') return false;
    final base = (bra['base_tags'] as String?) ?? '';
    return base.isNotEmpty && !rendered.tags.contains(base.split(',').first.trim());
  }

  bool _pantiesConcealed() {
    final rendered = renderItemsToTags(_items);
    final p = _items['panties'];
    if (p is! Map) return false;
    if ((p['state'] ?? 'intact') != 'intact') return false;
    final base = (p['base_tags'] as String?) ?? '';
    return base.isNotEmpty && !rendered.tags.contains(base.split(',').first.trim());
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    if (_items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'No classifiable garments in this outfit\'s tags.',
          style: TextStyle(color: t.textTertiary, fontSize: t.fontSize(11)),
        ),
      );
    }
    final rendered = renderItemsToTags(_items);
    final braHidden = _braConcealed();
    final pantiesHidden = _pantiesConcealed();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'OUTFIT STATE',
              style: TextStyle(
                color: t.textSecondary,
                fontSize: t.fontSize(9),
                letterSpacing: 2,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            if (rendered.isDishevelled)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: t.accentDanger.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: t.accentDanger.withValues(alpha: 0.5)),
                ),
                child: Text(
                  'DISHEVELLED',
                  style: TextStyle(
                    color: t.accentDanger,
                    fontSize: t.fontSize(8),
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const Spacer(),
            TextButton(
              onPressed: _resetIntact,
              child: Text('RESET',
                  style: TextStyle(color: t.textTertiary, fontSize: t.fontSize(9))),
            ),
            TextButton(
              onPressed: _reparse,
              child: Text('RE-PARSE',
                  style: TextStyle(color: t.textTertiary, fontSize: t.fontSize(9))),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ...kRenderOrder.where((s) => _items.containsKey(s)).map((slot) {
          final it = _items[slot] as Map<String, dynamic>;
          if (slot == 'dress') return _dressRow(t, it);
          if (slot == 'accessory') return _accessoryRows(t, it);
          final concealed = (slot == 'bra' && braHidden) || (slot == 'panties' && pantiesHidden);
          return _slotRow(t, slot, it, concealed: concealed);
        }),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: t.surfaceMid,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: t.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('→ RENDERED TAGS',
                  style: TextStyle(
                      color: t.textTertiary,
                      fontSize: t.fontSize(8),
                      letterSpacing: 1.5)),
              const SizedBox(height: 4),
              SelectableText(
                rendered.tags.isEmpty ? '(empty)' : rendered.tags,
                style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(11)),
              ),
              if (rendered.isDishevelled)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('+ nsfw',
                      style: TextStyle(
                          color: t.accentDanger, fontSize: t.fontSize(10))),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: () =>
                widget.onApplyToPrompt(rendered.tags, rendered.isDishevelled),
            icon: const Icon(Icons.add, size: 14),
            label: Text('APPLY TO PROMPT', style: TextStyle(fontSize: t.fontSize(9), letterSpacing: 1)),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.accent.withValues(alpha: 0.2),
              foregroundColor: t.accent,
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }

  Widget _slotRow(VisionTokens t, String slot, Map<String, dynamic> it,
      {bool concealed = false}) {
    final garment = (it['garment'] as String?) ?? slot;
    final state = (it['state'] as String?) ?? 'intact';
    final valid = (kValidStates[slot] ?? const {'intact', 'removed'}).toList()
      ..sort((a, b) => kOutfitStates.indexOf(a).compareTo(kOutfitStates.indexOf(b)));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(slot,
                style: TextStyle(
                    color: t.textTertiary,
                    fontSize: t.fontSize(9),
                    letterSpacing: 1)),
          ),
          Expanded(
            child: Text(
              concealed ? '$garment  (concealed)' : garment,
              style: TextStyle(
                color: concealed ? t.textMinimal : t.textPrimary,
                fontSize: t.fontSize(11),
                fontStyle: concealed ? FontStyle.italic : FontStyle.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _stateDropdown(t, state, valid,
              onChanged: concealed ? null : (v) => _setSlotState(slot, v)),
        ],
      ),
    );
  }

  Widget _dressRow(VisionTokens t, Map<String, dynamic> it) {
    final garment = (it['garment'] as String?) ?? 'dress';
    final topState = (it['top_state'] as String?) ?? 'intact';
    final botState = (it['bottom_state'] as String?) ?? 'intact';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 78,
                child: Text('dress',
                    style: TextStyle(
                        color: t.textTertiary,
                        fontSize: t.fontSize(9),
                        letterSpacing: 1)),
              ),
              Expanded(
                child: Text(garment,
                    style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(11)),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 86, top: 4),
            child: Row(
              children: [
                Text('top', style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(9))),
                const SizedBox(width: 6),
                _stateDropdown(t, topState, kValidDressTopStates.toList(),
                    onChanged: (v) => _setDressState('top', v)),
                const SizedBox(width: 16),
                Text('bottom', style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(9))),
                const SizedBox(width: 6),
                _stateDropdown(t, botState, kValidDressBottomStates.toList(),
                    onChanged: (v) => _setDressState('bottom', v)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _accessoryRows(VisionTokens t, Map<String, dynamic> it) {
    final subs = it['items'];
    if (subs is! Map || subs.isEmpty) {
      return _slotRow(t, 'accessory', it);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in subs.entries.cast<MapEntry<String, dynamic>>())
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 78,
                  child: Text('accessory',
                      style: TextStyle(
                          color: t.textTertiary, fontSize: t.fontSize(8), letterSpacing: 1)),
                ),
                Expanded(
                  child: Text(entry.key,
                      style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(11)),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                _stateDropdown(
                  t,
                  (entry.value is Map ? (entry.value['state'] as String?) : null) ?? 'intact',
                  const ['intact', 'removed'],
                  onChanged: (v) => _setAccessorySubState(entry.key, v),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _stateDropdown(VisionTokens t, String value, List<String> options,
      {ValueChanged<String>? onChanged}) {
    final items = options.contains(value) ? options : [value, ...options];
    return DropdownButton<String>(
      value: value,
      isDense: true,
      underline: const SizedBox.shrink(),
      style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(10)),
      dropdownColor: t.surfaceHigh,
      onChanged: onChanged == null ? null : (v) { if (v != null) onChanged(v); },
      items: [
        for (final o in items)
          DropdownMenuItem(
            value: o,
            child: Text(kStateLabels[o] ?? o,
                style: TextStyle(
                    color: o == 'intact' ? t.textSecondary : t.accentEdit,
                    fontSize: t.fontSize(10))),
          ),
      ],
    );
  }
}
