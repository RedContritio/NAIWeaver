import 'package:flutter/material.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/theme/vision_tokens.dart';
import '../../models/closet_outfit.dart';
import '../outfit_classifier.dart';
import '../outfit_delta.dart';
import '../outfit_renderer.dart';
import '../outfit_slots.dart';

/// The "Wear / state" panel: dresses/undresses a character's outfit via per-slot
/// state pills and shows the live Danbooru tags. Pure Dart — no LLM.
///
/// Operates on a working copy of [outfit.items]; emits the mutated outfit back
/// via [onChanged]. When [persistent] is true (default) the consumer is
/// expected to write changes through to storage; when false the panel is a
/// session-only working copy (used by the photoshoot screen).
class OutfitStatePanel extends StatefulWidget {
  final ClosetOutfit outfit;
  final ValueChanged<ClosetOutfit> onChanged;

  /// Inserts the rendered tag string (+ `nsfw` if dishevelled) into the current
  /// generation prompt at the cursor.
  final void Function(String renderedTags, bool dishevelled) onApplyToPrompt;

  /// When true (default) onChanged is expected to persist. When false the
  /// consumer treats edits as ephemeral. Behaviourally identical inside this
  /// widget; the flag is informational for callers and shifts the trailing
  /// button label from "APPLY TO PROMPT" to a slightly more verbose "USE
  /// THESE TAGS" prompt that fits the photoshoot flow.
  final bool persistent;

  const OutfitStatePanel({
    super.key,
    required this.outfit,
    required this.onChanged,
    required this.onApplyToPrompt,
    this.persistent = true,
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
      final states = subs.values
          .map((s) => (s is Map ? (s['state'] as String?) : null) ?? 'intact')
          .toSet();
      acc['state'] = states.length == 1 ? states.first : 'partial';
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

  // -- Concealment helpers (mirror the renderer's so the panel can dim concealed
  //    underwear rows). The renderer doesn't expose concealment directly, so we
  //    re-derive via the same rule: a bra is concealed if it has no row in the
  //    rendered output but is present and intact.
  bool _braConcealed() {
    final rendered = renderItemsToTags(_items);
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
        // Header — title + DISHEVELLED badge + overflow menu (RESET / RE-PARSE).
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
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: Icon(Icons.more_horiz, size: 18, color: t.textTertiary),
              padding: EdgeInsets.zero,
              onSelected: (v) {
                if (v == 'reset') _resetIntact();
                if (v == 'reparse') _reparse();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'reset',
                  child: Row(children: [
                    Icon(Icons.refresh, size: 14, color: t.textTertiary),
                    const SizedBox(width: 8),
                    Text('Reset to intact', style: TextStyle(fontSize: t.fontSize(11))),
                  ]),
                ),
                PopupMenuItem(
                  value: 'reparse',
                  child: Row(children: [
                    Icon(Icons.find_replace, size: 14, color: t.textTertiary),
                    const SizedBox(width: 8),
                    Text('Re-parse from tags', style: TextStyle(fontSize: t.fontSize(11))),
                  ]),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        ...kRenderOrder.where((s) => _items.containsKey(s)).map((slot) {
          final it = _items[slot] as Map<String, dynamic>;
          if (slot == 'dress') return _dressCard(t, it);
          if (slot == 'accessory') return _accessoryCards(t, it);
          final concealed =
              (slot == 'bra' && braHidden) || (slot == 'panties' && pantiesHidden);
          return _garmentCard(t, slot, it, concealed: concealed);
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
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () =>
                widget.onApplyToPrompt(rendered.tags, rendered.isDishevelled),
            icon: const Icon(Icons.add, size: 14),
            label: Text(widget.persistent ? 'APPLY TO PROMPT' : 'USE THESE TAGS',
                style: TextStyle(fontSize: t.fontSize(10), letterSpacing: 1)),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.accent.withValues(alpha: 0.2),
              foregroundColor: t.accent,
              elevation: 0,
              minimumSize: const Size.fromHeight(40),
            ),
          ),
        ),
      ],
    );
  }

  // -- Garment card variants ------------------------------------------------

  Widget _garmentCard(VisionTokens t, String slot, Map<String, dynamic> it,
      {bool concealed = false}) {
    final garment = (it['garment'] as String?) ?? slot;
    final state = (it['state'] as String?) ?? 'intact';
    final valid = (kValidStates[slot] ?? const {'intact', 'removed'}).toList()
      ..sort((a, b) => kOutfitStates.indexOf(a).compareTo(kOutfitStates.indexOf(b)));
    return _cardShell(
      t,
      slotLabel: slot,
      garmentLabel: concealed ? '$garment  (concealed)' : garment,
      concealed: concealed,
      trailing: _statePill(
        t,
        state: state,
        validStates: valid,
        onTap: concealed
            ? null
            : () => _pickState(slot: slot, current: state, valid: valid,
                onChosen: (v) => _setSlotState(slot, v)),
      ),
    );
  }

