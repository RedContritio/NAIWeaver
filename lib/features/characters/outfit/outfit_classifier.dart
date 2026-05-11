/// Classifies a flat comma-separated Danbooru tag string into per-slot items.
///
/// Ported from bri.'s `classify_outfit_tags` / `_classify_single` in
/// `app/outfit_slots.py`. The result is a `{slot: itemMap}` structure where
/// each itemMap is a plain `Map<String, dynamic>` (JSON-serializable):
///   { garment: String, base_tags: String, state: String,
///     turns_in_state: int, last_mentioned_turn: int }
/// `dress` has `top_state`/`bottom_state` instead of `state`. `accessory` has an
/// `items` sub-map (per-piece state) plus a derived parent `state`.
library;

import 'package:flutter/foundation.dart';
import 'outfit_slots.dart';
import 'outfit_slots_data.dart';

final Map<String, RegExp> _wordReCache = <String, RegExp>{};
final Map<String, RegExp> _synonymReCache = <String, RegExp>{};

/// True if [needle] appears in [haystack] as one or more whole tokens.
/// "bra" does NOT match inside "bracers"; "lace bra" still matches "black lace
/// bra". Implemented with `(?<!\w)needle(?!\w)`.
bool wholeWordIn(String needle, String haystack) {
  final pat = _wordReCache.putIfAbsent(
    needle,
    () => RegExp('(?<!\\w)${RegExp.escape(needle)}(?!\\w)'),
  );
  return pat.hasMatch(haystack);
}

String _applyTagSynonyms(String tag) {
  var out = tag;
  tagSynonyms.forEach((src, dst) {
    final pat = _synonymReCache.putIfAbsent(
      src,
      () => RegExp('(?<!\\w)${RegExp.escape(src)}(?!\\w)', caseSensitive: false),
    );
    out = out.replaceAll(pat, dst);
  });
  return out;
}

bool _bloomersShouldBeBottom(String key) {
  if (!key.contains('bloomers') && !key.contains('buruma')) return false;
  return key.contains('buruma') ||
      bloomersAsBottomHints.any((hint) => wholeWordIn(hint, key));
}

/// Returns the slot for a single tag, or null if unknown.
/// Strategy: exact hit → ambiguity guards → priority-ordered whole-word
/// substring hit (longest candidate first per slot).
String? classifySingleTag(String tag) {
  final key = tag.toLowerCase().trim();
  final exact = tagToSlot[key];
  if (exact != null) return exact;
  if (_bloomersShouldBeBottom(key)) return 'bottom';
  for (final slot in kSlotPriority) {
    final candidates = candidatesBySlot[slot];
    if (candidates == null) continue;
    for (final candidate in candidates) {
      if (wholeWordIn(candidate, key)) return slot;
    }
  }
  return null;
}

/// Parse a comma-separated Danbooru tag string into `{slot: itemMap}`.
/// Items start at state `intact`. Unknown tags bucket into `accessory`.
Map<String, dynamic> classifyOutfitTags(String? outfitTags) {
  final items = <String, dynamic>{};
  if (outfitTags == null || outfitTags.trim().isEmpty) return items;

  final rawTags = outfitTags
      .split(',')
      .map((t) => _applyTagSynonyms(t.trim().toLowerCase()))
      .where((t) => t.isNotEmpty)
      .toList();

  final buckets = <String, List<String>>{};
  final unknown = <String>[];
  for (final tag in rawTags) {
    final slot = classifySingleTag(tag);
    if (slot == null) {
      unknown.add(tag);
      continue;
    }
    (buckets[slot] ??= <String>[]).add(tag);
  }
  if (unknown.isNotEmpty) {
    if (kDebugMode) {
      debugPrint('outfit_slots: unclassified tags → accessory: $unknown');
    }
    (buckets['accessory'] ??= <String>[]).addAll(unknown);
  }

  for (final slot in kSlotPriority) {
    final tags = buckets[slot];
    if (tags == null || tags.isEmpty) continue;
    // Longest tag = most specific label.
    final garment = tags.reduce((a, b) => a.length >= b.length ? a : b);
    final item = <String, dynamic>{
      'garment': garment,
      'base_tags': tags.join(', '),
      'turns_in_state': 0,
      'last_mentioned_turn': 0,
    };
    if (slot == 'dress') {
      item['top_state'] = 'intact';
      item['bottom_state'] = 'intact';
    } else if (slot == 'accessory') {
      item['state'] = 'intact';
      item['items'] = <String, dynamic>{
        for (final t in tags)
          t: <String, dynamic>{
            'state': 'intact',
            'turns_in_state': 0,
            'last_mentioned_turn': 0,
          }
      };
    } else {
      item['state'] = 'intact';
    }
    items[slot] = item;
  }

  return items;
}
