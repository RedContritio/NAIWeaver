// Quality audit for generated outfits and characters.
//
// Mostly pure logic. Optional canonical-tag check loads
// `Tags/high-frequency-tags-list.json` lazily from disk (lab harness only —
// no rootBundle dep). Given a list of outfits (Map<String,dynamic> in the
// wardrobe-gen JSON shape), report which ones violate the prompt's hard rules.

import 'dart:convert';
import 'dart:io';
//
// Categories of violation:
//   • forbiddenMaterial   — uses "linen X", "silk X" (other than satin), etc.
//   • chestCoverage       — outer torso layer with no base top (and not sleep)
//   • tagCountLow/High    — fewer than 4 or more than 7 garment tags
//   • missingColor        — at least one tag has no recognised colour token
//   • smuggle             — body/pose/weather/environment token leaked in
//
// Returns a Report with per-outfit findings and a summary tally.

class OutfitFinding {
  final String outfitName;
  final String category;
  final String detail; // human-readable
  const OutfitFinding(this.outfitName, this.category, this.detail);

  @override
  String toString() => '[$category] "$outfitName": $detail';
}

class OutfitReport {
  final List<OutfitFinding> findings;
  final int outfitCount;
  const OutfitReport(this.findings, this.outfitCount);

  Map<String, int> get tally {
    final t = <String, int>{};
    for (final f in findings) {
      t[f.category] = (t[f.category] ?? 0) + 1;
    }
    return t;
  }

  bool get isClean => findings.isEmpty;

  String formatted() {
    final buf = StringBuffer();
    buf.writeln('Audited $outfitCount outfit(s). ${findings.length} finding(s).');
    if (findings.isEmpty) {
      buf.writeln('  Clean.');
      return buf.toString();
    }
    final t = tally;
    buf.writeln('  Tally:');
    for (final e in t.entries) {
      buf.writeln('    ${e.key}: ${e.value}');
    }
    buf.writeln('  Details:');
    for (final f in findings) {
      buf.writeln('    $f');
    }
    return buf.toString();
  }
}

// Material tokens that bri's prompt forbids — Danbooru-unindexed, image model
// ignores them. ("satin" IS indexed and is fine, so handled specially.)
const Set<String> _forbiddenMaterials = {
  'linen',
  'silk',
  'corduroy',
  'chiffon',
  'velvet',
  'tweed',
};

// Outer torso layers that trigger the chest-coverage rule.
const Set<String> _outerLayers = {
  'jacket',
  'cardigan',
  'blazer',
  'coat',
  'cloak',
  'cape',
  'surcoat',
  'tabard',
  'hauberk',
  'breastplate',
  'cuirass',
  'plate armor',
  'raincoat',
  'parka',
  'overcoat',
  'trench coat',
  'duster',
};

// Acceptable base TOP garments that satisfy chest coverage.
const Set<String> _baseTops = {
  'shirt',
  'blouse',
  't-shirt',
  'tshirt',
  'tank top',
  'tanktop',
  'sweater',
  'turtleneck',
  'gambeson',
  'doublet',
  'tunic',
  'pullover',
  'henley',
  'camisole',
  'bodysuit',
  'crop top',
  'sweatshirt',
  'hoodie',
  'polo',
};

// Loungewear that exempts the chest-coverage rule when slot is "sleep".
const Set<String> _loungewear = {
  'robe',
  'bathrobe',
  'kimono',
  'negligee',
  'peignoir',
  'nightgown',
  'nightdress',
};

// Recognised colour tokens. Conservative list — better to flag a possible
// miss than miss a real one. Extend as needed.
const Set<String> _colors = {
  'white', 'black', 'grey', 'gray', 'red', 'blue', 'green', 'yellow', 'orange',
  'purple', 'pink', 'brown', 'beige', 'tan', 'gold', 'silver', 'bronze', 'cream',
  'ivory', 'charcoal', 'burgundy', 'olive', 'slate', 'rust', 'sage', 'taupe',
  'navy', 'mustard', 'plum', 'lavender', 'mint', 'teal', 'turquoise', 'crimson',
  'scarlet', 'maroon', 'indigo', 'violet', 'rose', 'peach', 'coral', 'salmon',
  'khaki', 'chocolate', 'mocha', 'amber', 'emerald', 'jade', 'aqua', 'cyan',
  'magenta', 'fuchsia', 'azure', 'cobalt', 'wine', 'cherry', 'forest', 'pearl',
  'ash', 'midnight', 'denim',
};

