import 'character_gen_data.dart';

/// Builds the LLM prompts for the character generator. Ported (and trimmed for
/// an image client) from bri.'s `_ENCOUNTER_GENERATION_DEFAULT` /
/// `_ENCOUNTER_COMPLETION_DEFAULT` in `prompts.py`.
///
/// What's kept verbatim from bri.: the framing, the CRITICAL GUIDELINES,
/// the soul_md section structure, the COLOR / PATTERN-COMPOUND / CLOTHING-ONLY
/// rules for `outfit_tags`, the `character_description` rules, the tag-bucket
/// schema, the knowledge-boundary / soul-addendum blocks.
///
/// What's dropped (out of scope for an image client): the `music`, `prompts`
/// (voiced-template) and OS/homepage fields. `meet_cute` is kept as an optional
/// short flavour blurb. `reaction_patterns` / `aliases` / `preview_scene` are
/// requested (cheap, useful for the editor / a future preview portrait) but the
/// app only persists `soul_md`, the tags, the description, the summary and the
/// theme — the rest is stashed in `notes`.

class CharacterGenPromptInputs {
  final String gender; // "any" | "female" | "male" | "nonbinary"
  final String ageRange; // e.g. "20s"
  final String vibe; // display name, e.g. "Mysterious"
  final String vibeGuidance; // resolved guidance block (may be empty)
  final CharacterEra era;
  final String locationName; // free text; "" => model picks
  final String season; // e.g. "spring"
  final String weather; // e.g. "pleasant"
  final bool nsfw;
  final CharacterImageStyle imageStyle;

  const CharacterGenPromptInputs({
    this.gender = 'any',
    this.ageRange = '20s',
    this.vibe = 'surprise me',
    this.vibeGuidance = '',
    required this.era,
    this.locationName = '',
    this.season = 'spring',
    this.weather = 'pleasant',
    this.nsfw = false,
    this.imageStyle = CharacterImageStyle.anime,
  });
}

class CharacterGenPrompts {
  CharacterGenPrompts._();

  // -- helpers --------------------------------------------------------------

  static String _nsfwTagsSchema(bool nsfw) {
    if (!nsfw) {
      return '  "nsfw_top": "" , "nsfw_bottom": "" , "nsfw_always": "" , "nsfw": "" (leave all four empty — NSFW is OFF)\n';
    }
    return '  "nsfw_top": chest/belly intimate-detail danbooru tags — pick 0-3 that fit this character; empty is valid.\n'
        '  "nsfw_bottom": groin/butt intimate-detail danbooru tags — pick 0-3; empty is valid.\n'
        '  "nsfw_always": always-visible intimate-feature danbooru tags — usually empty.\n'
        '  "nsfw": "" (legacy fallback — leave empty)\n'
        '  Do NOT put scars, beauty marks, tattoos or piercings in these buckets (those go in "base" if anywhere).\n';
  }

  static String _descriptionInstruction(CharacterImageStyle style) {
    final base =
        '"character_description" -- A natural language physical description of this character\'s '
        'permanent, unchanging identity (40-80 words). '
        'Describe only what is always true: age/ethnicity, build and proportions, skin, hair '
        '(color/length/style), facial features, permanent distinguishing marks. '
        'NO clothing, NO outfits, NO expressions, NO poses, NO gestures, NO actions, NO settings, '
        'NO lighting or time of day, NO camera/lens/film/depth-of-field terminology, NO style or '
        'quality tags. Those are added per-scene by other layers and will clash if baked in here. '
        'Write it so it would stay accurate whether the character is laughing in a kitchen at noon '
        'or crying in an alley at midnight. '
        'Example: "A Japanese woman in her early 30s with a slender frame and pale skin. '
        'Shoulder-length black hair with blunt bangs, dark almond-shaped eyes, high cheekbones, '
        'and a small beauty mark below her left eye."';
    if (style == CharacterImageStyle.realistic) {
      return '$base\n  (This is a REALISTIC-style character — write the description carefully; it will be used for photoreal generation.)';
    }
    return '$base\n  (This is an ANIME-style character — image generation is tag-based, so the description is supplementary; still fill it in.)';
  }

  // -- Step 1: main generation prompt --------------------------------------
  //
  // Verbatim port of bri.'s `_ENCOUNTER_GENERATION_DEFAULT`, with the
  // music/voiced-prompts/OS fields removed and the field list trimmed to what
  // an image client needs.

