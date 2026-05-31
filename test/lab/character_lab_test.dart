// ignore_for_file: avoid_print
// Backend prompt-lab harness for character + wardrobe generation.
//
// This is NOT a unit test — it's a hand-runnable iteration loop that:
//   1. reads a real NovelAI token from the env var NAI_TOKEN
//   2. for each scenario in lab/scenarios.dart, runs either main-gen or
//      wardrobe-gen against the live API
//   3. writes the form, prompt, raw response, and parsed JSON to
//      lab/runs/<scenario>_<mode>_<promptVersion>_<timestamp>.json
//   4. runs the audit (lab/audit.dart) on every result and prints findings
//
// Skipped automatically when NAI_TOKEN is not set, so this file is safe to
// leave in the suite — CI runs will skip it, dev runs opt in.
//
// Usage (PowerShell):
//   $env:NAI_TOKEN="pst-..."
//   $env:LAB_SCENARIOS="modern_tokyo_mysterious_f,modern_nyc_chaotic_m"  # optional
//   $env:LAB_MODE="wardrobe"   # "wardrobe" | "main" | "both" (default both)
//   $env:LAB_PROMPT="lab/prompts/wardrobe.v2.txt"  # optional wardrobe override
//   $env:LAB_MODEL="glm-4-6"   # optional model override
//   $env:LAB_MAX_TOKENS="2000" # optional max_length override (default 2000)
//   flutter test test/lab/character_lab_test.dart --reporter=expanded
//
// Tip: `LAB_MAX_TOKENS=200` to simulate the free/Tablet-tier cap.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/nai_text_service.dart';
import 'package:naiweaver/core/services/text_gen_service.dart';
import 'package:naiweaver/features/characters/gen/character_gen_data.dart';
import 'package:naiweaver/features/characters/gen/character_gen_prompts.dart';
import 'package:naiweaver/features/characters/gen/character_gen_service.dart';
import 'package:naiweaver/features/characters/services/wardrobe_generator_service.dart';

import '../../lab/audit.dart';
import '../../lab/scenarios.dart';

void main() {
  final token = Platform.environment['NAI_TOKEN'] ?? '';
  if (token.trim().isEmpty) {
    test('lab harness — skipped (NAI_TOKEN not set)', () {
      // Intentionally no-op. Set NAI_TOKEN env var to run the harness.
    });
    return;
  }

  final mode = (Platform.environment['LAB_MODE'] ?? 'both').toLowerCase();
  final model = Platform.environment['LAB_MODEL'] ?? 'glm-4-6';
  final maxTokens = int.tryParse(Platform.environment['LAB_MAX_TOKENS'] ?? '') ?? 2000;
  final wardrobePromptPath = Platform.environment['LAB_PROMPT'] ?? '';
  final mainPromptPath = Platform.environment['LAB_MAIN_PROMPT'] ?? '';
  final userDescription = Platform.environment['LAB_USER_DESCRIPTION'] ?? '';
  final shape =
      (Platform.environment['LAB_SHAPE'] ?? '').toLowerCase() == 'lean'
          ? CharacterShape.lean
          : CharacterShape.full;
  final selectedIds = (Platform.environment['LAB_SCENARIOS'] ?? '')
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet();
  final scenarios = selectedIds.isEmpty
      ? kLabScenarios
      : kLabScenarios.where((s) => selectedIds.contains(s.id)).toList();

  if (scenarios.isEmpty) {
    test('lab harness — no scenarios matched LAB_SCENARIOS', () {
      fail('LAB_SCENARIOS=${Platform.environment['LAB_SCENARIOS']} matched no scenarios in '
          'lab/scenarios.dart. Known ids: ${kLabScenarios.map((s) => s.id).join(", ")}');
    });
    return;
  }

  final wardrobePromptOverride = wardrobePromptPath.isEmpty
      ? null
      : File(wardrobePromptPath).readAsStringSync();
  final wardrobePromptVersion =
      wardrobePromptPath.isEmpty ? 'in-code' : _versionFromPath(wardrobePromptPath);
  final mainPromptOverride =
      mainPromptPath.isEmpty ? null : File(mainPromptPath).readAsStringSync();
  final mainPromptVersion =
      mainPromptPath.isEmpty ? 'in-code' : _versionFromPath(mainPromptPath);

  final service = NaiTextService(token);
  final runsDir = Directory('lab/runs');
  if (!runsDir.existsSync()) runsDir.createSync(recursive: true);

  // Print the run config once.
  print('-- lab config --------------------------------------------------------');
  print('  mode: $mode');
  print('  model: $model');
  print('  max_tokens: $maxTokens');
  print('  main prompt: ${mainPromptPath.isEmpty ? "(in-code soul-md)" : mainPromptPath}');
  print('  wardrobe prompt: ${wardrobePromptPath.isEmpty ? "(in-code)" : wardrobePromptPath}');
  print('  shape: ${shape.name}');
  print('  user_description: ${userDescription.isEmpty ? "(none)" : userDescription}');
  print('  scenarios: ${scenarios.map((s) => s.id).join(", ")}');
  print('----------------------------------------------------------------------');

  for (final scenario in scenarios) {
    if (mode == 'main' || mode == 'both') {
      test('main-gen — ${scenario.id} ($mainPromptVersion, shape=${shape.name})', () async {
        await _runMainGen(
          scenario: scenario,
          service: service,
          model: model,
          maxTokens: maxTokens,
          promptOverride: mainPromptOverride,
          promptVersion: mainPromptVersion,
          shape: shape,
          userDescription: userDescription,
          runsDir: runsDir,
        );
      }, timeout: const Timeout(Duration(minutes: 8)));
    }

    if (mode == 'wardrobe' || mode == 'both') {
      test('wardrobe — ${scenario.id} ($wardrobePromptVersion)', () async {
        await _runWardrobe(
          scenario: scenario,
          service: service,
          model: model,
          maxTokens: maxTokens,
          promptOverride: wardrobePromptOverride,
          promptVersion: wardrobePromptVersion,
          runsDir: runsDir,
        );
      }, timeout: const Timeout(Duration(minutes: 8)));
    }
  }
}

