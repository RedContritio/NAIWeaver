import 'package:flutter/material.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/theme/vision_metrics.dart';
import '../../../../core/theme/vision_tokens.dart';
import '../../../../core/widgets/browser_native_selectable_text.dart';
import '../../../../core/widgets/ui/app_panel.dart';
import '../../../../core/widgets/ui/app_pill.dart';
import '../../../../core/widgets/ui/app_sheet.dart';
import '../../../../core/widgets/ui/app_tone.dart';
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
        e.key as String: e.value is Map ? copyMap(e.value as Map) : e.value,
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
    return base.isNotEmpty &&
        !rendered.tags.contains(base.split(',').first.trim());
  }

  bool _pantiesConcealed() {
    final rendered = renderItemsToTags(_items);
    final p = _items['panties'];
    if (p is! Map) return false;
    if ((p['state'] ?? 'intact') != 'intact') return false;
    final base = (p['base_tags'] as String?) ?? '';
    return base.isNotEmpty &&
        !rendered.tags.contains(base.split(',').first.trim());
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    if (_items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(VisionMetrics.space12),
        child: Text(
          l.charsStateNoGarments,
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
              l.charsOutfitState.toUpperCase(),
              style: TextStyle(
                color: t.textSecondary,
                fontSize: t.fontSize(9),
                letterSpacing: 2,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: VisionMetrics.space8),
            if (rendered.isDishevelled)
              AppPill(
                text: l.charsDishevelled.toUpperCase(),
                tone: AppTone.error,
                dense: true,
              ),
            const Spacer(),
            PopupMenuButton<String>(
              tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
              icon: Icon(
                Icons.more_horiz,
                size: VisionMetrics.iconMedium,
                color: t.textTertiary,
              ),
              padding: EdgeInsets.zero,
              onSelected: (v) {
                if (v == 'reset') _resetIntact();
                if (v == 'reparse') _reparse();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'reset',
                  child: Row(
                    children: [
                      Icon(
                        Icons.refresh,
                        size: VisionMetrics.iconSmall,
                        color: t.textTertiary,
                      ),
                      const SizedBox(width: VisionMetrics.space8),
                      Text(
                        l.charsResetIntact,
                        style: TextStyle(fontSize: t.fontSize(11)),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'reparse',
                  child: Row(
                    children: [
                      Icon(
                        Icons.find_replace,
                        size: VisionMetrics.iconSmall,
                        color: t.textTertiary,
                      ),
                      const SizedBox(width: VisionMetrics.space8),
                      Text(
                        l.charsReparse,
                        style: TextStyle(fontSize: t.fontSize(11)),
                      ),
                    ],
                  ),
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
              (slot == 'bra' && braHidden) ||
              (slot == 'panties' && pantiesHidden);
          return _garmentCard(t, slot, it, concealed: concealed);
        }),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: AppPanel(
            variant: AppPanelVariant.outlined,
            padding: const EdgeInsets.all(VisionMetrics.space8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '→ ${l.charsRenderedTags.toUpperCase()}',
                  style: TextStyle(
                    color: t.textTertiary,
                    fontSize: t.fontSize(8),
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                BrowserNativeSelectableText(
                  text: rendered.tags.isEmpty
                      ? l.charsEmptyValue
                      : rendered.tags,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: t.fontSize(11),
                  ),
                ),
                if (rendered.isDishevelled)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '+ nsfw', // l10n-ignore: prompt tag shown as rendered
                      style: TextStyle(
                        color: t.accentDanger,
                        fontSize: t.fontSize(10),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: VisionMetrics.space8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () =>
                widget.onApplyToPrompt(rendered.tags, rendered.isDishevelled),
            icon: const Icon(Icons.add, size: VisionMetrics.iconSmall),
            label: Text(
              (widget.persistent ? l.charsApplyToPrompt : l.charsUseTheseTags)
                  .toUpperCase(),
              style: TextStyle(fontSize: t.fontSize(10), letterSpacing: 1),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.accent.withValues(
                alpha: VisionMetrics.opacityPressed,
              ),
              foregroundColor: t.accent,
              elevation: 0,
              minimumSize: Size.fromHeight(context.hitSize),
            ),
          ),
        ),
      ],
    );
  }

  // -- Garment card variants ------------------------------------------------

  Widget _garmentCard(
    VisionTokens t,
    String slot,
    Map<String, dynamic> it, {
    bool concealed = false,
  }) {
    final garment = (it['garment'] as String?) ?? slot;
    final state = (it['state'] as String?) ?? 'intact';
    final valid = (kValidStates[slot] ?? const {'intact', 'removed'}).toList()
      ..sort(
        (a, b) => kOutfitStates.indexOf(a).compareTo(kOutfitStates.indexOf(b)),
      );
    return _cardShell(
      t,
      slotLabel: slot,
      garmentLabel: concealed
          ? '$garment  (${context.l.charsConcealed})'
          : garment,
      concealed: concealed,
      trailing: _statePill(
        t,
        state: state,
        validStates: valid,
        onTap: concealed
            ? null
            : () => _pickState(
                slot: slot,
                current: state,
                valid: valid,
                onChosen: (v) => _setSlotState(slot, v),
              ),
      ),
    );
  }

  Widget _dressCard(VisionTokens t, Map<String, dynamic> it) {
    final garment = (it['garment'] as String?) ?? 'dress';
    final topState = (it['top_state'] as String?) ?? 'intact';
    final botState = (it['bottom_state'] as String?) ?? 'intact';
    final topValid = kValidDressTopStates.toList()
      ..sort(
        (a, b) => kOutfitStates.indexOf(a).compareTo(kOutfitStates.indexOf(b)),
      );
    final botValid = kValidDressBottomStates.toList()
      ..sort(
        (a, b) => kOutfitStates.indexOf(a).compareTo(kOutfitStates.indexOf(b)),
      );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: VisionMetrics.radius2),
      child: AppPanel(
        variant: AppPanelVariant.inset,
        padding: const EdgeInsets.all(VisionMetrics.space8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l.charsDress,
              style: TextStyle(
                color: t.textTertiary,
                fontSize: t.fontSize(8),
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              garment,
              style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(12)),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _labelledPill(
                  t,
                  prefix: '↑ ${context.l.charsTopPrefix.toUpperCase()}',
                  state: topState,
                  onTap: () => _pickState(
                    slot: '${context.l.charsDress} (${context.l.charsTopPrefix})',
                    current: topState,
                    valid: topValid,
                    onChosen: (v) => _setDressState('top', v),
                  ),
                ),
                _labelledPill(
                  t,
                  prefix: '↓ ${context.l.charsBottomPrefix.toUpperCase()}',
                  state: botState,
                  onTap: () => _pickState(
                    slot: '${context.l.charsDress} (${context.l.charsBottomPrefix})',
                    current: botState,
                    valid: botValid,
                    onChosen: (v) => _setDressState('bottom', v),
                  ),
                ),
              ],
            ),
          ],
        ),
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
              state:
                  (entry.value is Map
                      ? (entry.value['state'] as String?)
                      : null) ??
                  'intact',
              validStates: const ['intact', 'removed'],
              onTap: () => _pickState(
                slot: 'accessory',
                current:
                    (entry.value is Map
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

  Widget _cardShell(
    VisionTokens t, {
    required String slotLabel,
    required String garmentLabel,
    required Widget trailing,
    bool concealed = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: VisionMetrics.radius2),
      child: AppPanel(
        variant: AppPanelVariant.inset,
        padding: const EdgeInsets.all(VisionMetrics.space8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    slotLabel,
                    style: TextStyle(
                      color: t.textTertiary,
                      fontSize: t.fontSize(8),
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    garmentLabel,
                    style: TextStyle(
                      color: concealed ? t.textMinimal : t.textPrimary,
                      fontSize: t.fontSize(12),
                      fontStyle: concealed
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: VisionMetrics.space8),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget _statePill(
    VisionTokens t, {
    required String state,
    required List<String> validStates,
    VoidCallback? onTap,
  }) {
    return AppPill(
      text: kStateLabels[state] ?? state,
      tone: _tone(kStateTone[state] ?? 'neutral'),
      onTap: onTap,
    );
  }

  Widget _labelledPill(
    VisionTokens t, {
    required String prefix,
    required String state,
    required VoidCallback onTap,
  }) {
    return AppPill(
      text: '$prefix  ${kStateLabels[state] ?? state}',
      tone: _tone(kStateTone[state] ?? 'neutral'),
      onTap: onTap,
    );
  }

  AppTone _tone(String tone) {
    switch (tone) {
      case 'minor':
        return AppTone.info;
      case 'moderate':
        return AppTone.warning;
      case 'strong':
        return AppTone.error;
      case 'neutral':
      default:
        return AppTone.neutral;
    }
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
    final chosen = await showAppSheet<String>(
      context: context,
      builder: (ctx) {
        final t = ctx.t;
        return AppPickerSheet(
          title: slot,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final s in valid)
                ListTile(
                  onTap: () => Navigator.of(ctx).pop(s),
                  leading: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _toneColor(t, kStateTone[s] ?? 'neutral'),
                      borderRadius: BorderRadius.circular(
                        VisionMetrics.radius2,
                      ),
                    ),
                  ),
                  title: Text(
                    kStateLabels[s] ?? s,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: t.fontSize(13),
                      fontWeight: s == current
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  trailing: s == current
                      ? Icon(
                          Icons.check,
                          size: VisionMetrics.iconMedium,
                          color: t.accent,
                        )
                      : null,
                ),
            ],
          ),
        );
      },
    );
    if (chosen != null && chosen != current) onChosen(chosen);
  }
}
