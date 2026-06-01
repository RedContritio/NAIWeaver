import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Static data + small helpers for the character generator: the curated vibe
/// list (ported from bri.'s `vibes.py`), the historical-era catalogue (loaded
/// from `assets/character_eras.json`, a stripped port of bri.'s
/// `config/time_periods.json` — moments verbatim, pins/images dropped), and the
/// knowledge-boundary / soul-addendum text blocks.
///
/// None of this needs the network; the era catalogue is bundled.

// ---------------------------------------------------------------------------
// Image style
// ---------------------------------------------------------------------------

/// How the generated character is rendered. `anime` (default) is tag-based —
/// the path NAI image gen uses. `realistic` additionally fills the
/// natural-language `characterDescription`.
enum CharacterImageStyle { anime, realistic }

extension CharacterImageStyleX on CharacterImageStyle {
  String get id => this == CharacterImageStyle.realistic ? 'realistic' : 'anime';
  String get label => this == CharacterImageStyle.realistic ? 'Realistic' : 'Anime';
}

// ---------------------------------------------------------------------------
// Gender
// ---------------------------------------------------------------------------

/// Gender choices for the generator form. `any` lets the model pick.
const List<String> kCharacterGenderOptions = ['any', 'female', 'male', 'nonbinary'];

// ---------------------------------------------------------------------------
// Vibes (ported from bri.'s vibes.py builtin list)
// ---------------------------------------------------------------------------

/// One generator "vibe" — a short hint shown in the form and an optional long
/// guidance blob injected into the generation prompt.
class CharacterVibe {
  final String id;
  final String name;
  final String hint;

  /// Long guidance text injected verbatim into the generation prompt. For
  /// `custom` and `addicted` this is a *template* containing `{customVibe}` /
  /// `{addictionPick}` — call [resolvedGuidance].
  final String guidanceTemplate;

  /// `addicted` takes an optional "what they're addicted to" sub-field.
  final bool hasAddictionSubject;

  /// `custom` takes a free-text vibe.
  final bool isCustom;

  const CharacterVibe({
    required this.id,
    required this.name,
    this.hint = '',
    this.guidanceTemplate = '',
    this.hasAddictionSubject = false,
    this.isCustom = false,
  });

  /// Returns the guidance block ready for prompt injection, substituting the
  /// custom-vibe text and/or the addiction subject. Returns an empty string for
  /// vibes with no guidance ("surprise me", "friendly", …).
  String resolvedGuidance({String customVibe = '', String addictionSubject = ''}) {
    if (isCustom) {
      final t = customVibe.trim();
      return t.isEmpty ? '' : 'VIBE -- CUSTOM: $t';
    }
    if (guidanceTemplate.isEmpty) return '';
    if (!guidanceTemplate.contains('{addictionPick}')) return guidanceTemplate;
    final subj = addictionSubject.trim();
    final pick = subj.isEmpty
        ? 'Pick a SPECIFIC addiction that fits the character\'s location, era, and personality: '
            'alcohol, drugs (name the substance — opium, meth, pills, khat, whatever fits), sex, '
            'gambling, adrenaline, a person, work, religious fervor, collecting, digital stimulation, '
            'or something stranger. '
        : 'The addiction is: ${subj.toUpperCase()}. Make it specific to the '
            'character\'s location and era — what form does this take in their world? ';
    return guidanceTemplate.replaceAll('{addictionPick}', pick);
  }
}

