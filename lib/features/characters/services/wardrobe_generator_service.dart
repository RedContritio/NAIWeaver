import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/services/text_gen_service.dart';
import '../models/closet_outfit.dart';

/// One generated outfit + whether the model flagged it primary.
class GeneratedOutfit {
  final ClosetOutfit outfit;
  final bool isPrimary;
  const GeneratedOutfit(this.outfit, this.isPrimary);
}

/// Generates a wardrobe for a character via [TextGenService]. Ports bri.'s
/// `_WARDROBE_GENERATE_PROMPT` (the no-meet-cute path) verbatim, with the
/// hard rules intact.
///
/// To dodge low-tier output caps (max_length ≈ 150), outfits are requested in
/// small batches; if a batch comes back truncated we salvage complete `{...}`
/// objects from the array. A `~600–1000`-token 7-outfit JSON simply won't fit
/// in one shot on a Tablet/free tier.
class WardrobeGeneratorService {
  final TextGenService _service;

  WardrobeGeneratorService(this._service);

  /// Batch size: keep each call small enough to fit a Tablet-tier cap.
  static int _batchSizeFor(int maxTokens) {
    if (maxTokens <= 200) return 2;
    if (maxTokens <= 600) return 3;
    if (maxTokens <= 1500) return 5;
    return 7;
  }

  Future<List<GeneratedOutfit>> generate({
    required String characterTags,
    required int count,
    String eraHint = '',
    String vibeHint = '',
    String model = kDefaultTextModel,
    int maxTokens = 150,
  }) async {
    final batch = _batchSizeFor(maxTokens);
    final results = <GeneratedOutfit>[];
    var remaining = count;
    var safety = 0;
    while (remaining > 0 && safety < 10) {
      safety++;
      final n = remaining < batch ? remaining : batch;
      final got = await _generateBatch(
        characterTags: characterTags,
        count: n,
        eraHint: eraHint,
        vibeHint: vibeHint,
        model: model,
        maxTokens: maxTokens,
      );
      if (got.isEmpty) break; // give up rather than loop forever
      results.addAll(got);
      remaining -= got.length;
      // If a batch under-delivered repeatedly, also stop.
      if (got.length < n && results.length >= count - 1) break;
    }
    return results.take(count).toList();
  }

  Future<List<GeneratedOutfit>> _generateBatch({
    required String characterTags,
    required int count,
    required String eraHint,
    required String vibeHint,
    required String model,
    required int maxTokens,
  }) async {
    final prompt = _buildPrompt(
      count: count,
      characterTags: characterTags.trim().isEmpty ? 'anime girl' : characterTags.trim(),
      eraHint: eraHint,
      vibeHint: vibeHint,
    );

    String raw = await _service.generate(TextGenRequest(
      input: prompt,
      model: model,
      params: TextGenParams.glmDefault().copyWith(
        temperature: 0.8,
        maxLength: maxTokens,
      ),
    ));

    var parsed = _extractOutfits(raw);

    // If truncated and nothing salvageable, try one continuation pass.
    if (parsed.isEmpty) {
      try {
        final cont = await _service.generate(TextGenRequest(
          input: '$prompt\n$raw\n\nContinue the JSON array from where you left off. Output ONLY the remaining JSON.',
          model: model,
          params: TextGenParams.glmDefault().copyWith(temperature: 0.7, maxLength: maxTokens),
        ));
        parsed = _extractOutfits('$raw$cont');
      } catch (_) {}
    }

    return [
      for (final m in parsed)
        GeneratedOutfit(
          ClosetOutfit.fromGeneratedJson(m),
          m['primary'] == true || m['meet_cute'] == true,
        ),
    ];
  }

  // -- Prompt (verbatim port of bri.'s _WARDROBE_GENERATE_PROMPT, no-meet-cute
  //    path; underwear_rule = the generic non-historical case unless an era
  //    hint is given) ---------------------------------------------------------