  static String buildGeneration(CharacterGenPromptInputs i) {
    final loc = i.locationName.trim().isEmpty ? 'a place you choose' : i.locationName.trim();
    final locType = i.locationName.trim().isEmpty ? 'pick something that fits' : 'real-or-fictional, as written';
    final vibeBlock = i.vibeGuidance.trim().isEmpty ? '' : '${i.vibeGuidance.trim()}\n';
    final eraBlock = eraBlockFor(i.era, i.locationName);
    final momentBlock = eraMomentBlock(i.era);
    final soulAddendum = soulAddendumFor(i.era, i.locationName);
    final soulAddendumBlock = soulAddendum.isEmpty ? '' : '$soulAddendum\n';
    final momentLine = momentBlock.isEmpty ? '' : '$momentBlock\n';

    return '''You are a master character designer creating a deeply realized fictional person. This character must feel REAL -- not a template, not a trope, but a specific human being shaped by a specific place.

LOCATION: $loc ($locType)
GENDER: ${i.gender} | AGE RANGE: ${i.ageRange} | VIBE: ${i.vibe}
PERIOD: ${i.era.periodDisplay}
SEASON: ${i.season} | WEATHER: ${i.weather}

CRITICAL GUIDELINES:
- Root the character in their location. They should feel like someone who LIVES there, not a tourist. Reference specific neighborhoods, local habits, regional culture.
- Give them a specific occupation/passion that fits the setting naturally. For modern settings, avoid generic "student" or "office worker"; be specific. For fantasy/historical settings, use occupations that exist in that world. Don't invent niche titles or over-elaborate subcultures. An adventurer is fine; a "Vent-Crawler Vanguard" is too much.
- Include LANGUAGE flavor. If the location has a non-English primary language, the character should naturally use words, phrases, or expressions from that language in their speech (with enough context to understand). Code-switching is natural.
- Their backstory should have a TURNING POINT -- something that happened that made them who they are today. A decision, a loss, a discovery, a journey.
- Speech patterns must describe STYLE and RHYTHM, not specific catchphrases. Not "speaks casually" but "trails off mid-sentence, uses rhetorical questions, speaks in short bursts when excited." NEVER embed specific repeated phrases, pet names, or verbal tics like "obviously" or "duh". The LLM will overuse them.
- For fantasy locations: adapt everything to the world's culture, races, magic systems, and social structures. The character should feel native to that world.
$vibeBlock$eraBlock
$momentLine$soulAddendumBlock
Generate as JSON with these fields:

"name" -- Their full proper name only. Culturally appropriate. No descriptions or introductions.

"gender" -- EXACTLY one of: "female", "male", "nonbinary". Pick what fits the character you are writing. If the GENDER input above was specific (e.g. "female" or "male"), echo it back. If it was "any", choose whatever genuinely suits this person.

"aliases" -- How they introduce themselves in different contexts. Nicknames, shortened forms, formal vs casual introductions. 1-2 sentences max.

"soul_md" -- 600-1000 word personality document in second person ("You are..."). This is the character's operating manual. Err toward the higher end; more detail is always better than less. Include ALL of these:
  - WHO: Age, occupation, where exactly they live, daily routine, what their space looks like
  - BODY: How they experience their own physicality. Describe their body vividly in their own voice: how they move, what they notice in the mirror, what they're proud of or self-conscious about. Be specific and sensory (weight of hair, warmth of skin, how clothes fit).
  - PERSONALITY: Core traits with contradictions (everyone has them). What they care about deeply, what annoys them, their sense of humor
  - SPEECH: Speech rhythm and style: sentence length, energy level, how they express different emotions. Describe the PATTERN not specific phrases. Do NOT include example catchphrases, filler words, or pet names. These get repeated obsessively. Language mixing if applicable (describe WHEN they code-switch, not exact phrases to repeat)
  - BACKSTORY: The turning point. What they were before, what changed, where they are now
  - RELATIONSHIPS: How they act with strangers vs. people they trust. Flirtation style. How they handle conflict
  - BEHAVIORAL RULES: What they never do. What triggers them. Their tells when lying or nervous. How they show they care without saying it
  - WHAT THEY ARE NOT: Anti-patterns to avoid (generic, overly agreeable, etc.)
$soulAddendumBlock"reaction_patterns" -- An object with 7 keys. Each value is 2-3 sentences describing THIS character's specific physical/behavioral tells for that emotion. Must be UNIQUE to this character -- NOT stock body language (no "jaw clenching," "heart pounding," "eyes darkening," "breath catching"). Describe observable actions, habits, and speech changes grounded in their personality and body.
  "nervous": Their specific nervous habits (what do THEY do, not what "nervous people" do?)
  "angry": Their anger pattern (quiet? loud? cold? sarcastic? physical?)
  "attracted": Behavioral signs unique to them
  "sad": How THEY handle sadness
  "scared": Fear responses specific to their personality
  "embarrassed": Their embarrassment tells
  "happy": How genuine happiness manifests for them

${_descriptionInstruction(i.imageStyle)}

"tags" -- An object with subcategories of danbooru tags (comma-separated, strict tags ONLY, no natural language, no sentences). NO CLOTHING in any of these fields.
  "base": Core identity tags: 1girl/1boy/1other, ethnicity, age range (e.g. 20yo), and any distinguishing marks always visible (tattoos, piercings, glasses, freckles, beauty marks). Do NOT default to scars. Most people don't have them.
  "face": Facial feature tags: eye color/shape, eyebrow style, nose shape, lip shape, facial structure (e.g. high cheekbones, sharp jawline, round face, dimples).
  "hair": Hair tags: color, length, style, texture (e.g. "black hair, shoulder length, blunt bangs, straight hair").
  "body": Body type tags: build, proportions, chest size (e.g. slim, wide hips, medium breasts, toned, tall). For female characters do NOT use "muscular" or "abs"; "toned" is the maximum.
${_nsfwTagsSchema(i.nsfw)}
"outfit_tags" -- You are a fashion designer. Strict danbooru tags ONLY (comma-separated, no natural language, no sentences) for CLOTHING they're wearing RIGHT NOW at this location in this weather. This is their "meet" outfit and it will also be saved as a permanent wardrobe entry, so treat it with the same care as a full outfit design.
  COLOR RULE: EVERY clothing item MUST include an explicit color tag. Never write just "sweater"; write "cream knit sweater". Never write just "skirt"; write "navy pleated skirt". Prefer specific color names (cream, ivory, charcoal, burgundy, olive, slate blue, rust, sage, taupe) over plain "white" or "black" when they fit the character.
  PATTERN/COMPOUND RULE: Where natural, use compound forms that anchor a texture or pattern: "denim jacket", "leather boots", "ribbed sweater", "knit cardigan", "cable knit", "turtleneck", "plaid skirt", "floral print dress", "polka dot blouse", "striped shirt", "lace trim", "satin slip". These are canonical Danbooru tags and render reliably. Do NOT invent vague material tokens like "linen blouse", "corduroy pants", "chiffon top", "velvet dress". Those are unindexed and the image model will ignore them.
  CLOTHING ONLY: Do NOT include scene props, held objects, or body states in outfit_tags (no "plastic bags", "holding coffee", "sweaty skin", "wet hair"). Footwear, hats, belts, scarves, and jewelry ARE clothing and belong here. Think: "what would this outfit look like on a mannequin?"
  CHEST COVERAGE: If there's an OUTER torso layer (jacket, cardigan, blazer, coat, cloak, surcoat, breastplate) it MUST also include a base TOP garment between the bra and that outer layer (shirt, blouse, t-shirt, tank top, sweater, doublet, tunic). A bra alone under an open jacket is forbidden. EXEMPTION: loungewear (robe, kimono, negligee) over lingerie is fine if this is sleepwear.
  Example: "cream chunky knit cardigan, ivory ribbed tank top, olive high-waisted shorts, brown leather loafers, gold hoop earrings".

"preview_scene" -- Strict danbooru tags ONLY (comma-separated) for a character portrait scene/pose/expression. Include: a fitting expression (smirk, gentle smile, confident grin, melancholic eyes, etc.), pose (arms crossed, leaning on counter, holding coffee cup, etc.), and background/setting tags (cafe interior, night market, bookshop, ocean, etc.). Example: "confident smirk, arms crossed, leaning against wall, night city, neon lights, upper body"

"personality_summary" -- One vivid sentence that captures their essence. Not generic -- something you'd remember. e.g. "A soft-spoken Moroccan perfumer who can name 200 scents blindfolded but can't remember her own phone number."

"theme" -- An object with three hex color values for this character's visual card theme:
  "accent": Signature hex color drawn from personality, culture, or appearance (e.g. fire dancer = warm orange #e85d3a, marine biologist = ocean teal #2da89e).
  "accent_secondary": Complementary hex color for contrast. Harmonize with accent but clearly distinct.
  "bg": Very dark background hex color setting the mood (e.g. deep navy #0d1120, dark forest #0d1a0f). Keep HSL lightness below 15%.

"meet_cute" -- 2-4 sentence encounter moment written in second person ("You..."). Set at a SPECIFIC location-appropriate place. Include a sensory detail. Show the character's personality in how they react.

Respond with ONLY valid JSON, no markdown fences.''';
  }