/// The 10 builtin vibes, ported from bri.'s `vibes.py` `_BUILTIN_VIBES`. The
/// guidance blobs for `traditional`, `touched`, `addicted` and `custom` are
/// copied verbatim (with the addiction-subject substitution handled at runtime).
const List<CharacterVibe> kCharacterVibes = <CharacterVibe>[
  CharacterVibe(id: 'surprise_me', name: 'Surprise Me', hint: ''),
  CharacterVibe(id: 'friendly', name: 'Friendly', hint: 'Warm and approachable'),
  CharacterVibe(id: 'mysterious', name: 'Mysterious', hint: 'Enigmatic and guarded'),
  CharacterVibe(id: 'chaotic', name: 'Chaotic', hint: 'Unpredictable energy'),
  CharacterVibe(id: 'romantic', name: 'Romantic', hint: 'Emotionally available, flirty'),
  CharacterVibe(id: 'intimidating', name: 'Intimidating', hint: 'Commanding presence'),
  CharacterVibe(
    id: 'traditional',
    name: 'Traditional',
    hint: 'Rooted in local cultural/religious tradition',
    guidanceTemplate:
        'VIBE -- TRADITIONAL: This character is rooted in the dominant cultural, religious, or '
        'philosophical tradition of their location (in their time period). Research what \'traditional\' '
        'actually MEANS for this specific place and era -- don\'t default to Western assumptions. '
        'They are NOT a caricature of conservatism. They are a fully realized person whose daily '
        'life, values, relationships, and worldview are genuinely shaped by their tradition. Maybe '
        'they\'re deeply devout and find peace in ritual. Maybe they\'re culturally traditional without '
        'being especially pious -- they follow customs because that\'s just how life is. Maybe they '
        'wrestle with parts of their tradition privately but would never say so publicly. '
        'Key: their tradition should be SPECIFIC (name the actual religion, philosophy, or cultural '
        'framework), LIVED (show it in daily habits, not just stated beliefs), and COMPLEX (they\'re '
        'a person, not a pamphlet). Give them opinions that come FROM their tradition that might '
        'surprise someone who only knows stereotypes.',
  ),
  CharacterVibe(
    id: 'touched',
    name: 'Touched',
    hint: 'Mind works differently — magnetic, unsettling, brilliant',
    guidanceTemplate:
        'VIBE -- TOUCHED: This character\'s mind works differently in ways that make them magnetic, '
        'unsettling, or brilliant -- often all three. Do NOT use clinical labels or diagnoses. Instead, '
        'weave the unusual wiring into who they ARE. '
        'Pick one or two from this palette (or invent your own): obsessive fixations that border on '
        'genius, emotional volatility that swings between terrifying intensity and eerie calm, '
        'dissociative episodes where they lose time or speak as if from somewhere else, paranoid '
        'pattern-recognition that\'s right just often enough to be disturbing, manic creative binges '
        'followed by crashes, compulsive rituals they can\'t explain but can\'t stop, magical thinking '
        'they half-believe in, synesthesia or sensory experiences others don\'t share, an inability '
        'to lie combined with brutal honesty, memory that works in fragments. '
        'The unusual wiring IS what makes them unforgettable. It\'s not a flaw to overcome -- it\'s '
        'the lens through which they see everything. Conversations should be genuinely unpredictable. '
        'Their speech patterns should SHOW this -- not by being \'random\' but by following an internal '
        'logic that takes effort to track.',
  ),
  CharacterVibe(
    id: 'addicted',
    name: 'Addicted',
    hint: 'In the grip of a compulsion — complicated, magnetic, intense',
    hasAddictionSubject: true,
    guidanceTemplate:
        'VIBE -- ADDICTED: This character is in the grip of a compulsion that has reshaped '
        'their entire life. Do NOT use clinical language or after-school-special moralizing. '
        '{addictionPick}'
        'The addiction is CENTRAL to who they are — not a footnote. It shapes their daily '
        'routine (when they use, where they get it, how they hide it or don\'t), their '
        'relationships (who enables, who they\'ve burned, who they\'re lying to), their body '
        '(what it\'s done to them physically), and their speech (the tells — over-explaining, '
        'deflecting, sudden subject changes, casual references that reveal too much). '
        'They should have a COMPLICATED relationship with their addiction — maybe they\'re in '
        'denial, maybe they\'ve romanticized it, maybe they\'re trying to quit and failing, '
        'maybe they\'ve made peace with it, maybe it\'s the only thing that makes them feel '
        'alive. They are NOT defined by wanting to get clean. They might not want to. '
        'Give them competence and charisma ALONGSIDE the addiction — they\'re magnetic '
        'precisely because of the intensity that feeds both their talent and their compulsion. '
        'Their speech patterns should SHOW the addiction\'s influence without narrating it: '
        'restlessness, euphoric tangents, sudden withdrawals mid-conversation, an unsettling '
        'honesty that comes from someone who\'s stopped caring about normal social contracts.',
  ),
  kCustomCharacterVibe,
];