  String _buildPrompt({
    required int count,
    required String characterTags,
    required String eraHint,
    required String vibeHint,
  }) {
    final eraContext = eraHint.isEmpty
        ? ''
        : 'Era / setting: $eraHint — make every outfit period-correct for this era.\n';
    final vibeContext = vibeHint.isEmpty ? '' : 'Overall vibe: $vibeHint\n';
    final underwearRule = eraHint.isEmpty
        ? '(No underwear rule — modern character. Base layers like "cotton bra"/"cotton panties" are fine but hidden under outer clothing.)'
        : 'BASE LAYER RULE (HARD CONSTRAINT): Every outfit MUST include era-appropriate base layer(s) authentic to $eraHint. '
            'FORBIDDEN: modern bras or panties of any kind (cotton, lace, satin, sports, thong, bralette, boyshorts). '
            'Use historical undergarments (chemise, loincloth, corset, petticoat, bloomers, etc.) as appropriate to the period and social class. '
            'If the COLOR RULE examples mention bras/panties, IGNORE them — that rule\'s examples are for modern characters; this character is not modern.';

    return '''You are a fashion designer creating outfits for an anime character. Generate $count distinct outfits suitable for different weather conditions and seasons.

Character body & appearance (BACKGROUND ONLY — DO NOT repeat these in `tags`. `tags` is a clothing manifest, nothing else): $characterTags
$vibeContext${eraContext}For each outfit, provide:
- name: A short, evocative name (e.g. "Winter Cozy", "Summer Festival", "Rainy Day Chic")
- tags: Danbooru-style CLOTHING tags, comma-separated (e.g. "cream knit sweater, turtleneck, long sleeves, navy pleated skirt, charcoal tights, brown ankle boots")
- seasons: Array of seasons this outfit suits ["spring", "summer", "fall", "winter"]
- weather: Array of weather conditions ["clear", "cloudy", "rain", "snow", "storm", "hot", "cold", "mild", "fog", "humid"]
- activities: Array of activities ["casual", "indoor", "outdoor", "formal", "studying", "exercise", "shopping", "date"]
- temperature_range: [min_celsius, max_celsius] range where this outfit is comfortable
- slots: Optional time-slot hint ["morning"|"daytime"|"evening"|"sleep"], or [] for any. Use ["sleep"] for pajamas only.
- primary: OPTIONAL boolean. Set to true on EXACTLY ONE outfit (or omit entirely from all).

TAG SCOPE — CRITICAL: `tags` lists CLOTHING ONLY. Each outfit should be 4–7 garment tags total (base layer + outer pieces + footwear). Do NOT stack three robes "for layering" — pick ONE outer garment per outfit.

EXCLUDE entirely from `tags` (these belong to the character or scene, not the outfit):
- Body: hair, eyes, skin, build, breasts, shoulders, thighs, scars, freckles, mineral stains, broken nose, broad face, etc.
- Pose / expression: smile, asymmetrical smile, hand shielding eyes, hunched shoulders, crossed arms, etc.
- Weather sensations: wind-flushed cheeks, sweat-gleamed, rain-streamed, visible breath, mist-breath, shivering, sodden, water-darkened, cling of wet linen, mud on calves, etc.
- Environment / time / mood: morning light, afternoon, brazier-warmed, festive, discreet, etc.
- Generic descriptors: "ancient greek clothes", "practical workwear", "elegant draping", "warm layered fabrics" — these are categories, not garments. Drop them.

IMPORTANT: Tags must be danbooru-style tags that work well with NovelAI image generation. Focus on specific clothing items, materials, and styles. Cover a variety of weather and seasons across the $count outfits.

COLOR RULE: EVERY clothing item MUST include an explicit color tag. Never write just "sweater" — write "cream knit sweater". Never write just "skirt" — write "navy pleated skirt". Use specific color names (cream, ivory, charcoal, burgundy, olive, slate blue, rust, sage, taupe) not just "white" or "black". Colors make outfits coherent and distinct in generated images.

PATTERN/COMPOUND RULE: use canonical Danbooru compounds ("denim jacket", "leather boots", "ribbed sweater", "cable knit", "turtleneck", "plaid skirt", "floral print dress", "polka dot blouse", "striped shirt", "lace trim", "satin slip"). Do NOT invent vague material tokens ("linen blouse", "corduroy pants", "chiffon top", "velvet dress") — those are unindexed and the image model ignores them.

CHEST COVERAGE RULE (HARD CONSTRAINT): Whenever the outfit includes an OUTER torso layer — jacket, cardigan, blazer, coat, cloak, cape, surcoat, tabard, hauberk, breastplate, cuirass, plate armor — it MUST also include a base TOP garment layered between the bra and that outer layer (shirt, blouse, t-shirt, tank top, sweater, gambeson, doublet, tunic, etc.). A bra alone under an open jacket is forbidden — open or unbuttoned outerwear must reveal a real shirt, not skin-on-bra. EXEMPTION: this rule does not apply when the outfit's outer layer is loungewear (robe, bathrobe, kimono, negligee, peignoir) and the time slot is "sleep" — in that case bra/lingerie under an open robe is allowed and period-appropriate.

$underwearRule

Respond with ONLY valid JSON: {"outfits": [...]}
No markdown fences, no explanation.''';
  }

  // -- Robust JSON extraction (ported from bri.'s _extract_json /
  //    _repair_truncated_wardrobe_json) ---------------------------------------

  List<Map<String, dynamic>> _extractOutfits(String raw) {
    final data = _extractJson(raw);
    if (data == null) return const [];
    if (data is List) {
      return data.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
    }
    if (data is Map) {
      for (final key in ['outfits', 'wardrobe', 'items', 'clothing']) {
        final v = data[key];
        if (v is List) {
          return v.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
        }
      }
      for (final v in data.values) {
        if (v is List) {
          return v.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
        }
      }
    }
    return const [];
  }

  dynamic _extractJson(String raw) {
    var text = raw.trim();
    // strip <think>…</think>
    final split = splitThinkBlock(text);
    text = split.answer.trim();
    // strip markdown fences
    text = text.replaceFirst(RegExp(r'^```(?:json)?\s*\n?'), '');
    text = text.replaceFirst(RegExp(r'\n?```\s*$'), '');
    text = text.trim();
    try {
      return jsonDecode(text);
    } catch (_) {}
    // scan for first { or [
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == '{' || ch == '[') {
        final fragment = text.substring(i);
        try {
          return jsonDecode(fragment);
        } catch (_) {}
        final repaired = _repairTruncated(fragment);
        if (repaired != null) return repaired;
        break;
      }
    }
    if (kDebugMode) debugPrint('WardrobeGeneratorService: no valid JSON in response');
    return null;
  }

  dynamic _repairTruncated(String text) {
    var lastComplete = -1;
    var depth = 0;
    var inStr = false;
    var escape = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (escape) {
        escape = false;
        continue;
      }
      if (ch == '\\') {
        escape = true;
        continue;
      }
      if (ch == '"') {
        inStr = !inStr;
        continue;
      }
      if (inStr) continue;
      if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth >= 0) lastComplete = i;
      }
    }
    if (lastComplete < 0) return null;
    final truncated = text.substring(0, lastComplete + 1);
    for (final suffix in [']}', ']}}', '']) {
      try {
        final result = jsonDecode(truncated + suffix);
        if (result is Map || result is List) return result;
      } catch (_) {}
    }
    return null;
  }
}
