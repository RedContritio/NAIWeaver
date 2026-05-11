import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/text_gen_service.dart';

void main() {
  group('TextGenParams', () {
    test('glmDefault() serializes to the exact NovelAI parameters shape', () {
      final json = TextGenParams.glmDefault().toJson();

      // Field names must match the API spec exactly.
      expect(json.keys, containsAll(<String>[
        'use_string',
        'temperature',
        'max_length',
        'min_length',
        'top_k',
        'top_p',
        'top_a',
        'typical_p',
        'tail_free_sampling',
        'repetition_penalty',
        'repetition_penalty_range',
        'repetition_penalty_slope',
        'repetition_penalty_frequency',
        'repetition_penalty_presence',
        'phrase_rep_pen',
        'bad_words_ids',
        'stop_sequences',
        'bracket_ban',
        'generate_until_sentence',
        'order',
      ]));

      expect(json['use_string'], isTrue);
      expect(json['temperature'], 1.0);
      expect(json['max_length'], 150);
      expect(json['min_length'], 1);
      expect(json['top_k'], 0);
      expect(json['top_p'], 1.0);
      expect(json['top_a'], 1.0);
      expect(json['typical_p'], 1.0);
      expect(json['tail_free_sampling'], 1.0);
      expect(json['repetition_penalty'], 1.0);
      expect(json['repetition_penalty_range'], 2048);
      expect(json['repetition_penalty_slope'], 0.0);
      expect(json['repetition_penalty_frequency'], 0.0);
      expect(json['repetition_penalty_presence'], 0.0);
      expect(json['phrase_rep_pen'], 'aggressive');
      expect(json['bad_words_ids'], isEmpty);
      expect(json['stop_sequences'], isEmpty);
      expect(json['bracket_ban'], isTrue);
      expect(json['generate_until_sentence'], isTrue);
      expect(json['order'], <int>[0, 1, 2, 3]);
    });

    test('round-trips through fromJson', () {
      const original = TextGenParams(
        temperature: 0.85,
        maxLength: 320,
        minLength: 5,
        topK: 40,
        topP: 0.92,
        topA: 0.1,
        typicalP: 0.95,
        tailFreeSampling: 0.97,
        repetitionPenalty: 1.05,
        repetitionPenaltyRange: 1024,
        repetitionPenaltySlope: 0.1,
        repetitionPenaltyFrequency: 0.02,
        repetitionPenaltyPresence: 0.01,
        phraseRepPen: 'medium',
        bracketBan: false,
        generateUntilSentence: false,
        order: [3, 2, 1, 0],
      );

      final restored = TextGenParams.fromJson(original.toJson());

      expect(restored.useString, original.useString);
      expect(restored.temperature, original.temperature);
      expect(restored.maxLength, original.maxLength);
      expect(restored.minLength, original.minLength);
      expect(restored.topK, original.topK);
      expect(restored.topP, original.topP);
      expect(restored.topA, original.topA);
      expect(restored.typicalP, original.typicalP);
      expect(restored.tailFreeSampling, original.tailFreeSampling);
      expect(restored.repetitionPenalty, original.repetitionPenalty);
      expect(restored.repetitionPenaltyRange, original.repetitionPenaltyRange);
      expect(restored.repetitionPenaltySlope, original.repetitionPenaltySlope);
      expect(
          restored.repetitionPenaltyFrequency, original.repetitionPenaltyFrequency);
      expect(
          restored.repetitionPenaltyPresence, original.repetitionPenaltyPresence);
      expect(restored.phraseRepPen, original.phraseRepPen);
      expect(restored.bracketBan, original.bracketBan);
      expect(restored.generateUntilSentence, original.generateUntilSentence);
      expect(restored.order, original.order);
    });

    test('deterministic preset lowers temperature', () {
      expect(TextGenParams.deterministic().temperature, 0.6);
      expect(TextGenParams.byPresetName('Deterministic (low temp)').temperature,
          0.6);
      expect(TextGenParams.byPresetName('GLM Default').temperature, 1.0);
      expect(TextGenParams.byPresetName('unknown').temperature, 1.0);
    });
  });

  group('TextGenRequest', () {
    test('builds the right top-level body shape', () {
      final req = TextGenRequest(
        input: 'The old lighthouse keeper said,',
        model: 'glm-4-6',
        params: TextGenParams.glmDefault(),
      );
      final body = req.toJson();
      expect(body.keys, unorderedEquals(<String>['input', 'model', 'parameters']));
      expect(body['input'], 'The old lighthouse keeper said,');
      expect(body['model'], 'glm-4-6');
      expect((body['parameters'] as Map)['use_string'], isTrue);
    });

    test('default model is glm-4-6', () {
      expect(const TextGenRequest(input: 'x').model, 'glm-4-6');
      expect(kDefaultTextModel, 'glm-4-6');
    });

    test('firstStopIndex finds the earliest stop string', () {
      const req = TextGenRequest(
        input: '',
        stopStrings: ['END', '.'],
      );
      // "." appears at index 5, "END" never -> 5.
      expect(req.firstStopIndex('hello. world END'), 5);
      // No stop strings -> -1.
      expect(const TextGenRequest(input: '').firstStopIndex('anything'), -1);
      // Empty stop strings ignored.
      expect(
          const TextGenRequest(input: '', stopStrings: ['', '']).firstStopIndex('x'),
          -1);
    });
  });
}