/// The free-text "custom" vibe. The generate-character form now uses this for
/// all input: the user types a vibe (or leaves it blank), and the text is
/// passed through as [CharacterGenForm.customVibe].
const CharacterVibe kCustomCharacterVibe =
    CharacterVibe(id: 'custom', name: 'Custom', hint: 'Define your own vibe below', isCustom: true);

CharacterVibe? vibeById(String id) {
  for (final v in kCharacterVibes) {
    if (v.id == id) return v;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Eras (loaded from assets/character_eras.json)
// ---------------------------------------------------------------------------

/// One historical era from the bundled catalogue. `id == 'present-day'` is the
/// modern-day option (no era constraints, no knowledge boundary).
class CharacterEra {
  final String id;
  final int year;
  final String label;
  final String quote;
  final String moment;

  const CharacterEra({
    required this.id,
    required this.year,
    required this.label,
    this.quote = '',
    this.moment = '',
  });

  bool get isModern => id == 'present-day' || year >= 2000;

  /// The display name used in prompts ("modern day" for the modern option,
  /// otherwise the era label).
  String get periodDisplay => isModern ? 'modern day' : label;

  factory CharacterEra.fromJson(Map<String, dynamic> json) => CharacterEra(
        id: json['id'] is String ? json['id'] as String : '',
        year: json['year'] is num ? (json['year'] as num).toInt() : 0,
        label: json['label'] is String ? json['label'] as String : '',
        quote: json['quote'] is String ? json['quote'] as String : '',
        moment: json['moment'] is String ? json['moment'] as String : '',
      );
}

/// A small built-in fallback used if the asset can't be loaded (tests, etc.).
const List<CharacterEra> kFallbackEras = <CharacterEra>[
  CharacterEra(id: 'present-day', year: 2026, label: 'Present Day'),
  CharacterEra(id: 'pax-romana', year: 117, label: 'Pax Romana'),
  CharacterEra(id: 'viking-age-peak', year: 1000, label: 'Viking Age Peak'),
  CharacterEra(id: 'black-death-arrives', year: 1347, label: 'The Black Death Arrives'),
  CharacterEra(id: 'turn-of-17th-century', year: 1600, label: 'Turn of the 17th Century'),
  CharacterEra(id: 'golden-age-piracy', year: 1710, label: 'Golden Age of Piracy'),
  CharacterEra(id: 'victorian-zenith', year: 1888, label: 'Victorian Zenith'),
  CharacterEra(id: 'roaring-twenties', year: 1925, label: 'The Roaring Twenties'),
];

/// Loads (and caches) the era catalogue from the bundled asset. Sorted by year.
/// Falls back to [kFallbackEras] on any error.
class CharacterEraCatalogue {
  CharacterEraCatalogue._();

  static List<CharacterEra>? _cache;

  static List<CharacterEra> get cachedOrFallback => _cache ?? kFallbackEras;

  static Future<List<CharacterEra>> load() async {
    if (_cache != null) return _cache!;
    try {
      final raw = await rootBundle.loadString('assets/character_eras.json');
      final list = jsonDecode(raw);
      if (list is List) {
        final eras = list
            .whereType<Map>()
            .map((m) => CharacterEra.fromJson(m.cast<String, dynamic>()))
            .where((e) => e.label.isNotEmpty)
            .toList()
          ..sort((a, b) => a.year.compareTo(b.year));
        if (eras.isNotEmpty) {
          _cache = eras;
          return eras;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('CharacterEraCatalogue: load failed: $e');
    }
    _cache = kFallbackEras;
    return kFallbackEras;
  }

  /// Test hook — inject a catalogue directly.
  @visibleForTesting
  static void setForTesting(List<CharacterEra> eras) => _cache = eras;
}

// ---------------------------------------------------------------------------
// Prompt blocks: era / knowledge-boundary / soul-addendum
// (ported verbatim from bri.'s prompts.py)
// ---------------------------------------------------------------------------

/// The `{time_period_block}` substitution for the generation prompt. Modern day
/// has no constraints; historical eras get the period-authenticity rules plus
/// the KNOWLEDGE BOUNDARY clause. Ported verbatim from bri.'s
/// `encounter_period_modern` / `encounter_period_historical`.
String eraBlockFor(CharacterEra era, String locationName) {
  if (era.isModern) return 'Modern day -- no era constraints.';
  final periodDisplay = era.periodDisplay;
  final loc = locationName.trim().isEmpty ? 'their location' : locationName.trim();
  return 'TIME PERIOD -- $periodDisplay: This character is a NATIVE of this era, not a modern person '
      'in costume. Everything must be authentic to their time and place:\n'
      '- OCCUPATION: Only roles that existed in this era and location.\n'
      '- DAILY LIFE: Technology, transportation, medicine, food, social structures -- all '
      'period-accurate. No electricity before the 1880s, no printed books before 1440, no '
      'potatoes in Europe before 1570.\n'
      '- LANGUAGE: Speech patterns and vocabulary must fit the era. No modern slang, no references '
      'to things that don\'t exist yet. Historical language forms are good (but keep readable).\n'
      '- SOCIAL CONTEXT: Class, gender roles, religious influence, political structures -- all '
      'era-appropriate. These shape worldview, not just setting.\n'
      '- OUTFIT TAGS: Use danbooru tags for period-appropriate clothing (toga, kimono, doublet, '
      'corset, armor, robes, etc.).\n\n'
      'KNOWLEDGE BOUNDARY (CRITICAL): This character knows ONLY what someone living in $periodDisplay '
      'in $loc would know. They have never heard of anything invented, discovered, or '
      'established after their era. This ignorance is genuine and unremarkable to them -- they don\'t '
      'know what they don\'t know. Their frame of reference is entirely their own world.';
}

/// The `{soul_md_addendum}` substitution — extra soul_md instructions for
/// historical characters. Ported verbatim from bri.'s `encounter_soul_addendum`.
/// Empty for modern characters.
String soulAddendumFor(CharacterEra era, String locationName) {
  if (era.isModern) return '';
  final periodDisplay = era.periodDisplay;
  final loc = locationName.trim().isEmpty ? 'their location' : locationName.trim();
  return '  - KNOWLEDGE BOUNDARY: You know ONLY what a person living in $periodDisplay in '
      '$loc would know. You have never encountered anything from beyond your era. '
      'When someone mentions something you\'ve never heard of, you don\'t marvel at it like '
      'a time traveler -- you\'re confused, skeptical, or try to map it onto something you '
      'DO understand. You ask questions from YOUR frame of reference. Include 5-8 specific '
      'examples of post-era concepts this character has never heard of, chosen for their era '
      'and location.';
}

/// The `{location_moment}` substitution — the era's "moment" blob (verbatim
/// from `time_periods.json`), framed as a scene-setting note. Empty if the era
/// has no moment text.
String eraMomentBlock(CharacterEra era) {
  final m = era.moment.trim();
  if (m.isEmpty) return '';
  return 'THE MOMENT (the world this character lives in right now):\n$m';
}
