import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/text_gen_service.dart';

void main() {
  group('TextGenParams — legacy parameters body (Kayra/Clio/Erato)', () {
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

  });

  group('TextGenRequest', () {
    test('chat-style model => OpenAI completions {prompt, model, ...} body', () {
      final req = TextGenRequest(
        input: 'The old lighthouse keeper said,',
        model: 'glm-4-6',
        params: TextGenParams.glmDefault(),
      );
      expect(req.isChatStyle, isTrue);
      final body = req.toJson();
      expect(body['model'], 'glm-4-6');
      expect(body['prompt'], 'The old lighthouse keeper said,');
      expect(body['max_tokens'], 150);
      expect(body['temperature'], 1.0);
      expect(body['top_p'], 1.0);
      expect(body['stream'], isFalse);
      // No legacy keys, no messages array.
      expect(body.containsKey('input'), isFalse);
      expect(body.containsKey('parameters'), isFalse);
      expect(body.containsKey('messages'), isFalse);
      // Zero-valued extras omitted.
      expect(body.containsKey('top_k'), isFalse);
      expect(body.containsKey('min_p'), isFalse);
      expect(body.containsKey('frequency_penalty'), isFalse);
      expect(body.containsKey('presence_penalty'), isFalse);
    });

    test('toCompletionsJson(stream: true) sets "stream": true', () {
      final body = const TextGenRequest(input: 'x', model: 'glm-4-6')
          .toCompletionsJson(stream: true);
      expect(body['stream'], isTrue);
    });

    test('completions body includes non-zero extras', () {
      final req = TextGenRequest(
        input: 'x',
        model: 'glm-4-6',
        params: const TextGenParams(
          topK: 40,
          minP: 0.05,
          frequencyPenalty: 0.1,
          presencePenalty: 0.2,
        ),
      );
      final body = req.toJson();
      expect(body['top_k'], 40);
      expect(body['min_p'], 0.05);
      expect(body['frequency_penalty'], 0.1);
      expect(body['presence_penalty'], 0.2);
    });

    test('system prompt is prepended to the prompt', () {
      final req = TextGenRequest(
        input: 'Where am I?',
        model: 'glm-4-6',
        systemPrompt: 'You are a not-very-helpful assistant.',
      );
      expect(req.toJson()['prompt'],
          'You are a not-very-helpful assistant.\nWhere am I?');
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

    test('enable_thinking only appears in the body when on', () {
      final off = TextGenRequest(
        input: 'x',
        model: 'glm-4-6',
        params: TextGenParams.glmDefault(),
      ).toJson();
      expect(off.containsKey('enable_thinking'), isFalse);

      final on = TextGenRequest(
        input: 'x',
        model: 'glm-4-6',
        params: TextGenParams.glmDefault().copyWith(enableThinking: true),
      ).toJson();
      expect(on['enable_thinking'], isTrue);
    });

    test('chat-completions body wraps the input as a single user message', () {
      final req = TextGenRequest(
        input: 'Solve: 17 * 23',
        model: 'glm-4-6',
        systemPrompt: 'Be terse.',
        params: const TextGenParams(enableThinking: true),
      );
      final body = req.toChatCompletionsJson();
      expect(body['model'], 'glm-4-6');
      final messages = (body['messages'] as List).cast<Map>();
      expect(messages, hasLength(2));
      expect(messages[0]['role'], 'system');
      expect(messages[0]['content'], 'Be terse.');
      expect(messages[1]['role'], 'user');
      expect(messages[1]['content'], 'Solve: 17 * 23');
      expect(body['enable_thinking'], isTrue);
      expect(body['max_tokens'], 150);
      expect(body.containsKey('prompt'), isFalse);
    });

    test('chat-completions body omits system message when none set', () {
      final body = const TextGenRequest(
        input: 'hi',
        model: 'glm-4-6',
        params: TextGenParams(enableThinking: true),
      ).toChatCompletionsJson();
      expect((body['messages'] as List), hasLength(1));
      expect(((body['messages'] as List).first as Map)['role'], 'user');
    });

    test('completions body forwards stop strings as a "stop" array', () {
      final req = TextGenRequest(
        input: 'x',
        model: 'glm-4-6',
        stopStrings: ['END', '', '.'],
      );
      expect(req.toJson()['stop'], <String>['END', '.']);
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

  group('splitThinkBlock', () {
    test('splits a leading <think>…</think> block from the answer', () {
      final r = splitThinkBlock(
          '<think>let me reason</think>\nThe final answer.');
      expect(r.reasoning, 'let me reason');
      expect(r.answer, 'The final answer.');
    });

    test('handles a closing tag with no opening tag', () {
      final r = splitThinkBlock('I considered X.</think>\nAnswer here.');
      expect(r.reasoning, 'I considered X.');
      expect(r.answer, 'Answer here.');
    });

    test('returns the whole string as the answer when no </think> is present',
        () {
      final r = splitThinkBlock('Just an answer.');
      expect(r.reasoning, isEmpty);
      expect(r.answer, 'Just an answer.');
    });
  });

  group('extractGeneratedResult', () {
    test('uses parsedReasoning / parsedContent when the server pre-split', () {
      final r = extractGeneratedResult({
        'choices': [
          {
            'parsedReasoning': 'I weighed the options.',
            'parsedContent': 'Picked B.',
            'text': '<think>I weighed the options.</think>Picked B.',
          }
        ]
      });
      expect(r, isNotNull);
      expect(r!.text, 'Picked B.');
      expect(r.reasoning, 'I weighed the options.');
    });

    test('falls back to raw text when parsedContent is missing', () {
      final r = extractGeneratedResult({
        'choices': [
          {'text': 'plain answer'}
        ]
      });
      expect(r!.text, 'plain answer');
      expect(r.reasoning, isEmpty);
    });

    test('legacy {output} responses never have reasoning', () {
      final r = extractGeneratedResult({'output': 'kayra-style continuation'});
      expect(r!.text, 'kayra-style continuation');
      expect(r.hasReasoning, isFalse);
    });
  });
}
