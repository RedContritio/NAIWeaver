/// Outfit slot model, valid (slot, state) combinations, and helper enums.
///
/// Ported from bri.'s `app/outfit_slots.py`. The per-item state is stored as a
/// `Map<String, dynamic>` so it serializes straight to/from JSON in
/// `closet.json`. See [classifyOutfitTags] (outfit_classifier.dart) for how a
/// flat Danbooru tag string becomes a `{slot: itemMap}` structure, and
/// [renderItemsToTags] (outfit_renderer.dart) for the reverse.
library;

/// The ten clothing slots. `dress` is special — it has no single state; it
/// carries `topState` + `bottomState` that move independently. `accessory`
/// tracks per-sub-item state plus a derived parent state.
const List<String> kOutfitSlots = <String>[
  'outerwear',
  'armor',
  'top',
  'dress',
  'bottom',
  'bra',
  'panties',
  'legwear',
  'footwear',
  'headwear',
  'accessory',
];

/// The verb-ish state enum for single-state slots.
const List<String> kOutfitStates = <String>[
  'intact',
  'unbuttoned', // top: some buttons undone
  'open', // top/outerwear: fully open, hanging
  'lifted', // skirt/shirt pushed up
  'pulled_down', // pants/panties/bra pulled down
  'aside', // panties/bikini/bra pulled to one side
  'around_ankles', // panties/pants tangled at feet
  'removed', // gone entirely
];

/// Per-slot valid state sets. A `(slot, state)` pair must be in here or it is
/// rejected (e.g. "skirt unbuttoned" is nonsense — `bottom` allows `unbuttoned`
/// only for pants, but we keep it permissive at the slot level and let the
/// renderer drop the verb tag for skirts).
const Map<String, Set<String>> kValidStates = <String, Set<String>>{
  'top': {'intact', 'unbuttoned', 'open', 'lifted', 'removed'},
  'bottom': {
    'intact',
    'unbuttoned',
    'lifted',
    'pulled_down',
    'around_ankles',
    'removed'
  },
  'bra': {'intact', 'pulled_down', 'aside', 'removed'},
  'panties': {'intact', 'pulled_down', 'aside', 'around_ankles', 'removed'},
  'outerwear': {'intact', 'unbuttoned', 'open', 'removed'},
  'armor': {'intact', 'removed'},
  'legwear': {'intact', 'pulled_down', 'around_ankles', 'removed'},
  'footwear': {'intact', 'removed'},
  'headwear': {'intact', 'removed'},
  'accessory': {'intact', 'removed'}, // per-sub-item
};

/// Dress has two independent state fields.
const Set<String> kValidDressTopStates = <String>{
  'intact',
  'unbuttoned',
  'open',
  'pulled_down',
  'removed',
};
const Set<String> kValidDressBottomStates = <String>{
  'intact',
  'lifted',
  'aside',
  'removed',
};

/// Slots whose non-intact, visible state makes the look "dishevelled" (→ append
/// `nsfw` to the prompt). Armor is intentionally excluded — a knight unbuckling
/// a cuirass is just disarming.
const Set<String> kNsfwTriggeringSlots = <String>{
  'top',
  'bottom',
  'dress',
  'bra',
  'panties',
  'legwear',
};

/// Render order for the output tag string — keeps NovelAI output stable. Armor
/// renders after `top` so the visual stack reads outerwear → armor → top.
const List<String> kRenderOrder = <String>[
  'outerwear',
  'armor',
  'top',
  'dress',
  'bottom',
  'bra',
  'panties',
  'legwear',
  'footwear',
  'headwear',
  'accessory',
];

/// Priority order for ambiguous substring matches ("sports bra" beats "bra").
/// More specific slots first.
const List<String> kSlotPriority = <String>[
  'dress',
  'armor',
  'outerwear',
  'bra',
  'panties',
  'top',
  'bottom',
  'legwear',
  'footwear',
  'headwear',
  'accessory',
];

/// Slot-level nudity tag emitted when a slot is fully `removed`. Dress is
/// handled specially (per-half topless/bottomless).
const Map<String, String> kRemovedNudityTag = <String, String>{
  'top': 'topless',
  'bottom': 'bottomless',
  'bra': 'no bra',
  'panties': 'no panties',
  'outerwear': '',
  'armor': '',
  'legwear': '',
  'footwear': 'barefoot',
  'headwear': '',
  'accessory': '',
};

