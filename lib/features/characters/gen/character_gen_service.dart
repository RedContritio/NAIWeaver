import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/services/text_gen_service.dart';
import '../models/closet_outfit.dart';
import '../models/saved_character.dart';
import '../services/wardrobe_generator_service.dart';
import 'character_gen_data.dart';
import 'character_gen_prompts.dart';

/// The form inputs collected from the user.
class CharacterGenForm {
  /// "any" | "female" | "male" | "nonbinary".
  final String gender;
  final CharacterVibe vibe;
  final String customVibe; // only for vibe.isCustom
  final String addictionSubject; // only for vibe.hasAddictionSubject
  final CharacterEra era;
  final String location; // free text; "" => model picks
  final bool nsfw;
  final CharacterImageStyle imageStyle;
  final int wardrobeCount;

  const CharacterGenForm({
    this.gender = 'any',
    required this.vibe,
    this.customVibe = '',
    this.addictionSubject = '',
    required this.era,
    this.location = '',
    this.nsfw = false,
    this.imageStyle = CharacterImageStyle.anime,
    this.wardrobeCount = 5,
  });
}

/// Coarse pipeline steps, surfaced to the progress UI.
enum CharacterGenStep { preparing, generating, completing, wardrobe, saving, done }

extension CharacterGenStepX on CharacterGenStep {
  String get label {
    switch (this) {
      case CharacterGenStep.preparing:
        return 'Preparing…';
      case CharacterGenStep.generating:
        return 'Creating character…';
      case CharacterGenStep.completing:
        return 'Completing fields…';
      case CharacterGenStep.wardrobe:
        return 'Generating wardrobe…';
      case CharacterGenStep.saving:
        return 'Saving…';
      case CharacterGenStep.done:
        return 'Done';
    }
  }
}

/// Progress report passed to the caller-supplied callback.
class CharacterGenProgress {
  final CharacterGenStep step;

  /// Sub-progress within the step, e.g. wardrobe outfits done/total. Null when
  /// there's nothing meaningful to count.
  final int? current;
  final int? total;
  final String? detail;

  const CharacterGenProgress(this.step, {this.current, this.total, this.detail});

  String get text {
    var s = step.label;
    if (current != null && total != null) s = '$s ($current/$total)';
    if (detail != null && detail!.isNotEmpty) s = '$s — $detail';
    return s;
  }
}

/// Thrown when the user cancels mid-pipeline.
class CharacterGenCancelled implements Exception {
  const CharacterGenCancelled();
  @override
  String toString() => 'Character generation cancelled';
}

/// A cancellation flag the caller flips to abort the pipeline. The service
/// checks it between steps (and between continuation calls) and throws
/// [CharacterGenCancelled]. Nothing is written to disk until the very end, so a
/// cancel leaves no half-written files.
class CharacterGenCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
  void throwIfCancelled() {
    if (_cancelled) throw const CharacterGenCancelled();
  }
}

/// The fully-assembled result of a generation run: a [SavedCharacter] plus its
/// starter closet (the meet outfit first, marked primary, then any wardrobe
/// outfits). The caller persists these via `CharacterLibraryService` /
/// `ClosetService`.
class GeneratedCharacter {
  final SavedCharacter character;
  final List<ClosetOutfit> closet;
  const GeneratedCharacter(this.character, this.closet);
}

/// Orchestrates building a complete [SavedCharacter] from a [CharacterGenForm].
///
/// Pipeline (ported from bri.'s `generate_encounter`, simplified for an image
/// client):
///   1. main generation LLM call → parse JSON (with truncation repair).
///   2. completion / repair pass: fill missing/truncated fields with a 2nd
///      call; if `soul_md` was cut off, loop continuation calls to finish it.
///   3. starter wardrobe: reuse [WardrobeGeneratorService].
///   4. assemble + return (caller saves).
///
/// All LLM calls go through [TextGenService.generate]. The free/Tablet tier's
/// ~150-token output cap is handled by the chunked-continuation loop in step 2
/// (and the batching inside [WardrobeGeneratorService] in step 3).
class CharacterGenService {
  final TextGenService _service;
  final String model;
  final int maxTokens;

  /// Safety ceiling on the soul_md continuation loop (tokens of *appended*
  /// text). Stops the loop on low-tier accounts before it burns forever.
  static const int _soulMaxAppendTokens = 1500;

