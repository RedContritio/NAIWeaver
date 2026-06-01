import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

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

  /// Optional artist/style tag, applied directly to the generated character's
  /// image prompt (becomes [SavedCharacter.artistTag]). "" => none.
  final String artist;
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
    this.artist = '',
    this.wardrobeCount = 5,
  });
}

/// Coarse pipeline steps, surfaced to the progress UI.
enum CharacterGenStep { preparing, generating, wardrobe, saving, done }

extension CharacterGenStepX on CharacterGenStep {
  String get label {
    switch (this) {
      case CharacterGenStep.preparing:
        return 'Preparing…';
      case CharacterGenStep.generating:
        return 'Creating character…';
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

/// Orchestrates building a [SavedCharacter] from a [CharacterGenForm] using the
/// lean v2 prompt (appearance tags only — no personality, no soul_md).
///
/// Pipeline:
///   1. lean generation: single LLM call → JSON {name, gender, tags{base, face,
///      hair, body, nsfw_*}}. `<<END>>` stop string keeps GLM from looping.
///   2. starter wardrobe: [WardrobeGeneratorService].
///   3. assemble + return (caller saves).
class CharacterGenService {
  final TextGenService _service;
  final String model;
  final int maxTokens;

  /// Floor on the character-generation call. The lean prompt's JSON runs
  /// ~400-600 tokens; we ask for at least this much regardless of the user's
  /// default `maxLength` (which is typically 150 for image-gen contexts).
  static const int _leanGenMaxTokensFloor = 1500;

  /// Loaded once on first use; the asset bundle is read-only.
  static String? _leanTemplateCache;

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

    final template = await _loadLeanTemplate();
    check();

    final vibeHint = form.vibe.isCustom
        ? form.customVibe
        : (form.vibe.hasAddictionSubject && form.addictionSubject.isNotEmpty
            ? '${form.vibe.name} (${form.addictionSubject})'
            : form.vibe.name);

    // -- Step 1: lean character generation --------------------------------
    progress(const CharacterGenProgress(CharacterGenStep.generating));
    final prompt = substituteLeanCharacterPrompt(
      template: template,
      gender: form.gender,
      era: form.era,
      locationName: form.location,
      vibeHint: vibeHint,
      nsfw: form.nsfw,
    );
    final raw = await _callLlm(prompt, temperature: 0.95);
    check();
    final parsed = _parseCharacterJson(raw);
    if (parsed == null) {
      throw TextGenException(
        'The model didn\'t return usable character JSON. Try again, or pick a higher-tier '
        'account / larger output length.',
      );
    }

    final name = _str(parsed['name']).trim().isEmpty ? 'Unnamed' : _str(parsed['name']).trim();
    final genderOut = _normaliseGender(_str(parsed['gender']), form.gender);

    final tags = (parsed['tags'] is Map)
        ? (parsed['tags'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};

    // -- Step 2: starter wardrobe -----------------------------------------
    final bodyTagParts = <String>[
      _str(tags['base']).trim(),
      _str(tags['face']).trim(),
      _str(tags['hair']).trim(),
      _str(tags['body']).trim(),
    ].where((s) => s.isNotEmpty).toList();
    final bodyTags = bodyTagParts.join(', ');

    final closet = <ClosetOutfit>[];

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
          gender: genderOut,
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
        // A wardrobe failure isn't fatal — the character is still useful
        // with an empty closet.
        if (kDebugMode) debugPrint('CharacterGenService: wardrobe step failed: $e');
      }
    }

    // -- Step 3: assemble --------------------------------------------------
    progress(const CharacterGenProgress(CharacterGenStep.saving));
    check();

    final primaryOutfitId = closet.isEmpty ? null : closet.first.id;

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
      artistTag: form.artist.trim(),
      primaryOutfitId: primaryOutfitId,
    );

    progress(const CharacterGenProgress(CharacterGenStep.done));
    return GeneratedCharacter(character, closet);
  }

  // -- LLM call wrapper ---------------------------------------------------

  Future<String> _callLlm(String prompt, {double temperature = 0.9}) async {
    final budget = maxTokens < _leanGenMaxTokensFloor ? _leanGenMaxTokensFloor : maxTokens;
    return _service.generate(TextGenRequest(
      input: prompt,
      model: model,
      stopStrings: const ['<<END>>'],
      params: TextGenParams.glmDefault().copyWith(
        temperature: temperature,
        maxLength: budget,
      ),
    ));
  }

  // -- prompt template loading -------------------------------------------

  Future<String> _loadLeanTemplate() async {
    if (_leanTemplateCache != null) return _leanTemplateCache!;
    final raw = await rootBundle.loadString('assets/prompts/character.lean.v2.txt');
    _leanTemplateCache = raw;
    return raw;
  }

  /// Test hook — inject a template directly without going through rootBundle.
  @visibleForTesting
  static void setLeanTemplateForTesting(String? template) {
    _leanTemplateCache = template;
  }

  // -- JSON parsing / repair ---------------------------------------------

  /// Parses the lean-generation response into a character map. Strips
  /// fences/think blocks, narrows to the first `{`..last `}`, decodes, and
  /// falls back to a backwards-trim-and-close repair on truncation. Requires
  /// `name` to accept a repaired result.
  static Map<String, dynamic>? _parseCharacterJson(String raw) {
    var text = _stripFencesAndThink(raw).trim();
    // Drop a trailing <<END>> sentinel if the stop didn't already strip it.
    text = text.replaceAll('<<END>>', '').trim();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) text = text.substring(start, end + 1);
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map && !_isEmptyField(decoded['name'])) {
        return decoded.cast<String, dynamic>();
      }
    } catch (_) {}
    final fromBrace = text.startsWith('{')
        ? text
        : (start >= 0 ? raw.substring(raw.indexOf('{')) : text);
    final repaired = _repairTruncatedJson(fromBrace, requireKeys: const ['name']);
    return repaired;
  }

  /// Progressively strips characters off the end, then tries closing the JSON
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

  static bool _isEmptyField(dynamic v) {
    if (v == null) return true;
    if (v is String) return v.trim().isEmpty;
    if (v is Iterable) return v.isEmpty;
    if (v is Map) return v.isEmpty;
    return false;
  }

  static String _stripFencesAndThink(String raw) {
    var text = raw;
    final split = splitThinkBlock(text);
    text = split.answer.trim();
    text = text.replaceFirst(RegExp(r'^```(?:json)?\s*\n?', caseSensitive: false), '');
    text = text.replaceFirst(RegExp(r'\n?```\s*$'), '');
    return text.trim();
  }

  static String _str(dynamic v) {
    if (v is String) return v;
    if (v == null) return '';
    return v.toString();
  }

  static String _normaliseGender(String fromModel, String fromForm) {
    final m = fromModel.trim().toLowerCase();
    if (m == 'female' || m == 'male' || m == 'nonbinary') return m;
    final f = fromForm.trim().toLowerCase();
    if (f == 'female' || f == 'male' || f == 'nonbinary') return f;
    return '';
  }

  static String _genId() {
    final ms = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return ms.length >= 12 ? ms.substring(ms.length - 12) : ms.padLeft(12, '0');
  }

  // -- test hooks ---------------------------------------------------------

  @visibleForTesting
  static Map<String, dynamic>? parseCharacterJsonForTesting(String raw) => _parseCharacterJson(raw);
}