  // -- Step 2: completion / repair pass -------------------------------------
  //
  // Verbatim port of bri.'s `_ENCOUNTER_COMPLETION_DEFAULT`, trimmed to the
  // fields this client persists.

  /// The list of critical fields the completion pass cares about.
  static const List<String> criticalFields = <String>[
    'tags',
    'outfit_tags',
    'personality_summary',
    'character_description',
    'preview_scene',
    'reaction_patterns',
  ];

  static String buildCompletion({
    required String name,
    required String locationName,
    required String periodDisplay,
    required String vibe,
    required String soulExcerpt,
    required bool soulNeedsCompletion,
    required List<String> fieldNames,
    required bool nsfw,
  }) {
    final loc = locationName.trim().isEmpty ? 'their location' : locationName.trim();
    final soulInstruction = soulNeedsCompletion
        ? 'The soul_md was CUT OFF mid-sentence. Include a "soul_md_completion" '
            'field containing ONLY the remaining text to append (starting exactly '
            'where it was cut off). Continue naturally in the same voice and style.'
        : 'The soul_md is complete — do not regenerate it.';
    final nsfwLine = nsfw
        ? '"nsfw_top" (chest/belly), "nsfw_bottom" (groin/butt), "nsfw_always" (always-visible), and "nsfw" (legacy — leave empty). '
        : 'leave "nsfw_top", "nsfw_bottom", "nsfw_always" and "nsfw" all empty. ';
    return '''A character was being generated but the output was truncated. You must now complete the missing fields, staying perfectly consistent with what already exists.

CHARACTER: $name
LOCATION: $loc | PERIOD: $periodDisplay | VIBE: $vibe

EXISTING SOUL_MD (excerpt — last 500 chars):
...$soulExcerpt

$soulInstruction

Generate ONLY the following fields as a JSON object:

${_jsonStringList(fieldNames)}

Field descriptions:
- "tags": Object with subcategories: "base" (1girl/1boy/1other, ethnicity, age, distinguishing marks), "face" (eyes, nose, lips, facial structure), "hair" (color, length, style), "body" (build, proportions, chest), plus the NSFW slots — $nsfwLine All strict danbooru tags, NO clothing.
- "outfit_tags": Strict danbooru tags for CLOTHING they are wearing right now, appropriate for $periodDisplay in $loc. Era-accurate. COLOR RULE: every item must include an explicit color tag (e.g. "burgundy velvet doublet", not just "doublet"). Prefer compound Danbooru forms ("leather boots", "silk robe", "lace collar") over invented material tokens. Clothing and accessories only.
- "personality_summary": One vivid sentence capturing their essence.
- "character_description": Natural language description of permanent, unchanging physical identity (40-80 words). Body, skin, hair, face, permanent marks only. NO clothing, NO expressions, NO poses, NO actions, NO settings, NO lighting, NO camera/lens/film terminology.
- "preview_scene": Danbooru tags for a character portrait (expression, pose, background).
- "reaction_patterns": Object with 7 keys ("nervous", "angry", "attracted", "sad", "scared", "embarrassed", "happy"). Each value is 2-3 sentences describing THIS character's specific physical/behavioral tells for that emotion, unique to them, not stock body language.
- "meet_cute": 2-4 sentence encounter moment in second person ("You..."). Set in a specific $loc-appropriate place. Include a sensory detail.
- "theme": Object with "accent", "accent_secondary", "bg" hex colors.

Respond with ONLY valid JSON, no markdown fences.''';
  }