  CharacterGenService(
    this._service, {
    this.model = kDefaultTextModel,
    this.maxTokens = 150,
  });

  Future<GeneratedCharacter> generate(
    CharacterGenForm form, {
    void Function(CharacterGenProgress)? onProgress,
    CharacterGenCancelToken? cancelToken,
  }) async {
    final token = cancelToken ?? CharacterGenCancelToken();
    void progress(CharacterGenProgress p) => onProgress?.call(p);
    void check() => token.throwIfCancelled();

    progress(const CharacterGenProgress(CharacterGenStep.preparing));
    check();

    final vibeGuidance = form.vibe.resolvedGuidance(
      customVibe: form.customVibe,
      addictionSubject: form.addictionSubject,
    );
    final inputs = CharacterGenPromptInputs(
      gender: form.gender,
      vibe: form.vibe.name,
      vibeGuidance: vibeGuidance,
      era: form.era,
      locationName: form.location,
      season: _currentSeason(),
      weather: form.era.isModern ? 'pleasant' : 'typical seasonal weather for the region',
      nsfw: form.nsfw,
      imageStyle: form.imageStyle,
    );

    // -- Step 1: main generation ------------------------------------------
    progress(const CharacterGenProgress(CharacterGenStep.generating));
    final genPrompt = CharacterGenPrompts.buildGeneration(inputs);
    final raw1 = await _callLlm(genPrompt, temperature: 0.95);
    check();
    var result = _parseCharacterJson(raw1);
    if (result == null) {
      throw TextGenException(
        'The model didn\'t return usable character JSON. Try again, or pick a higher-tier '
        'account / larger output length.',
      );
    }

    // -- Step 2: completion / repair pass + chunked soul_md ---------------
    progress(const CharacterGenProgress(CharacterGenStep.completing));
    result = await _completeCharacter(result, inputs, token, progress);
    check();

    // Ensure the bare minimum is present.
    final name = _str(result['name']).trim().isEmpty ? 'Unnamed' : _str(result['name']).trim();
    final soulMd = _str(result['soul_md']);
    final genderOut = _normaliseGender(_str(result['gender']), form.gender);

    final tags = (result['tags'] is Map)
        ? (result['tags'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final outfitTags = _str(result['outfit_tags']).trim();
    final personalitySummary = _str(result['personality_summary']).trim();
    final characterDescription = _str(result['character_description']).trim();
    final theme = (result['theme'] is Map) ? (result['theme'] as Map).cast<String, dynamic>() : null;

    // -- Step 3: starter wardrobe ------------------------------------------
    final bodyTagParts = <String>[
      _str(tags['base']).trim(),
      _str(tags['face']).trim(),
      _str(tags['hair']).trim(),
      _str(tags['body']).trim(),
    ].where((s) => s.isNotEmpty).toList();
    final bodyTags = bodyTagParts.join(', ');

    final closet = <ClosetOutfit>[];
    // The meet outfit becomes the first (primary) closet entry.
    if (outfitTags.isNotEmpty) {
      closet.add(ClosetOutfit.create(name: 'Meet Outfit', tags: outfitTags));
    }

    if (form.wardrobeCount > 0) {
      progress(CharacterGenProgress(CharacterGenStep.wardrobe, current: 0, total: form.wardrobeCount));
      check();
      try {
        final wardrobe = WardrobeGeneratorService(_service);
        final outfits = await wardrobe.generate(
          characterTags: bodyTags.isEmpty ? name : bodyTags,
          count: form.wardrobeCount,
          eraHint: form.era.isModern ? '' : form.era.label,
          vibeHint: form.vibe.isCustom ? form.customVibe : form.vibe.name,
          model: model,
          maxTokens: maxTokens,
        );
        check();
        for (final g in outfits) {
          closet.add(g.outfit);
        }
        progress(CharacterGenProgress(
          CharacterGenStep.wardrobe,
          current: outfits.length,
          total: form.wardrobeCount,
        ));
      } on CharacterGenCancelled {
        rethrow;
      } catch (e) {
        // A wardrobe failure isn't fatal — the character is still useful with
        // just the meet outfit.
        if (kDebugMode) debugPrint('CharacterGenService: wardrobe step failed: $e');
      }
    }

    // -- Step 4: assemble --------------------------------------------------
    progress(const CharacterGenProgress(CharacterGenStep.saving));
    check();

    final primaryOutfitId = closet.isEmpty ? null : closet.first.id;
    final notes = _buildNotes(result);

    final character = SavedCharacter(
      id: _genId(),
      name: name,
      gender: genderOut,
      baseTags: _str(tags['base']).trim(),
      faceTags: _str(tags['face']).trim(),
      hairTags: _str(tags['hair']).trim(),
      bodyTags: _str(tags['body']).trim(),
      nsfwTop: form.nsfw ? _str(tags['nsfw_top']).trim() : '',
      nsfwBottom: form.nsfw ? _str(tags['nsfw_bottom']).trim() : '',
      nsfwAlways: form.nsfw ? _str(tags['nsfw_always']).trim() : '',
      characterDescription: characterDescription,
      soulMd: soulMd,
      personalitySummary: personalitySummary,
      themeAccent: _hexOrNull(theme?['accent']),
      themeAccentSecondary: _hexOrNull(theme?['accent_secondary']),
      themeBg: _hexOrNull(theme?['bg']),
      primaryOutfitId: primaryOutfitId,
      notes: notes,
    );

    progress(const CharacterGenProgress(CharacterGenStep.done));
    return GeneratedCharacter(character, closet);
  }

  // -- step 2 internals ---------------------------------------------------

  /// Detects missing/truncated fields and fixes them with a 2nd LLM call; if
  /// `soul_md` was cut off mid-sentence, loops continuation calls to finish it.
  /// Ported from bri.'s `_run_completion_pass`.
  Future<Map<String, dynamic>> _completeCharacter(
    Map<String, dynamic> result,
    CharacterGenPromptInputs inputs,
    CharacterGenCancelToken token,
    void Function(CharacterGenProgress) progress,
  ) async {
    // 2a. finish soul_md by continuation if it was cut off.
    var soulMd = _str(result['soul_md']);
    var appendedTokensApprox = 0;
    var loops = 0;
    while (soulMdTruncated(soulMd) && loops < 8 && appendedTokensApprox < _soulMaxAppendTokens) {
      token.throwIfCancelled();
      loops++;
      progress(CharacterGenProgress(
        CharacterGenStep.completing,
        detail: 'extending personality ($loops)',
      ));
      final contPrompt = CharacterGenPrompts.buildSoulContinuation(soulMd);
      String chunk;
      try {
        chunk = await _callLlm(contPrompt, temperature: 0.9);
      } catch (e) {
        if (kDebugMode) debugPrint('CharacterGenService: soul continuation failed: $e');
        break;
      }
      chunk = _stripFencesAndThink(chunk).trim();
      if (chunk.isEmpty) break;
      // Avoid an infinite no-progress loop if the model just echoes the tail.
      if (soulMd.endsWith(chunk)) break;
      soulMd = _joinContinuation(soulMd, chunk);
      appendedTokensApprox += (chunk.length / 4).ceil();
    }
    result['soul_md'] = soulMd;

    // 2b. fill missing critical fields.
    final missing = CharacterGenPrompts.criticalFields
        .where((f) => _isEmptyField(result[f]))
        .toList();
    final soulStillTruncated = soulMdTruncated(soulMd); // may still be, after the loop cap
    if (missing.isEmpty && !soulStillTruncated) return result;

    token.throwIfCancelled();
    progress(CharacterGenProgress(
      CharacterGenStep.completing,
      detail: missing.isEmpty ? 'finishing personality' : 'filling ${missing.length} field(s)',
    ));

    final fieldNames = <String>[
      if (soulStillTruncated) 'soul_md_completion',
      ...missing,
    ];
    if (fieldNames.isEmpty) return result;

    final excerpt = soulMd.length > 500 ? soulMd.substring(soulMd.length - 500) : soulMd;
    final completionPrompt = CharacterGenPrompts.buildCompletion(
      name: _str(result['name']),
      locationName: inputs.locationName,
      periodDisplay: inputs.era.periodDisplay,
      vibe: inputs.vibe,
      soulExcerpt: excerpt.isEmpty ? '(empty)' : excerpt,
      soulNeedsCompletion: soulStillTruncated,
      fieldNames: fieldNames,
      nsfw: inputs.nsfw,
    );

    Map<String, dynamic>? completion;
    try {
      final rawC = await _callLlm(completionPrompt, temperature: 0.85);
      token.throwIfCancelled();
      completion = _parseLooseJsonObject(rawC);
    } catch (e) {
      if (kDebugMode) debugPrint('CharacterGenService: completion pass failed: $e');
    }
    if (completion == null) return result;

    if (completion['soul_md_completion'] is String) {
      result['soul_md'] = _joinContinuation(soulMd, (completion['soul_md_completion'] as String).trim());
    }
    for (final f in CharacterGenPrompts.criticalFields) {
      if (_isEmptyField(result[f]) && completion.containsKey(f) && !_isEmptyField(completion[f])) {
        result[f] = completion[f];
      }
    }
    // Also pick up theme / meet_cute / aliases if they were missing.
    for (final f in const ['theme', 'meet_cute', 'aliases', 'gender', 'name']) {
      if (_isEmptyField(result[f]) && completion.containsKey(f) && !_isEmptyField(completion[f])) {
        result[f] = completion[f];
      }
    }
    return result;
  }

  // -- LLM call wrapper ---------------------------------------------------

  Future<String> _callLlm(String prompt, {double temperature = 0.9}) async {
    return _service.generate(TextGenRequest(
      input: prompt,
      model: model,
      params: TextGenParams.glmDefault().copyWith(
        temperature: temperature,
        maxLength: maxTokens,
      ),
    ));
  }

  // -- JSON parsing / repair (ported from bri.'s _repair_truncated_json /
  //    _repair_completion_json / strip-fences logic) ----------------------

  /// Parses the main-generation response into a character map. Strips
  /// fences/think blocks, narrows to the first `{`..last `}`, `jsonDecode`s,
  /// and falls back to a backwards-trim-and-close repair on truncation.
  /// Requires `name` + `soul_md` to accept a repaired result. Returns null if
  /// nothing usable was found.
  static Map<String, dynamic>? _parseCharacterJson(String raw) {
    var text = _stripFencesAndThink(raw).trim();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) text = text.substring(start, end + 1);
    try {
      final decoded = jsonDecode(text);
      // Only accept a clean parse if it actually looks like a character
      // (a `name` at minimum) — otherwise fall through to the repair path,
      // which is stricter and may recover more.
      if (decoded is Map && !_isEmptyField(decoded['name'])) {
        return decoded.cast<String, dynamic>();
      }
    } catch (_) {}
    // Truncation repair: from the first `{`, walk backwards trimming and try
    // appending closing brackets/quotes until it parses with name + soul_md.
    final fromBrace = text.startsWith('{') ? text : (start >= 0 ? raw.substring(raw.indexOf('{')) : text);
    final repaired = _repairTruncatedJson(fromBrace, requireKeys: const ['name', 'soul_md']);
    return repaired;
  }

  /// Parses a completion-pass response into any non-empty object. Lighter than
  /// [_parseCharacterJson] — accepts any dict.
  static Map<String, dynamic>? _parseLooseJsonObject(String raw) {
    var text = _stripFencesAndThink(raw).trim();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) text = text.substring(start, end + 1);
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    final fromBrace = start >= 0 ? raw.substring(raw.indexOf('{')) : text;
    return _repairTruncatedJson(fromBrace, requireKeys: const []);
  }