String _versionFromPath(String p) {
  final base = p.split(RegExp(r'[\\/]')).last;
  return base.replaceAll(RegExp(r'\.txt$'), '');
}

String _stamp() => DateTime.now()
    .toIso8601String()
    .replaceAll(':', '-')
    .replaceAll('.', '-');

Future<void> _runMainGen({
  required LabScenario scenario,
  required TextGenService service,
  required String model,
  required int maxTokens,
  String? promptOverride,
  required String promptVersion,
  required CharacterShape shape,
  required String userDescription,
  required Directory runsDir,
}) async {
  final form = scenario.form;
  final String prompt;
  if (promptOverride != null) {
    // Lean prompt path — substitute placeholders.
    prompt = substituteLeanCharacterPrompt(
      template: promptOverride,
      userDescription: userDescription,
      gender: form.gender,
      ageRange: '20s',
      era: form.era,
      locationName: form.location,
      vibeHint: form.vibe.isCustom ? form.customVibe : form.vibe.name,
      nsfw: form.nsfw,
    );
  } else {
    final inputs = CharacterGenPromptInputs(
      gender: form.gender,
      vibe: form.vibe.name,
      vibeGuidance: form.vibe.resolvedGuidance(
        customVibe: form.customVibe,
        addictionSubject: form.addictionSubject,
      ),
      era: form.era,
      locationName: form.location,
      season: 'spring',
      weather: 'pleasant',
      nsfw: form.nsfw,
      imageStyle: form.imageStyle,
    );
    prompt = CharacterGenPrompts.buildGeneration(inputs);
  }

  print('\n[main-gen ${scenario.id} v=$promptVersion shape=${shape.name}] prompt: ${prompt.length} chars');
  final t0 = DateTime.now();
  String raw;
  try {
    raw = await service.generate(TextGenRequest(
      input: prompt,
      model: model,
      stopStrings: promptOverride != null ? const ['<<END>>'] : null,
      params: TextGenParams.glmDefault().copyWith(
        temperature: 0.95,
        maxLength: maxTokens,
      ),
    ));
  } on TextGenException catch (e) {
    print('  ERROR: $e');
    rethrow;
  }
  final dt = DateTime.now().difference(t0);
  print('  got ${raw.length} chars in ${dt.inMilliseconds}ms');

  // Parse — same logic the prod service uses.
  final parsed = CharacterGenService.parseCharacterJsonForTesting(raw);

  final report = parsed == null ? null : auditCharacter(parsed, shape: shape);
  if (report != null) print(report.formatted());

  // Auto-correction pass (lean only): if any tags were flagged as unknown,
  // ask GLM to map them to the closest canonical Danbooru tag, splice the
  // mapping back into the parsed object, and re-audit.
  Map<String, String>? correctionMap;
  Map<String, dynamic>? corrected;
  CharacterReport? correctedReport;
  String? correctionRaw;
  if (shape == CharacterShape.lean &&
      parsed != null &&
      report != null &&
      report.findings.any((f) => f.field == 'unknownTag')) {
    final unknownTags = <String>{};
    for (final f in report.findings) {
      if (f.field != 'unknownTag') continue;
      final m = RegExp(r'"([^"]+)"').firstMatch(f.detail);
      if (m != null) unknownTags.add(m.group(1)!);
    }
    if (unknownTags.isNotEmpty) {
      print('  Auto-correction: ${unknownTags.length} unknown tag(s) → asking GLM to map');
      final correctionPrompt =
          'You are validating a list of anime image tags. The following tags were emitted by a model but are NOT canonical Danbooru tags:\n\n'
          '${unknownTags.map((t) => '- "$t"').join('\n')}\n\n'
          'For EACH tag above, output the SINGLE closest canonical Danbooru tag that means the same thing (or an empty string "" if the concept does not map cleanly to a real Danbooru tag — better to drop it than invent).\n\n'
          'Use ONLY real Danbooru tags. Examples of valid replacements:\n'
          '  "japanese" → "" (Danbooru tags via skin tone, not nationality)\n'
          '  "hooded eyes" → "tareme"\n'
          '  "high cheekbones" → "" (not a Danbooru tag)\n'
          '  "center part" → "parted bangs"\n'
          '  "slim" → "petite"\n'
          '  "olive skin" → "tan"\n'
          '  "thin eyebrows" → "" (not canonical — only "thick eyebrows" exists)\n'
          '  "20yo" → "" (not a Danbooru tag)\n'
          '  "dark brown hair" → "brown hair"\n\n'
          'Respond with ONLY a JSON object mapping each input tag to its replacement (use empty string to drop):\n'
          '{"input_tag": "canonical_tag_or_empty", ...}\n\n'
          'No markdown fences. No commentary. After the closing `}` write `<<END>>` on its own line and STOP.';
      try {
        correctionRaw = await service.generate(TextGenRequest(
          input: correctionPrompt,
          model: model,
          stopStrings: const ['<<END>>'],
          params: TextGenParams.glmDefault().copyWith(
            temperature: 0.3,
            maxLength: 800,
          ),
        ));
        // Extract the JSON object.
        final cleaned = correctionRaw
            .replaceAll(RegExp(r'^```(?:json)?\s*\n?'), '')
            .replaceAll(RegExp(r'\n?```\s*$'), '')
            .trim();
        final start = cleaned.indexOf('{');
        final end = cleaned.lastIndexOf('}');
        if (start >= 0 && end > start) {
          final fragment = cleaned.substring(start, end + 1);
          final decoded = jsonDecode(fragment);
          if (decoded is Map) {
            correctionMap = decoded.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
          }
        }
      } catch (e) {
        print('  Auto-correction failed: $e');
      }

      if (correctionMap != null) {
        // Apply: walk each bucket, replace each tag, drop empties, dedupe.
        corrected = jsonDecode(jsonEncode(parsed)) as Map<String, dynamic>;
        final tagsMap = corrected['tags'];
        if (tagsMap is Map) {
          for (final bucket in ['base', 'face', 'hair', 'body', 'nsfw_top', 'nsfw_bottom', 'nsfw_always']) {
            final v = tagsMap[bucket];
            if (v is! String) continue;
            final parts = v.toLowerCase().split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
            final out = <String>[];
            final seen = <String>{};
            for (final p in parts) {
              final replacement = correctionMap.containsKey(p) ? correctionMap[p]!.trim() : p;
              if (replacement.isEmpty) continue;
              if (seen.add(replacement)) out.add(replacement);
            }
            tagsMap[bucket] = out.join(', ');
          }
        }
        correctedReport = auditCharacter(corrected, shape: shape);
        print('  After correction: ${correctedReport.findings.length} finding(s) '
            '(was ${report.findings.length})');
      }
    }
  }

  final file = File('${runsDir.path}/${scenario.id}_main_${promptVersion}_${_stamp()}.json');
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
    'scenario': scenario.id,
    'description': scenario.description,
    'mode': 'main-gen',
    'prompt_version': promptVersion,
    'shape': shape.name,
    'user_description': userDescription,
    'model': model,
    'max_tokens': maxTokens,
    'temperature': 0.95,
    'form': _formToJson(form),
    'prompt': prompt,
    'raw': raw,
    'correction_raw': correctionRaw,
    'correction_map': correctionMap,
    'corrected': corrected,
    'corrected_audit': correctedReport == null
        ? null
        : {
            'finding_count': correctedReport.findings.length,
            'tally': correctedReport.findings.fold<Map<String, int>>({}, (m, f) {
              m[f.field] = (m[f.field] ?? 0) + 1;
              return m;
            }),
            'findings': [for (final f in correctedReport.findings) f.toString()],
          },
    'parsed': parsed,
    'audit': report == null
        ? {'parse_failed': true}
        : {
            'finding_count': report.findings.length,
            'tally': report.findings.fold<Map<String, int>>({}, (m, f) {
              m[f.field] = (m[f.field] ?? 0) + 1;
              return m;
            }),
            'findings': [for (final f in report.findings) f.toString()],
            'present_fields': report.presentFields,
          },
    'duration_ms': dt.inMilliseconds,
    'timestamp': DateTime.now().toIso8601String(),
  }));
  print('  -> ${file.path}');
}