  Widget _dressCard(VisionTokens t, Map<String, dynamic> it) {
    final garment = (it['garment'] as String?) ?? 'dress';
    final topState = (it['top_state'] as String?) ?? 'intact';
    final botState = (it['bottom_state'] as String?) ?? 'intact';
    final topValid = kValidDressTopStates.toList()
      ..sort((a, b) => kOutfitStates.indexOf(a).compareTo(kOutfitStates.indexOf(b)));
    final botValid = kValidDressBottomStates.toList()
      ..sort((a, b) => kOutfitStates.indexOf(a).compareTo(kOutfitStates.indexOf(b)));
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: t.surfaceMid.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('dress',
              style: TextStyle(
                  color: t.textTertiary,
                  fontSize: t.fontSize(8),
                  letterSpacing: 1.5)),
          const SizedBox(height: 2),
          Text(garment,
              style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(12)),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _labelledPill(
                t,
                prefix: '↑ TOP',
                state: topState,
                onTap: () => _pickState(
                  slot: 'dress (top)',
                  current: topState,
                  valid: topValid,
                  onChosen: (v) => _setDressState('top', v),
                ),
              ),
              _labelledPill(
                t,
                prefix: '↓ BOT',
                state: botState,
                onTap: () => _pickState(
                  slot: 'dress (bottom)',
                  current: botState,
                  valid: botValid,
                  onChosen: (v) => _setDressState('bottom', v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _accessoryCards(VisionTokens t, Map<String, dynamic> it) {
    final subs = it['items'];
    if (subs is! Map || subs.isEmpty) {
      return _garmentCard(t, 'accessory', it);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in subs.entries.cast<MapEntry<String, dynamic>>())
          _cardShell(
            t,
            slotLabel: 'accessory',
            garmentLabel: entry.key,
            trailing: _statePill(
              t,
              state: (entry.value is Map
                      ? (entry.value['state'] as String?)
                      : null) ??
                  'intact',
              validStates: const ['intact', 'removed'],
              onTap: () => _pickState(
                slot: 'accessory',
                current: (entry.value is Map
                        ? (entry.value['state'] as String?)
                        : null) ??
                    'intact',
                valid: const ['intact', 'removed'],
                onChosen: (v) => _setAccessorySubState(entry.key, v),
              ),
            ),
          ),
      ],
    );
  }

  // -- Visual primitives ----------------------------------------------------

  Widget _cardShell(VisionTokens t,
      {required String slotLabel,
      required String garmentLabel,
      required Widget trailing,
      bool concealed = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: t.surfaceMid.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(slotLabel,
                    style: TextStyle(
                        color: t.textTertiary,
                        fontSize: t.fontSize(8),
                        letterSpacing: 1.5)),
                const SizedBox(height: 2),
                Text(
                  garmentLabel,
                  style: TextStyle(
                    color: concealed ? t.textMinimal : t.textPrimary,
                    fontSize: t.fontSize(12),
                    fontStyle:
                        concealed ? FontStyle.italic : FontStyle.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }

  Widget _statePill(VisionTokens t,
      {required String state,
      required List<String> validStates,
      VoidCallback? onTap}) {
    final tone = kStateTone[state] ?? 'neutral';
    final color = _toneColor(t, tone);
    final label = kStateLabels[state] ?? state;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        constraints: const BoxConstraints(minHeight: 32, minWidth: 88),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: t.fontSize(10),
                    fontWeight: FontWeight.w600)),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.expand_more, size: 14, color: color.withValues(alpha: 0.7)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _labelledPill(VisionTokens t,
      {required String prefix,
      required String state,
      required VoidCallback onTap}) {
    final tone = kStateTone[state] ?? 'neutral';
    final color = _toneColor(t, tone);
    final label = kStateLabels[state] ?? state;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(prefix,
                style: TextStyle(
                    color: color.withValues(alpha: 0.8),
                    fontSize: t.fontSize(9),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: t.fontSize(10),
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(Icons.expand_more, size: 14, color: color.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }

  Color _toneColor(VisionTokens t, String tone) {
    switch (tone) {
      case 'minor':
        return t.accentEdit;
      case 'moderate':
        return t.accentFavorite;
      case 'strong':
        return t.accentDanger;
      case 'neutral':
      default:
        return t.textSecondary;
    }
  }

  /// Bottom-sheet picker for a slot's state — large tap targets, tone-coloured.
  Future<void> _pickState({
    required String slot,
    required String current,
    required List<String> valid,
    required ValueChanged<String> onChosen,
  }) async {
    final t = context.tRead;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: t.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Text(slot.toUpperCase(),
                    style: TextStyle(
                        color: t.textTertiary,
                        fontSize: t.fontSize(9),
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold)),
              ),
              for (final s in valid)
                InkWell(
                  onTap: () => Navigator.of(ctx).pop(s),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: t.borderSubtle),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _toneColor(t, kStateTone[s] ?? 'neutral'),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(kStateLabels[s] ?? s,
                              style: TextStyle(
                                  color: t.textPrimary,
                                  fontSize: t.fontSize(13),
                                  fontWeight: s == current
                                      ? FontWeight.bold
                                      : FontWeight.normal)),
                        ),
                        if (s == current)
                          Icon(Icons.check, size: 18, color: t.accent),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (chosen != null && chosen != current) onChosen(chosen);
  }
}