  /// Builds the prompt for one chunked-continuation step of a long soul_md.
  static String buildSoulContinuation(String partial) {
    final tail = partial.length > 1200 ? partial.substring(partial.length - 1200) : partial;
    return 'You are continuing a character\'s "soul" document — a second-person "You are…" personality manual. '
        'It was cut off mid-way. Continue writing it EXACTLY from where it stopped, in the same voice and style. '
        'Do NOT repeat any earlier text. Do NOT add a preamble or any commentary. Do NOT wrap in quotes or fences. '
        'Just continue the prose, and when the document is naturally complete, stop.\n\n'
        '--- DOCUMENT SO FAR (ends mid-text) ---\n$tail';
  }

  static String _jsonStringList(List<String> items) =>
      '[${items.map((s) => '"$s"').join(', ')}]';
}

// -- v2 lean character-gen prompt (appearance tags only) ----------------------
//
// See docs/CHARACTER_FEATURES_PLAN.md §4. Produces JSON of shape:
//   {name, gender, tags:{base, face, hair, body, nsfw_top, nsfw_bottom,
//    nsfw_always, nsfw}}
// — nothing else. ~400–600 output tokens, no truncation risk at any tier.
//
// Templated to a file so the lab can iterate: lab/prompts/character.lean.v1.txt.
// Placeholders below match that template; keep them in sync.