  /// Ported from bri.'s `_repair_truncated_json` / `_repair_completion_json`:
  /// progressively strips characters off the end, then tries closing the JSON
  /// with a small set of bracket/quote suffixes, accepting the first parse that
  /// is a dict containing all of [requireKeys].
  static Map<String, dynamic>? _repairTruncatedJson(String text, {required List<String> requireKeys}) {
    if (text.isEmpty) return null;
    const suffixes = <String>['"}', '"}}}', '"}}', '"}]}', '"]}}', '"}]}}', '}}', '}', ']}'];
    final maxTrim = text.length < 4000 ? text.length : 4000;
    for (var trim = 0; trim < maxTrim; trim++) {
      final candidate = text.substring(0, text.length - trim);
      for (final suffix in suffixes) {
        try {
          final result = jsonDecode(candidate + suffix);
          if (result is Map && requireKeys.every((k) => result.containsKey(k) && !_isEmptyField(result[k]))) {
            return result.cast<String, dynamic>();
          }
        } catch (_) {}
      }
    }
    return null;
  }

  // -- small helpers ------------------------------------------------------

  /// True if `soul_md` looks cut off mid-sentence (last non-whitespace char is
  /// not sentence-final). Ported from bri.'s `_soul_md_truncated`. Empty ⇒ true.
  static bool soulMdTruncated(String text) {
    final t = text.trimRight();
    if (t.isEmpty) return true;
    const enders = {'.', '!', '?', '"', '\'', ')', '”', '’', '…'};
    return !enders.contains(t[t.length - 1]);
  }

