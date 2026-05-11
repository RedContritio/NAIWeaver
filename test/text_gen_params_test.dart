import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/text_gen_service.dart';

void main() {
  group('TextGenParams — legacy parameters body (Kayra/Clio/Erato)', () {
    test('toLegacyParametersJson() has the documented field names + defaults', () {
      final json = TextGenParams.glmDefault().toLegacyParametersJson();

      // Names match the NovelAI Swagger AiGenerateParameters schema / what
      // SillyTavern sends.
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
        'generate_until_sentence',
        'order',
        'force_emotion',
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
      expect(json['phrase_rep_pen'], 'aggressive');
      expect(json['generate_until_sentence'], isTrue);
      expect(json['order'], <int>[0, 1, 2, 3]);
      expect(json['force_emotion'], isFalse);
      // We do NOT send invented fields.
      expect(json.containsKey('bracket_ban'), isFalse);
    });
  });

  group('TextGenParams — chat body (GLM)', () {
    test('toChatJson() uses OpenAI-ish names and omits zero-valued extras', () {
      final json = TextGenParams.glmDefault().toChatJson();
      expect(json.keys, containsAll(<String>['temperature', 'max_tokens', 'top_p']));
      expect(json['temperature'], 1.0);
      expect(json['max_tokens'], 150);
      expect(json['top_p'], 1.0);
      // top_k 0 / penalties 0 / min_p 0 are omitted (server defaults).
      expect(json.containsKey('top_k'), isFalse);
      expect(json.containsKey('frequency_penalty'), isFalse);
      expect(json.containsKey('presence_penalty'), isFalse);
      expect(json.containsKey('min_p'), isFalse);
    });

    test('toChatJson() includes the extras once they are non-zero', () {
      const p = TextGenParams(
        topK: 40,
        frequencyPenalty: 0.1,
        presencePenalty: 0.2,
        minP: 0.05,
      );
      final json = p.toChatJson();
      expect(json['top_k'], 40);
      expect(json['frequency_penalty'], 0.1);
      expect(json['presence_penalty'], 0.2);
      expect(json['min_p'], 0.05);
    });
  });

  group('TextGenParams round-trip', () {
    test('toJson()/fromJson() preserves all fields', () {
      const original = TextGenParams(
        temperature: 0.85,
        maxLength: 320,
        minLength: 5,
        topK: 40,
        topP: 0.92,
        frequencyPenalty: 0.03,
        presencePenalty: 0.04,
        minP: 0.02,
        topA: 0.1,
        typicalP: 0.95,
        tailFreeSampling: 0.97,
        repetitionPenalty: 1.05,
        repetitionPenaltyRange: 1024,
        repetitionPenaltySlope: 0.1,
        repetitionPenaltyFrequency: 0.02,
        repetitionPenaltyPresence: 0.01,
        phraseRepPen: 'medium',
        generateUntilSentence: false,
        order: [3, 2, 1, 0],
      );
      final restored = TextGenParams.fromJson(original.toJson());
      expect(restored.temperature, original.temperature);
      expect(restored.maxLength, original.maxLength);
      expect(restored.minLength, original.minLength);
      expect(restored.topK, original.topK);
      expect(restored.topP, original.topP);
      expect(restored.frequencyPenalty, original.frequencyPenalty);
      expect(restored.presencePenalty, original.presencePenalty);
      expect(restored.minP, original.minP);
      expect(restored.topA, original.topA);
      expect(restored.typicalP, original.typicalP);
      expect(restored.tailFreeSampling, original.tailFreeSampling);
      expect(restored.repetitionPenalty, original.repetitionPenalty);
      expect(restored.repetitionPenaltyRange, original.repetitionPenaltyRange);
      expect(restored.repetitionPenaltySlope, original.repetitionPenaltySlope);
      expect(restored.repetitionPenaltyFrequency,
          original.repetitionPenaltyFrequency);
      expect(restored.repetitionPenaltyPresence,
          original.repetitionPenaltyPresence);
      expect(restored.phraseRepPen, original.phraseRepPen);
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
    test('chat-style model => messages body with choices-friendly shape', () {
      final req = TextGenRequest(
        input: 'The old lighthouse keeper said,',
        model: 'glm-4-6',
        params: TextGenParams.glmDefault(),
      );
      expect(req.isChatStyle, isTrue);
      final body = req.toJson();
      expect(body['model'], 'glm-4-6');
      expect(body['messages'], isA<List>());
      final messages = body['messages'] as List;
      expect(messages, hasLength(1)); // single user message, no system by default
      expect((messages.first as Map)['role'], 'user');
      expect((messages.first as Map)['content'], 'The old lighthouse keeper said,');
      expect(body['temperature'], 1.0);
      expect(body['max_tokens'], 150);
      expect(body.containsKey('input'), isFalse);
      expect(body.containsKey('parameters'), isFalse);
    });

    test('system prompt becomes a leading system message', () {
      final req = TextGenRequest(
        input: 'Where am I?',
        model: 'glm-4-6',
        systemPrompt: 'You are a not-very-helpful assistant.',
      );
      final messages = (req.toJson()['messages'] as List).cast<Map>();
      expect(messages, hasLength(2));
      expect(messages[0]['role'], 'system');
      expect(messages[1]['role'], 'user');
    });

    test('legacy model => {input, model, parameters} body', () {
      final req = TextGenRequest(
        input: 'Once upon a time',
        model: 'kayra-v1',
        params: TextGenParams.glmDefault(),
      );
      expect(req.isChatStyle, isFalse);
      final body = req.toJson();
      expect(body.keys, unorderedEquals(<String>['input', 'model', 'parameters']));
      expect(body['input'], 'Once upon a time');
      expect(body['model'], 'kayra-v1');
      expect((body['parameters'] as Map)['use_string'], isTrue);
      expect((body['parameters'] as Map)['max_length'], 150);
    });

    test('chat body forwards stop strings as a "stop" array', () {
      final req = TextGenRequest(
        input: 'x',
        model: 'glm-4-6',
        stopStrings: ['END', '', '.'],
      );
      expect(req.toJson()['stop'], <String>['END', '.']);
    });

    test('default model is glm-4-6 and is chat-style', () {
      expect(const TextGenRequest(input: 'x').model, 'glm-4-6');
      expect(kDefaultTextModel, 'glm-4-6');
      expect(isChatStyleModel('glm-4-6'), isTrue);
      expect(isChatStyleModel('kayra-v1'), isFalse);
      expect(isChatStyleModel('clio-v1'), isFalse);
      expect(isChatStyleModel('llama-3-erato-v1'), isFalse);
    });

    test('firstStopIndex finds the earliest stop string', () {
      const req = TextGenRequest(input: '', stopStrings: ['END', '.']);
      expect(req.firstStopIndex('hello. world END'), 5);
      expect(const TextGenRequest(input: '').firstStopIndex('anything'), -1);
      expect(
          const TextGenRequest(input: '', stopStrings: ['', ''])
              .firstStopIndex('x'),
          -1);
    });
  });

  group('extractGeneratedText', () {
    test('reads the legacy {"output": ...} shape', () {
      expect(extractGeneratedText({'output': ' a continuation'}),
          ' a continuation');
    });

    test('reads chat {"choices":[{"text": ...}]}', () {
      expect(
          extractGeneratedText({
            'choices': [
              {'text': 'hello world'}
            ]
          }),
          'hello world');
    });

    test('reads chat {"choices":[{"message":{"content": ...}}]}', () {
      expect(
          extractGeneratedText({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'hi there'}
              }
            ]
          }),
          'hi there');
    });

    test('reads streamed chat delta {"choices":[{"delta":{"content": ...}}]}', () {
      expect(
          extractGeneratedText({
            'choices': [
              {
                'delta': {'content': 'tok'}
              }
            ]
          }),
          'tok');
    });

    test('returns null when there is nothing usable', () {
      expect(extractGeneratedText({'unrelated': 1}), isNull);
      expect(extractGeneratedText(42), isNull);
    });
  });
}