// Tokens that should NEVER appear in `tags` (clothing manifest only).
// Compact starter list — these are the most common smuggled bodies / poses /
// weather / environments. Audit flags but doesn't fail; some are judgement calls.
const List<String> _smuggleTokens = [
  // body parts
  'hair', 'eyes', 'eye color', 'breasts', 'cleavage', 'thighs', 'shoulders',
  'skin', 'face', 'lips', 'cheeks', 'freckles', 'scars', 'scar', 'mineral',
  'broken nose', 'broad face',
  // poses / expressions
  'smile', 'smirk', 'crossed arms', 'hunched', 'leaning', 'arms crossed',
  'hand shielding', 'closed eyes',
  // weather sensations
  'wind-flushed', 'sweat-gleamed', 'rain-streamed', 'visible breath',
  'mist-breath', 'shivering', 'sodden', 'water-darkened', 'wet linen',
  'mud on calves', 'wind-tossed', 'sun-warmed', 'rain-soaked',
  // environment / mood
  'morning light', 'afternoon light', 'brazier-warmed', 'festive', 'discreet',
  'twilight', 'firelit',
];

class _OutfitView {
  final String name;
  final List<String> tagList; // already-trimmed, lowercased
  final List<String> slots;
  final String tagsRaw;
  _OutfitView(this.name, this.tagList, this.slots, this.tagsRaw);
}

_OutfitView _viewOf(Map<String, dynamic> o) {
  final name = (o['name'] is String ? o['name'] as String : 'unnamed').trim();
  final rawTags = (o['tags'] is String ? o['tags'] as String : '').toLowerCase();
  final tagList = rawTags
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final slots = (o['slots'] is List)
      ? (o['slots'] as List)
          .whereType<String>()
          .map((s) => s.toLowerCase())
          .toList()
      : const <String>[];
  return _OutfitView(name, tagList, slots, rawTags);
}

bool _containsAny(String tag, Set<String> haystack) {
  for (final h in haystack) {
    if (tag.contains(h)) return true;
  }
  return false;
}

bool _hasColor(String tag) {
  for (final c in _colors) {
    // word-boundary-ish; "navy blue" → match "navy" or "blue"
    if (RegExp(r'\b' + RegExp.escape(c) + r'\b').hasMatch(tag)) return true;
  }
  return false;
}

/// Audits a list of outfits (wardrobe-gen JSON shape) for prompt-rule
/// violations. Returns a [Report].
OutfitReport auditOutfits(List<Map<String, dynamic>> outfits) {
  final findings = <OutfitFinding>[];

  for (final o in outfits) {
    final v = _viewOf(o);
    if (v.tagList.isEmpty) {
      findings.add(OutfitFinding(v.name, 'empty', 'no tags at all'));
      continue;
    }

    // Tag count
    if (v.tagList.length < 4) {
      findings.add(OutfitFinding(
        v.name,
        'tagCountLow',
        'only ${v.tagList.length} tag(s)',
      ));
    } else if (v.tagList.length > 7) {
      // 7 is the upper bound from the prompt; >7 is a finding but not always
      // a failure (sometimes 8 is fine). Just flag it.
      findings.add(OutfitFinding(
        v.name,
        'tagCountHigh',
        '${v.tagList.length} tags (cap is 7)',
      ));
    }

    // Forbidden materials
    for (final tag in v.tagList) {
      for (final mat in _forbiddenMaterials) {
        // "satin slip" is canonical and allowed; anything else "silk X" is not.
        // The rule lists "satin" as INDEXED, so allow it.
        if (RegExp(r'\b' + mat + r'\b').hasMatch(tag)) {
          findings.add(OutfitFinding(
            v.name,
            'forbiddenMaterial',
            '"$tag" uses unindexed material "$mat"',
          ));
          break;
        }
      }
    }

    // Missing color (per-tag)
    for (final tag in v.tagList) {
      // skip very short / common base layer tokens that rarely have a color
      // e.g. "loincloth" alone is fine for an era piece, but flag for review.
      if (!_hasColor(tag)) {
        findings.add(OutfitFinding(
          v.name,
          'missingColor',
          '"$tag" has no recognised colour token',
        ));
      }
    }

    // Chest coverage
    final hasOuter = v.tagList.any((t) => _containsAny(t, _outerLayers));
    final hasBaseTop = v.tagList.any((t) => _containsAny(t, _baseTops));
    final hasLoungewear = v.tagList.any((t) => _containsAny(t, _loungewear));
    final isSleep = v.slots.contains('sleep');
    if (hasOuter && !hasBaseTop && !(hasLoungewear && isSleep)) {
      findings.add(OutfitFinding(
        v.name,
        'chestCoverage',
        'outer layer without a base top garment',
      ));
    }

    // Smuggled body/pose/weather/env tokens
    for (final tag in v.tagList) {
      for (final s in _smuggleTokens) {
        if (tag.contains(s)) {
          findings.add(OutfitFinding(
            v.name,
            'smuggle',
            '"$tag" contains "$s" (body/pose/weather/env)',
          ));
          break;
        }
      }
    }
  }

  return OutfitReport(findings, outfits.length);
}