  static bool _isEmptyField(dynamic v) {
    if (v == null) return true;
    if (v is String) return v.trim().isEmpty;
    if (v is Iterable) return v.isEmpty;
    if (v is Map) return v.isEmpty;
    return false;
  }

  static String _stripFencesAndThink(String raw) {
    var text = raw;
    // Drop a leading <think>…</think> block if present.
    final split = splitThinkBlock(text);
    text = split.answer;
    text = text.trim();
    // Drop ```json … ``` fences.
    text = text.replaceFirst(RegExp(r'^```(?:json)?\s*\n?', caseSensitive: false), '');
    text = text.replaceFirst(RegExp(r'\n?```\s*$'), '');
    return text.trim();
  }

  /// Joins a continuation chunk onto a partial document, inserting a space if
  /// the join would otherwise glue two words together.
  static String _joinContinuation(String base, String chunk) {
    if (base.isEmpty) return chunk;
    if (chunk.isEmpty) return base;
    final lastChar = base[base.length - 1];
    final firstChar = chunk[0];
    final needSpace = !RegExp(r'\s').hasMatch(lastChar) && !RegExp(r'\s').hasMatch(firstChar);
    return needSpace ? '$base $chunk' : '$base$chunk';
  }

  /// Stash the non-persisted personality extras (aliases, reaction patterns,
  /// preview scene, meet-cute) in the character's `notes` so they aren't lost.
  static String _buildNotes(Map<String, dynamic> result) {
    final buf = StringBuffer();
    final aliases = _str(result['aliases']).trim();
    if (aliases.isNotEmpty) buf.writeln('Aliases: $aliases\n');
    final meet = _str(result['meet_cute']).trim();
    if (meet.isNotEmpty) buf.writeln('Meet: $meet\n');
    final preview = _str(result['preview_scene']).trim();
    if (preview.isNotEmpty) buf.writeln('Preview scene: $preview\n');
    final rp = result['reaction_patterns'];
    if (rp is Map && rp.isNotEmpty) {
      buf.writeln('Reaction patterns:');
      for (final k in const ['nervous', 'angry', 'attracted', 'sad', 'scared', 'embarrassed', 'happy']) {
        final v = _str(rp[k]).trim();
        if (v.isNotEmpty) buf.writeln('  • $k: $v');
      }
    }
    return buf.toString().trimRight();
  }

