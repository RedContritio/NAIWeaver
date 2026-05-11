/// Outfit-state delta application + reset helpers.
///
/// Ported from bri.'s `apply_outfit_delta` / `filter_fresh_delta` /
/// `reset_items_to_intact` in `app/outfit_slots.py`. Mainly used by Phase B /
/// future stateful flows; the manual outfit-state panel sets states directly.
///
/// A delta is `{slot: {state: "...", mentioned: bool}}` (dress:
/// `{top_state, bottom_state}`; accessory: `{state}` or `{items: {key: {state}}}`).
///
/// NOTE: decay-redress / snapshot-redress from bri. is intentionally NOT ported
/// yet — `turns_in_state` is tracked but the auto-force-redress is a TODO.
library;

import 'package:flutter/foundation.dart';
import 'outfit_slots.dart';

/// Removal-type transitions that get scrubbed from the first delta after an
/// outfit swap (the LLM may have narrated the previous outfit coming off).
const Set<String> _freshDropStates = <String>{
  'removed',
  'pulled_down',
  'around_ankles',
  'aside',
  'lifted',
};

/// Strip removal-type transitions from a delta applied to a just-set outfit.
/// Returns a new map (does not mutate the input). Entries left with only
/// metadata (e.g. `mentioned`) are dropped.
Map<String, dynamic> filterFreshDelta(Map<String, dynamic>? delta) {
  if (delta == null) return <String, dynamic>{};
  final out = <String, dynamic>{};
  delta.forEach((slot, change) {
    if (change is! Map) return;
    final c = change.cast<String, dynamic>();
    if (slot == 'dress') {
      final cleaned = Map<String, dynamic>.from(c);
      if (_freshDropStates.contains(cleaned['top_state'])) {
        cleaned.remove('top_state');
      }
      if (_freshDropStates.contains(cleaned['bottom_state'])) {
        cleaned.remove('bottom_state');
      }
      if (cleaned.containsKey('top_state') ||
          cleaned.containsKey('bottom_state')) {
        out[slot] = cleaned;
      }
    } else if (slot == 'accessory') {
      final cleaned = Map<String, dynamic>.from(c);
      if (_freshDropStates.contains(cleaned['state'])) cleaned.remove('state');
      final sub = cleaned['items'];
      if (sub is Map) {
        final subClean = <String, dynamic>{};
        sub.forEach((k, v) {
          if (!(v is Map && _freshDropStates.contains(v['state']))) {
            subClean[k as String] = v;
          }
        });
        if (subClean.isNotEmpty) {
          cleaned['items'] = subClean;
        } else {
          cleaned.remove('items');
        }
      }
      if (cleaned.containsKey('state') || cleaned.containsKey('items')) {
        out[slot] = cleaned;
      }
    } else {
      if (_freshDropStates.contains(c['state'])) return;
      out[slot] = c;
    }
  });
  return out;
}

void _ensureAccessorySubitems(Map<String, dynamic> item) {
  if (item['items'] is Map) return;
  final base = ((item['base_tags'] as String?) ?? (item['garment'] as String?) ?? '');
  final parentState = (item['state'] as String?) ?? 'intact';
  final parentTurns = item['turns_in_state'] ?? 0;
  final parentMention = item['last_mentioned_turn'] ?? 0;
  final subs = <String, dynamic>{};
  for (final raw in base.split(',').map((t) => t.trim())) {
    if (raw.isEmpty) continue;
    subs[raw] = <String, dynamic>{
      'state': (parentState == 'intact' || parentState == 'removed')
          ? parentState
          : 'intact',
      'turns_in_state': parentTurns,
      'last_mentioned_turn': parentMention,
    };
  }
  item['items'] = subs;
}