/// Turns a non-intact slot can sit before a redress nudge would fire. We track
/// `turnsInState` but the auto-force-redress is a TODO (see outfit_delta.dart).
const int kDishevelmentDecayTurns = 4;

/// Human-readable labels for states (UI dropdowns / status strip).
const Map<String, String> kStateLabels = <String, String>{
  'intact': 'intact',
  'unbuttoned': 'unbuttoned',
  'open': 'open',
  'lifted': 'lifted',
  'pulled_down': 'pulled down',
  'aside': 'pulled aside',
  'around_ankles': 'around ankles',
  'removed': 'removed',
};

/// Tone bucket per state — UI can map these to badge colours without
/// hard-coding the enum.
const Map<String, String> kStateTone = <String, String>{
  'intact': 'neutral',
  'unbuttoned': 'minor',
  'open': 'minor',
  'lifted': 'moderate',
  'pulled_down': 'moderate',
  'aside': 'moderate',
  'around_ankles': 'strong',
  'removed': 'strong',
};

bool isValidStateFor(String slot, String state) {
  if (slot == 'dress') return false; // dress uses topState/bottomState
  return kValidStates[slot]?.contains(state) ?? false;
}

/// True if [item] (the per-slot map) is in any non-intact state.
bool itemIsNonIntact(String slot, Map<String, dynamic> item) {
  if (slot == 'dress') {
    return (item['top_state'] ?? 'intact') != 'intact' ||
        (item['bottom_state'] ?? 'intact') != 'intact';
  }
  if (slot == 'accessory') {
    final subs = item['items'];
    if (subs is Map && subs.isNotEmpty) {
      return subs.values
          .any((s) => (s is Map ? (s['state'] ?? 'intact') : 'intact') != 'intact');
    }
  }
  return (item['state'] ?? 'intact') != 'intact';
}

/// True if any item in [items] is non-intact.
bool anyNonIntact(Map<String, dynamic> items) {
  for (final entry in items.entries) {
    final v = entry.value;
    if (v is Map<String, dynamic> && itemIsNonIntact(entry.key, v)) return true;
  }
  return false;
}

/// A presentational entry for the dashboard status strip.
class OutfitStateEntry {
  final String slot;
  final String garment;
  final String state;
  final String label;
  final String tone;

  const OutfitStateEntry({
    required this.slot,
    required this.garment,
    required this.state,
    required this.label,
    required this.tone,
  });
}

OutfitStateEntry _stateEntry(String slot, String garment, String state) =>
    OutfitStateEntry(
      slot: slot,
      garment: garment.isEmpty ? slot : garment,
      state: state,
      label: kStateLabels[state] ?? state,
      tone: kStateTone[state] ?? 'moderate',
    );

/// Returns a list of non-intact slots for dashboard UI. Empty list ⇒ fully
/// dressed. Dress reports up to two entries; accessory reports per sub-item.
List<OutfitStateEntry> formatStateStrip(Map<String, dynamic>? items) {
  if (items == null) return const [];
  final strip = <OutfitStateEntry>[];
  for (final slot in kRenderOrder) {
    final it = items[slot];
    if (it is! Map<String, dynamic>) continue;
    if (slot == 'dress') {
      final garment = (it['garment'] as String?) ?? 'dress';
      final topState = (it['top_state'] as String?) ?? 'intact';
      final botState = (it['bottom_state'] as String?) ?? 'intact';
      if (topState != 'intact') {
        strip.add(_stateEntry('dress (top)', garment, topState));
      }
      if (botState != 'intact') {
        strip.add(_stateEntry('dress (bottom)', garment, botState));
      }
      continue;
    }
    if (slot == 'accessory' && it['items'] is Map) {
      final subs = (it['items'] as Map).cast<String, dynamic>();
      subs.forEach((subKey, sub) {
        final s = (sub is Map ? (sub['state'] as String?) : null) ?? 'intact';
        if (s != 'intact') {
          strip.add(_stateEntry('accessory ($subKey)', subKey, s));
        }
      });
      continue;
    }
    final state = (it['state'] as String?) ?? 'intact';
    if (state == 'intact') continue;
    strip.add(_stateEntry(slot, (it['garment'] as String?) ?? '', state));
  }
  return strip;
}