  static String _str(dynamic v) {
    if (v is String) return v;
    if (v == null) return '';
    return v.toString();
  }

  static String? _hexOrNull(dynamic v) {
    if (v is! String) return null;
    var h = v.trim();
    if (h.isEmpty) return null;
    if (!h.startsWith('#')) h = '#$h';
    // Accept #rgb / #rrggbb / #aarrggbb.
    if (!RegExp(r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(h)) return null;
    return h.toUpperCase();
  }

  static String _normaliseGender(String fromModel, String fromForm) {
    final m = fromModel.trim().toLowerCase();
    if (m == 'female' || m == 'male' || m == 'nonbinary') return m;
    final f = fromForm.trim().toLowerCase();
    if (f == 'female' || f == 'male' || f == 'nonbinary') return f;
    return '';
  }

  static String _currentSeason() {
    // Northern-hemisphere meteorological seasons; good enough as a hint.
    final m = DateTime.now().month;
    if (m == 12 || m <= 2) return 'winter';
    if (m <= 5) return 'spring';
    if (m <= 8) return 'summer';
    return 'fall';
  }

  static String _genId() {
    final ms = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return ms.length >= 12 ? ms.substring(ms.length - 12) : ms.padLeft(12, '0');
  }

  // -- test hooks ---------------------------------------------------------

  @visibleForTesting
  static Map<String, dynamic>? parseCharacterJsonForTesting(String raw) => _parseCharacterJson(raw);

  @visibleForTesting
  static Map<String, dynamic>? parseLooseJsonForTesting(String raw) => _parseLooseJsonObject(raw);

  @visibleForTesting
  static String joinContinuationForTesting(String base, String chunk) => _joinContinuation(base, chunk);
}