String? _findAccessorySubitem(Map<String, dynamic> items, String key) {
  final k = key.trim().toLowerCase();
  if (k.isEmpty) return null;
  if (items.containsKey(k)) return k;
  for (final fullKey in items.keys) {
    if (k.contains(fullKey) || fullKey.contains(k)) return fullKey;
  }
  final kWords = k.split(' ').where((w) => w.length > 2).toSet();
  if (kWords.isEmpty) return null;
  String? best;
  var bestOverlap = 0;
  for (final fullKey in items.keys) {
    final overlap = kWords
        .intersection(fullKey.split(' ').where((w) => w.length > 2).toSet())
        .length;
    if (overlap > 0 && (best == null || overlap > bestOverlap)) {
      best = fullKey;
      bestOverlap = overlap;
    }
  }
  return best;
}

void _recalcAccessoryParentState(Map<String, dynamic> item) {
  final subs = item['items'];
  if (subs is! Map || subs.isEmpty) return;
  final states = subs.values
      .map((s) => (s is Map ? (s['state'] as String?) : null) ?? 'intact')
      .toSet();
  if (states.length == 1 && states.first == 'intact') {
    item['state'] = 'intact';
  } else if (states.length == 1 && states.first == 'removed') {
    item['state'] = 'removed';
  } else {
    item['state'] = 'partial';
  }
}

/// If the delta says `top:removed` while an intact outerwear exists and the
/// outerwear isn't itself being changed → reroute to `outerwear:removed`
/// (the LLM almost certainly meant the outer layer). Returns a new map.
Map<String, dynamic> _rerouteOuterForTop(
    Map<String, dynamic> items, Map<String, dynamic> delta) {
  final topChange = delta['top'];
  if (topChange is! Map) return delta;
  if (topChange['state'] != 'removed') return delta;
  final outerwear = items['outerwear'];
  if (outerwear is! Map<String, dynamic> ||
      (outerwear['state'] ?? 'intact') != 'intact') {
    return delta;
  }
  if (delta.containsKey('outerwear')) return delta;
  if (kDebugMode) {
    debugPrint(
        'outfit_delta: rerouting top:removed → outerwear:removed (intact outerwear present)');
  }
  final rerouted = Map<String, dynamic>.from(delta);
  rerouted.remove('top');
  rerouted['outerwear'] = <String, dynamic>{
    'state': 'removed',
    'mentioned': (topChange['mentioned'] as bool?) ?? true,
  };
  return rerouted;
}