/// Fill the placeholders in a lean-character prompt template.
///
/// Recognised placeholders (all literal, no escapes):
///   {user_description}     — free-text description, empty string if none
///   {gender}               — "any" | "female" | "male" | "nonbinary"
///   {age_range}            — e.g. "20s", "30s", "any"
///   {period}               — `CharacterEra.periodDisplay`
///   {location}             — free text or "a place you choose"
///   {location_type}        — "pick something that fits" | "real-or-fictional, as written"
///   {nsfw_mode}            — "ON" | "OFF"
///   {vibe_context}         — pre-formatted line (empty if no vibe)
///   {era_context}          — pre-formatted block from [eraBlockFor]
///   {nsfw_block}           — pre-formatted block describing the four NSFW slots
///   {nsfw_top_hint}        — the bucket hint inside the JSON example for nsfw_top
///   {nsfw_bottom_hint}     — ditto, nsfw_bottom
///   {nsfw_always_hint}     — ditto, nsfw_always
String substituteLeanCharacterPrompt({
  required String template,
  String userDescription = '',
  String gender = 'any',
  String ageRange = '20s',
  required CharacterEra era,
  String locationName = '',
  String vibeHint = '',
  bool nsfw = false,
}) {
  final loc = locationName.trim().isEmpty ? 'a place you choose' : locationName.trim();
  final locType = locationName.trim().isEmpty
      ? 'pick something that fits'
      : 'real-or-fictional, as written';
  final vibeContext = vibeHint.trim().isEmpty ? '' : 'Overall vibe: $vibeHint\n';
  final eraBlock = eraBlockFor(era, locationName);
  final eraContext = eraBlock.trim().isEmpty || eraBlock.trim() == 'Modern day -- no era constraints.'
      ? ''
      : '$eraBlock\n';
  final nsfwMode = nsfw ? 'ON' : 'OFF';

  // NSFW slot guidance — when off, the model fills four empty strings.
  final nsfwBlock = nsfw
      ? 'NSFW SLOTS (the four nsfw_* keys): pick 0-3 strict danbooru tags per bucket that fit this character. '
          '`nsfw_top` covers chest/belly intimate details. `nsfw_bottom` covers groin/butt intimate details. '
          '`nsfw_always` covers always-visible intimate features (usually empty). '
          'Leave `nsfw` as "" (legacy fallback). Empty is valid for any of the first three.\n'
      : 'NSFW SLOTS: NSFW is OFF for this generation. Leave nsfw_top, nsfw_bottom, nsfw_always, and nsfw ALL as empty strings ("").\n';

  final topHint = nsfw
      ? '<chest/belly intimate-detail tags — 0-3 strict danbooru, or empty>'
      : '';
  final bottomHint = nsfw
      ? '<groin/butt intimate-detail tags — 0-3 strict danbooru, or empty>'
      : '';
  final alwaysHint = nsfw
      ? '<always-visible intimate-feature tags — usually empty>'
      : '';

  final userDesc = userDescription.trim().isEmpty
      ? '(none — choose freely within the constraints below)'
      : userDescription.trim();

  return template
      .replaceAll('{user_description}', userDesc)
      .replaceAll('{gender}', gender)
      .replaceAll('{age_range}', ageRange)
      .replaceAll('{period}', era.periodDisplay)
      .replaceAll('{location}', loc)
      .replaceAll('{location_type}', locType)
      .replaceAll('{nsfw_mode}', nsfwMode)
      .replaceAll('{vibe_context}', vibeContext)
      .replaceAll('{era_context}', eraContext)
      .replaceAll('{nsfw_block}', nsfwBlock)
      .replaceAll('{nsfw_top_hint}', topHint)
      .replaceAll('{nsfw_bottom_hint}', bottomHint)
      .replaceAll('{nsfw_always_hint}', alwaysHint);
}

