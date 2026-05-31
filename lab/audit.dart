// Quality audit for generated outfits and characters.
//
// Mostly pure logic. Optional canonical-tag check loads
// `Tags/high-frequency-tags-list.json` lazily from disk (lab harness only —
// no rootBundle dep). Given a list of outfits (Map<String,dynamic> in the
// wardrobe-gen JSON shape), report which ones violate the prompt's hard rules.

import 'dart:convert';
import 'dart:io';
//
// Categories — split into BLOCKING findings and informational WARNINGS.
//
// Blocking findings (image will look wrong, the prompt failed):
//   • chestCoverage       — outer torso layer with no base top (and not sleep)
//   • tagCountLow/High    — fewer than 4 or more than 7 garment tags
//   • missingColor        — a tag with a recognised garment word but no colour
//   • smuggle             — body/pose/weather/environment token leaked in
//   • empty               — outfit has zero tags
//
// Informational warnings (NAI 4.5 handles these; surfacing for review only):
//   • forbiddenMaterial   — "linen X", "silk X" etc. NAI 4.5's Flux decoder
//                           handles these, but kept visible as drift signal.
//   • unknownTagToken     — token (after stripping colors) doesn't resolve to
//                           a canonical Danbooru tag via any trailing N-gram.

enum AuditSeverity { finding, warning }

class OutfitFinding {
  final String outfitName;
  final String category;
  final String detail; // human-readable
  final AuditSeverity severity;
  const OutfitFinding(
    this.outfitName,
    this.category,
    this.detail, {
    this.severity = AuditSeverity.finding,
  });

  @override
  String toString() {
    final tag = severity == AuditSeverity.warning ? 'warn' : category;
    return severity == AuditSeverity.warning
        ? '[warn:$category] "$outfitName": $detail'
        : '[$tag] "$outfitName": $detail';
  }
}

class OutfitReport {
  /// All entries — blocking findings AND informational warnings — preserved
  /// here for backwards-compat with existing callers that iterate `findings`.
  /// Use [blocking] / [warnings] for severity-aware consumption.
  final List<OutfitFinding> findings;
  final int outfitCount;
  const OutfitReport(this.findings, this.outfitCount);

  List<OutfitFinding> get blocking =>
      [for (final f in findings) if (f.severity == AuditSeverity.finding) f];
  List<OutfitFinding> get warnings =>
      [for (final f in findings) if (f.severity == AuditSeverity.warning) f];

  Map<String, int> get tally {
    final t = <String, int>{};
    for (final f in blocking) {
      t[f.category] = (t[f.category] ?? 0) + 1;
    }
    return t;
  }

  Map<String, int> get warningTally {
    final t = <String, int>{};
    for (final f in warnings) {
      t[f.category] = (t[f.category] ?? 0) + 1;
    }
    return t;
  }

  bool get isClean => blocking.isEmpty;