// -- Character-level audit (the main-gen prompt) -----------------------------

class CharacterFinding {
  final String field;
  final String detail;
  const CharacterFinding(this.field, this.detail);
  @override
  String toString() => '[$field] $detail';
}

class CharacterReport {
  final List<CharacterFinding> findings;
  final List<String> presentFields;
  const CharacterReport(this.findings, this.presentFields);

  bool get isClean => findings.isEmpty;

  String formatted() {
    final buf = StringBuffer();
    buf.writeln('Character audit: ${findings.length} finding(s).');
    buf.writeln('  Present fields: ${presentFields.join(", ")}');
    for (final f in findings) {
      buf.writeln('  $f');
    }
    return buf.toString();
  }
}

/// Which JSON shape to expect from the model.
///
/// - `full` — bri's encounter pipeline output: `name, gender, soul_md,
///   reaction_patterns, character_description, personality_summary,
///   outfit_tags, tags, theme`. Used by §3 in the planning doc.
/// - `lean` — v2 spec (see `docs/CHARACTER_FEATURES_PLAN.md` §4): appearance
///   tags only. `name, gender, tags:{base, face, hair, body, nsfw_top,
///   nsfw_bottom, nsfw_always, nsfw}`. No soul_md / theme / outfit_tags / etc.
enum CharacterShape { full, lean }

/// Cache for the canonical tag set (lazily loaded from disk).
Set<String>? _canonicalTagsCache;

/// Loads `Tags/high-frequency-tags-list.json` from the lab's working dir
/// (project root). Returns null if the file isn't readable — callers should
/// then skip the unknown-tag check rather than crash.
Set<String>? loadCanonicalTags({String path = 'Tags/high-frequency-tags-list.json'}) {
  if (_canonicalTagsCache != null) return _canonicalTagsCache;
  try {
    final f = File(path);
    if (!f.existsSync()) return null;
    final raw = f.readAsStringSync();
    final list = jsonDecode(raw);
    if (list is! List) return null;
    final out = <String>{};
    for (final entry in list) {
      if (entry is! Map) continue;
      final tag = entry['tag'];
      if (tag is String) out.add(tag.toLowerCase().trim());
      final aliases = entry['aliases'];
      if (aliases is List) {
        for (final a in aliases) {
          if (a is String) out.add(a.toLowerCase().trim());
        }
      }
    }
    _canonicalTagsCache = out;
    return out;
  } catch (_) {
    return null;
  }
}

/// Splits a comma-separated tag string into trimmed lowercase tokens.
List<String> _splitTags(String s) => s
    .toLowerCase()
    .split(',')
    .map((t) => t.trim())
    .where((t) => t.isNotEmpty)
    .toList();