Future<void> _runWardrobe({
  required LabScenario scenario,
  required TextGenService service,
  required String model,
  required int maxTokens,
  String? promptOverride,
  required String promptVersion,
  required Directory runsDir,
}) async {
  final form = scenario.form;
  // For a wardrobe-only run we need body tags. If the scenario doesn't provide
  // them (most don't — they come from main-gen), use a generic stand-in. The
  // lab user can edit this scenario to inject specific tags.
  final bodyTags = '1girl, ${form.gender == "male" ? "1boy, " : ""}20yo';
  final eraHint = form.era.isModern ? '' : form.era.periodDisplay;
  final vibeHint = form.vibe.isCustom ? form.customVibe : form.vibe.name;

  final body = bodyTags.trim().isEmpty ? 'anime girl' : bodyTags.trim();
  final prompt = promptOverride != null
      ? substituteWardrobePrompt(
          template: promptOverride,
          count: form.wardrobeCount,
          characterTags: body,
          eraHint: eraHint,
          vibeHint: vibeHint,
        )
      : buildWardrobePrompt(
          count: form.wardrobeCount,
          characterTags: body,
          eraHint: eraHint,
          vibeHint: vibeHint,
        );

  print('\n[wardrobe ${scenario.id} v=$promptVersion] prompt: ${prompt.length} chars');

  // Stop string is only honored when an override prompt is in play (the v1
  // in-code prompt doesn't emit <<END>>). Same convention as main-gen.
  final stopStrings = promptOverride != null ? const ['<<END>>'] : null;

  // Diagnostic pass: fire ONE direct call against the same prompt so we
  // capture the raw GLM response. This is independent of the prod path below
  // and is for "what did the model actually emit" forensics. Use the same
  // params (temperature 0.8) the prod service uses.
  String? diagnosticRaw;
  try {
    diagnosticRaw = await service.generate(TextGenRequest(
      input: prompt,
      model: model,
      stopStrings: stopStrings,
      params: TextGenParams.glmDefault().copyWith(
        temperature: 0.8,
        maxLength: maxTokens,
      ),
    ));
    print('  diagnostic raw: ${diagnosticRaw.length} chars');
  } catch (e) {
    print('  diagnostic call failed: $e');
  }

  // Use the real service for the batch path, with the override threaded in so
  // we exercise the same batching behaviour the prod app uses.
  final svc = WardrobeGeneratorService(service);
  final t0 = DateTime.now();
  final outfits = await svc.generate(
    characterTags: body,
    count: form.wardrobeCount,
    eraHint: eraHint,
    vibeHint: vibeHint,
    model: model,
    maxTokens: maxTokens,
    promptOverride: promptOverride,
    stopStrings: stopStrings,
  );
  final dt = DateTime.now().difference(t0);
  print('  got ${outfits.length} outfit(s) in ${dt.inMilliseconds}ms');

  final outfitsJson = [
    for (final g in outfits)
      {
        'name': g.outfit.name,
        'tags': g.outfit.tags,
        'seasons': g.outfit.seasons,
        'weather': g.outfit.weather,
        'activities': g.outfit.activities,
        'temperature_range': g.outfit.temperatureRange,
        'slots': g.outfit.slots,
        'primary': g.isPrimary,
      }
  ];

  final report = auditOutfits(outfitsJson.cast<Map<String, dynamic>>());
  print(report.formatted());

  final file = File('${runsDir.path}/${scenario.id}_wardrobe_${promptVersion}_${_stamp()}.json');
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
    'scenario': scenario.id,
    'description': scenario.description,
    'mode': 'wardrobe',
    'prompt_version': promptVersion,
    'model': model,
    'max_tokens': maxTokens,
    'temperature': 0.8,
    'form': _formToJson(form),
    'body_tags': body,
    'era_hint': eraHint,
    'vibe_hint': vibeHint,
    'prompt': prompt,
    'diagnostic_raw': diagnosticRaw,
    'outfits': outfitsJson,
    'audit': {
      'finding_count': report.findings.length,
      'tally': report.tally,
      'findings': [for (final f in report.findings) f.toString()],
    },
    'duration_ms': dt.inMilliseconds,
    'timestamp': DateTime.now().toIso8601String(),
  }));
  print('  -> ${file.path}');
}

Map<String, dynamic> _formToJson(CharacterGenForm f) => {
      'gender': f.gender,
      'vibe': f.vibe.id,
      'customVibe': f.customVibe,
      'addictionSubject': f.addictionSubject,
      'era': {
        'id': f.era.id,
        'year': f.era.year,
        'label': f.era.label,
      },
      'location': f.location,
      'nsfw': f.nsfw,
      'imageStyle': f.imageStyle.id,
      'wardrobeCount': f.wardrobeCount,
    };