  String formatted() {
    final buf = StringBuffer();
    final block = blocking;
    final warn = warnings;
    buf.writeln(
        'Audited $outfitCount outfit(s). ${block.length} blocking, ${warn.length} warning(s).');
    if (block.isEmpty && warn.isEmpty) {
      buf.writeln('  Clean.');
      return buf.toString();
    }
    if (block.isNotEmpty) {
      buf.writeln('  Findings tally:');
      for (final e in tally.entries) {
        buf.writeln('    ${e.key}: ${e.value}');
      }
      buf.writeln('  Findings:');
      for (final f in block) {
        buf.writeln('    $f');
      }
    }
    if (warn.isNotEmpty) {
      buf.writeln('  Warnings tally:');
      for (final e in warningTally.entries) {
        buf.writeln('    ${e.key}: ${e.value}');
      }
      buf.writeln('  Warnings:');
      for (final f in warn) {
        buf.writeln('    $f');
      }
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

// Acceptable base TOP garments that satisfy chest coverage. Includes
// historical/draped single-garment dresses (stola, tunica, peplos, chiton,
// gown) where the dress IS the base layer under a cloak/coat/cardigan.
// Loungewear (robe/kimono/yukata) is intentionally NOT here — those have a
// different role and are handled via the [_loungewear] + sleep-slot exemption.
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
  'tunica',
  'stola',
  'chiton',
  'peplos',
  'dress',
  'gown',
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

// Recognised colour tokens. `tan` and `chestnut` are intentionally NOT here:
// NAI 4.5 confuses them between skin/hair tone and garment/leather. Use
// brown/beige/khaki instead.
const Set<String> _colors = {
  'white', 'black', 'grey', 'gray', 'red', 'blue', 'green', 'yellow', 'orange',
  'purple', 'pink', 'brown', 'beige', 'gold', 'silver', 'bronze', 'cream',
  'ivory', 'charcoal', 'burgundy', 'olive', 'slate', 'rust', 'sage', 'taupe',
  'navy', 'mustard', 'plum', 'lavender', 'mint', 'teal', 'turquoise', 'crimson',
  'scarlet', 'maroon', 'indigo', 'violet', 'rose', 'peach', 'coral', 'salmon',
  'khaki', 'chocolate', 'mocha', 'amber', 'emerald', 'jade', 'aqua', 'cyan',
  'magenta', 'fuchsia', 'azure', 'cobalt', 'wine', 'cherry', 'forest', 'pearl',
  'ash', 'midnight', 'denim',
};

// Garment-word tokens that, when present in a tag, require a recognised
// colour. Tags WITHOUT a garment word (attribute-only: "long sleeves",
// "high collar", "scoop neck", "lace trim", "hooded", "floor-length") don't
// need a colour — Danbooru has many of these as standalone attribute tags.
const Set<String> _garmentTokens = {
  // Tops
  'shirt', 't-shirt', 'tshirt', 'blouse', 'tank', 'tanktop', 'camisole',
  'crop', 'sweater', 'turtleneck', 'pullover', 'henley', 'polo', 'hoodie',
  'sweatshirt', 'cardigan', 'vest', 'waistcoat', 'bodysuit', 'leotard',
  'bra', 'bralette', 'bandeau',
  // Bottoms
  'skirt', 'pants', 'trousers', 'jeans', 'shorts', 'leggings', 'tights',
  'pantyhose', 'stockings', 'jodhpurs', 'breeches', 'sweatpants',
  // Dresses / one-piece / sleepwear
  'dress', 'gown', 'sundress', 'kimono', 'yukata', 'robe', 'bathrobe',
  'negligee', 'peignoir', 'nightgown', 'nightdress', 'pajamas', 'pajama',
  'slip',
  // Outerwear
  'jacket', 'blazer', 'coat', 'overcoat', 'trench', 'raincoat', 'parka',
  'duster', 'cloak', 'cape', 'poncho', 'shawl', 'surcoat', 'tabard',
  'hauberk', 'breastplate', 'cuirass',
  // Footwear
  'boots', 'shoes', 'sneakers', 'loafers', 'sandals', 'slippers', 'heels',
  'pumps', 'mary', 'oxfords', 'geta', 'calcei',
  // Accessories that benefit from a color
  'hat', 'beanie', 'beret', 'fedora', 'bonnet', 'cap', 'scarf', 'gloves',
  'mittens', 'tie', 'ascot', 'belt', 'sash', 'obi', 'umbrella', 'parasol',
  // Historical base layers
  'chemise', 'corset', 'petticoat', 'bloomers', 'tunic', 'tunica', 'toga',
  'stola', 'chiton', 'peplos', 'himation', 'gambeson', 'doublet', 'palla',
  'subligaculum', 'loincloth', 'shendyt', 'wimple',
};

// Canonical Danbooru attribute words that don't standalone-search in our
// high-frequency JSON but appear inside compounds and are legitimate
// attribute-only tags. When a wardrobe tag's non-colour tokens are ALL in
// this set, the audit's unknownTagToken check passes it through.
//
// Example: a bare tag `high-waisted` or `hooded` is a valid attribute tag
// even though `high-waisted` isn't in high-frequency-tags-list.json on its
// own (the canonical entry tends to be the compound, like `high-waisted
// skirt`).
const Set<String> _attributeTokens = {
  'hooded',
  'floor-length',
  'ankle-high',
  'knee-length',
  'high-waisted',
  'off-shoulder',
  'cropped',
  'fitted',
  'plunging',
  'flat',
  'heeled',
  'open',
  'sleeveless',
  'scoop',
  'v-neck',
};

// Era-specific vocabulary words that NAI 4.5's Flux decoder handles well but
// that are not present in our canonical Danbooru list. Same treatment as
// [_attributeTokens]: a tag whose non-colour tokens are ALL in this set
// passes the unknownTagToken check.
//
// These are the period-correct garment words shipped by
// `eraClothingVocabularyFor()` in `wardrobe_generator_service.dart` —
// keep the two in sync.
const Set<String> _eraToleratedTags = {
  'stola',
  'palla',
  'tunica',
  'subligaculum',
  'pallium',
  'calcei',
  'fibula',
  'torque',
  'peplos',
  'himation',
  'hauberk',
  'gambeson',
  'doublet',
  'shendyt',
};

// Tags that are widely rendered cleanly by NAI but happen not to be in the
// canonical high-frequency JSON. Treated as canonical for the trailing-N-gram
// check. Each entry was verified against the JSON file before adding.
const Set<String> _canonicalSupplement = {
  'tights',
  'stockings',
  'pajama set',
  'rain boots',
};

// Tokens that should NEVER appear in `tags` (clothing manifest only). All
// matched WHOLE-WORD via regex below — substring matching used to false-flag
// `scarf` for containing `scar`, `tweed` for containing nothing useful, etc.
const List<String> _smuggleTokens = [
  // body parts
  'hair', 'eyes', 'eye color', 'breasts', 'cleavage', 'thighs', 'shoulders',
  'skin', 'face', 'lips', 'cheeks', 'freckles', 'scars', 'scar',
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
  // bri-style smuggle compounds (substring on these is safe because they're
  // already compound phrases that don't collide with garments)
  'mineral stain', 'mineral-stained',
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

bool _hasGarmentWord(String tag) {
  for (final g in _garmentTokens) {
    if (RegExp(r'\b' + RegExp.escape(g) + r'\b').hasMatch(tag)) return true;
  }
  return false;
}

/// Whole-word smuggle check. Substring matching used to false-flag `scarf`
/// for containing `scar` and `tweed` for nothing useful. Multi-word smuggles
/// (e.g. `mineral stain`) match as substrings since they're already compound
/// phrases that don't collide with single garment words.
String? _smuggleHit(String tag) {
  for (final s in _smuggleTokens) {
    if (s.contains(' ') || s.contains('-')) {
      // Compound — substring is safe.
      if (tag.contains(s)) return s;
    } else {
      if (RegExp(r'\b' + RegExp.escape(s) + r'\b').hasMatch(tag)) return s;
    }
  }
  return null;
}

/// Splits a single tag like "cream knit sweater" into ["cream","knit","sweater"].
List<String> _tokenize(String tag) =>
    tag.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

/// Strips leading colour tokens off a tokenized tag, returning the
/// non-colour remainder (e.g. ["knit","sweater"] for "cream knit sweater",
/// ["plaid","scarf"] for "burgundy plaid scarf").
List<String> _stripLeadingColors(List<String> tokens) {
  var i = 0;
  while (i < tokens.length && _colors.contains(tokens[i])) {
    i++;
  }
  return tokens.sublist(i);
}

/// True if any trailing N-gram of [tokens] (joined with spaces) is in
/// [canonical]. E.g. for ["knit","sweater"] checks "knit sweater" then
/// "sweater" — either match suffices.
bool _anyTrailingNgramCanonical(List<String> tokens, Set<String> canonical) {
  for (var start = 0; start < tokens.length; start++) {
    final candidate = tokens.sublist(start).join(' ');
    if (canonical.contains(candidate)) return true;
  }
  return false;
}

/// Audits a list of outfits (wardrobe-gen JSON shape) for prompt-rule
/// violations. Returns an [OutfitReport]. Some categories are demoted to
/// [AuditSeverity.warning] — see [OutfitReport.blocking] vs [warnings].
OutfitReport auditOutfits(List<Map<String, dynamic>> outfits) {
  final findings = <OutfitFinding>[];
  final canonical = loadCanonicalTags();

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

    // Forbidden materials — WARNING (NAI 4.5 Flux decoder handles these).
    for (final tag in v.tagList) {
      for (final mat in _forbiddenMaterials) {
        // "satin slip" is canonical and allowed; "satin" IS indexed.
        if (RegExp(r'\b' + mat + r'\b').hasMatch(tag)) {
          findings.add(OutfitFinding(
            v.name,
            'forbiddenMaterial',
            '"$tag" uses non-Danbooru material "$mat" (NAI handles it; review)',
            severity: AuditSeverity.warning,
          ));
          break;
        }
      }
    }

    // Missing color — only when the tag contains a recognised garment word.
    // Attribute-only tags (`long sleeves`, `high collar`, `lace trim`,
    // `hooded`, `floor-length`) are legitimate without colours.
    for (final tag in v.tagList) {
      if (!_hasGarmentWord(tag)) continue;
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

    // Smuggled body/pose/weather/env tokens — whole-word match.
    for (final tag in v.tagList) {
      final hit = _smuggleHit(tag);
      if (hit != null) {
        findings.add(OutfitFinding(
          v.name,
          'smuggle',
          '"$tag" contains "$hit" (body/pose/weather/env)',
        ));
      }
    }

    // unknownTagToken — WARNING. Parentheticals always flag; other tags pass
    // when ANY trailing N-gram (after stripping leading colours) is in the
    // canonical Danbooru list OR [_canonicalSupplement]. Tags whose remaining
    // tokens are ALL attribute words ([_attributeTokens]) or ALL era-tolerated
    // period vocab ([_eraToleratedTags]) also pass. Skip entirely if the
    // canonical file is not loadable (lab harness might be invoked from a
    // different working dir).
    if (canonical != null) {
      for (final tag in v.tagList) {
        if (tag.contains('(') || tag.contains(')')) {
          findings.add(OutfitFinding(
            v.name,
            'unknownTagToken',
            '"$tag" contains parentheses (invented compound)',
            severity: AuditSeverity.warning,
          ));
          continue;
        }
        // Whole-tag canonical / supplement hit is the cheap path.
        if (canonical.contains(tag)) continue;
        if (_canonicalSupplement.contains(tag)) continue;
        final tokens = _tokenize(tag);
        if (tokens.isEmpty) continue;
        final remaining = _stripLeadingColors(tokens);
        if (remaining.isEmpty) continue; // pure colour token, fine
        if (_anyTrailingNgramCanonical(remaining, canonical)) continue;
        if (_anyTrailingNgramCanonical(remaining, _canonicalSupplement)) continue;
        // Allow-list pass: every non-colour token is an attribute word or an
        // era-tolerated period garment.
        if (remaining.every((t) =>
            _attributeTokens.contains(t) || _eraToleratedTags.contains(t))) {
          continue;
        }
        findings.add(OutfitFinding(
          v.name,
          'unknownTagToken',
          '"$tag" has no canonical Danbooru tag in trailing tokens',
          severity: AuditSeverity.warning,
        ));
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