/// Apply per-slot state changes to [items] in place.
void applyOutfitDelta(
    Map<String, dynamic> items, Map<String, dynamic>? deltaIn, int turnNo) {
  if (deltaIn == null) return;
  final delta = _rerouteOuterForTop(items, deltaIn);

  final stateReset = <String>{};

  delta.forEach((slot, change) {
    if (!items.containsKey(slot)) {
      if (kDebugMode) debugPrint('outfit_delta: unknown slot $slot');
      return;
    }
    if (change is! Map) {
      if (kDebugMode) debugPrint('outfit_delta: non-dict change for $slot');
      return;
    }
    final it = items[slot] as Map<String, dynamic>;
    final c = change.cast<String, dynamic>();

    if (slot == 'dress') {
      final newTop = c['top_state'] as String?;
      final newBot = c['bottom_state'] as String?;
      var changed = false;
      if (newTop != null) {
        if (!kValidDressTopStates.contains(newTop)) {
          if (kDebugMode) {
            debugPrint('outfit_delta: invalid dress top_state $newTop');
          }
        } else if (newTop != it['top_state']) {
          it['top_state'] = newTop;
          changed = true;
        }
      }
      if (newBot != null) {
        if (!kValidDressBottomStates.contains(newBot)) {
          if (kDebugMode) {
            debugPrint('outfit_delta: invalid dress bottom_state $newBot');
          }
        } else if (newBot != it['bottom_state']) {
          it['bottom_state'] = newBot;
          changed = true;
        }
      }
      if (changed) {
        it['turns_in_state'] = 0;
        stateReset.add(slot);
      }
    } else if (slot == 'accessory') {
      _ensureAccessorySubitems(it);
      final subDelta = c['items'];
      var anyChanged = false;
      final subReset = <String>{};
      final subItems = (it['items'] as Map).cast<String, dynamic>();
      if (subDelta is Map && subDelta.isNotEmpty) {
        subDelta.forEach((rawKey, subChange) {
          if (subChange is! Map) return;
          final resolved = _findAccessorySubitem(subItems, rawKey as String);
          if (resolved == null) {
            if (kDebugMode) {
              debugPrint('outfit_delta accessory: unknown sub-item $rawKey');
            }
            return;
          }
          final subItem = subItems[resolved] as Map<String, dynamic>;
          final newSubState = subChange['state'] as String?;
          if (newSubState != null) {
            if (newSubState != 'intact' && newSubState != 'removed') {
              if (kDebugMode) {
                debugPrint('outfit_delta accessory: invalid sub-state $newSubState');
              }
            } else if (newSubState != subItem['state']) {
              subItem['state'] = newSubState;
              subItem['turns_in_state'] = 0;
              subReset.add(resolved);
              anyChanged = true;
            }
          }
          if (subChange['mentioned'] == true) {
            subItem['last_mentioned_turn'] = turnNo;
          }
        });
      } else {
        final newState = c['state'] as String?;
        if (newState != null) {
          if (newState != 'intact' && newState != 'removed') {
            if (kDebugMode) {
              debugPrint("outfit_delta: invalid state $newState for 'accessory'");
            }
          } else {
            subItems.forEach((subKey, subItem) {
              if (subItem is Map<String, dynamic> &&
                  subItem['state'] != newState) {
                subItem['state'] = newState;
                subItem['turns_in_state'] = 0;
                subReset.add(subKey);
                anyChanged = true;
              }
            });
          }
        }
      }
      // Sub-item decay.
      subItems.forEach((subKey, subItem) {
        if (subReset.contains(subKey)) return;
        if (subItem is Map<String, dynamic> &&
            (subItem['state'] ?? 'intact') != 'intact') {
          subItem['turns_in_state'] = (subItem['turns_in_state'] ?? 0) + 1;
        }
      });
      if (anyChanged) {
        _recalcAccessoryParentState(it);
        it['turns_in_state'] = 0;
        stateReset.add(slot);
      }
    } else {
      final newState = c['state'] as String?;
      if (newState == null) {
        // still allow `mentioned` below
      } else if (!isValidStateFor(slot, newState)) {
        if (kDebugMode) {
          debugPrint('outfit_delta: invalid state $newState for slot $slot');
        }
      } else if (newState != it['state']) {
        it['state'] = newState;
        it['turns_in_state'] = 0;
        stateReset.add(slot);
      }
    }

    if (c['mentioned'] == true) it['last_mentioned_turn'] = turnNo;
  });

  // Decay counter for non-intact slots that did NOT transition this turn.
  items.forEach((slot, it) {
    if (stateReset.contains(slot)) return;
    if (it is Map<String, dynamic> && itemIsNonIntact(slot, it)) {
      it['turns_in_state'] = (it['turns_in_state'] ?? 0) + 1;
    }
  });
}

/// Set every item back to intact. Used on outfit swap / "Reset to intact".
void resetItemsToIntact(Map<String, dynamic> items) {
  items.forEach((slot, it) {
    if (it is! Map<String, dynamic>) return;
    if (slot == 'dress') {
      it['top_state'] = 'intact';
      it['bottom_state'] = 'intact';
    } else if (slot == 'accessory' && it['items'] is Map) {
      it['state'] = 'intact';
      (it['items'] as Map).forEach((_, sub) {
        if (sub is Map<String, dynamic>) {
          sub['state'] = 'intact';
          sub['turns_in_state'] = 0;
        }
      });
    } else {
      it['state'] = 'intact';
    }
    it['turns_in_state'] = 0;
  });
}