CharacterReport auditCharacter(
  Map<String, dynamic> c, {
  CharacterShape shape = CharacterShape.full,
}) {
  final findings = <CharacterFinding>[];
  final present = <String>[];

  void mustString(String key, {int? minWords, int? maxWords}) {
    final v = c[key];
    if (v is! String || v.trim().isEmpty) {
      findings.add(CharacterFinding(key, 'missing or empty'));
      return;
    }
    present.add(key);
    if (minWords != null || maxWords != null) {
      final words = v.trim().split(RegExp(r'\s+')).length;
      if (minWords != null && words < minWords) {
        findings.add(CharacterFinding(key, '$words words (< $minWords)'));
      }
      if (maxWords != null && words > maxWords) {
        findings.add(CharacterFinding(key, '$words words (> $maxWords)'));
      }
    }
  }

  void mustMap(String key, List<String> requiredSubkeys) {
    final v = c[key];
    if (v is! Map) {
      findings.add(CharacterFinding(key, 'missing or not an object'));
      return;
    }
    present.add(key);
    for (final sub in requiredSubkeys) {
      if (v[sub] == null || (v[sub] is String && (v[sub] as String).trim().isEmpty)) {
        findings.add(CharacterFinding('$key.$sub', 'missing or empty'));
      }
    }
  }

  // Shared (both shapes)
  mustString('name');
  mustString('gender');
  mustMap('tags', ['base', 'face', 'hair', 'body']);

  if (shape == CharacterShape.full) {
    mustString('soul_md', minWords: 400, maxWords: 1400);
    mustString('character_description', minWords: 30, maxWords: 100);
    mustString('personality_summary', maxWords: 50);
    mustString('outfit_tags');
    mustMap('reaction_patterns',
        ['nervous', 'angry', 'attracted', 'sad', 'scared', 'embarrassed', 'happy']);
    mustMap('theme', ['accent', 'accent_secondary', 'bg']);

    // Check outfit_tags for the same wardrobe rules.
    final outfitTags = c['outfit_tags'];
    if (outfitTags is String && outfitTags.trim().isNotEmpty) {
      final pseudoOutfit = {
        'name': 'meet_outfit',
        'tags': outfitTags,
        'slots': const <String>[],
      };
      final report = auditOutfits([pseudoOutfit]);
      for (final f in report.findings) {
        findings.add(CharacterFinding('outfit_tags', '${f.category} — ${f.detail}'));
      }
    }
  } else {
    // Lean shape: the four NSFW slots are nice-to-have, not required. GLM
    // sometimes omits them when NSFW is off; the importer fills them with "".
    // We surface a single soft warning per missing slot rather than blocking.
    final tags = c['tags'];
    if (tags is Map) {
      for (final slot in ['nsfw_top', 'nsfw_bottom', 'nsfw_always', 'nsfw']) {
        if (!tags.containsKey(slot)) {
          findings.add(CharacterFinding(
            'nsfw_slot_warning',
            'tags.$slot omitted (importer will fill with "")',
          ));
        }
      }
      // Smuggle check: lean tags should not contain clothing/expressions/poses.
      for (final bucket in ['base', 'face', 'hair', 'body']) {
        final v = tags[bucket];
        if (v is! String) continue;
        final lower = v.toLowerCase();
        // Quick check for the most common smuggled categories. Not exhaustive —
        // garments are very common drift on lean prompts.
        const clothingHints = [
          'shirt', 'blouse', 'jacket', 'coat', 'dress', 'skirt', 'pants',
          'jeans', 'sweater', 'cardigan', 'hoodie', 'boots', 'shoes', 'hat',
        ];
        for (final h in clothingHints) {
          if (RegExp(r'\b' + h + r'\b').hasMatch(lower)) {
            findings.add(CharacterFinding(
              'tags.$bucket',
              'contains clothing token "$h" (must be appearance-only)',
            ));
            break;
          }
        }
      }
      // Unknown-tag check: walk every emitted tag and flag the ones not in the
      // canonical Danbooru list. We tolerate the four NSFW slots being empty.
      final canonical = loadCanonicalTags();
      if (canonical != null) {
        for (final bucket in ['base', 'face', 'hair', 'body', 'nsfw_top', 'nsfw_bottom', 'nsfw_always']) {
          final v = tags[bucket];
          if (v is! String || v.trim().isEmpty) continue;
          for (final tag in _splitTags(v)) {
            if (!canonical.contains(tag)) {
              findings.add(CharacterFinding(
                'unknownTag',
                'tags.$bucket "$tag" is not in the canonical Danbooru list',
              ));
            }
          }
        }
      }
    }
  }

  return CharacterReport(findings, present);
}
