import 'dart:convert';

/// Abstraction over a text-generation backend.
///
/// v1 only ships a NovelAI implementation ([NaiTextService]), but the panel /
/// notifier talk to this interface so other providers can be slotted in later.
abstract class TextGenService {
  /// Streams generated text token-by-token (or chunk-by-chunk).
  ///
  /// Implementations must enforce [TextGenRequest.stopStrings] client-side
  /// (truncating the *yielded* chunk at the stop string and ending the stream).
  Stream<String> generateStream(TextGenRequest req);

  /// One-shot convenience: awaits the full generated continuation.
  Future<String> generate(TextGenRequest req);

  /// Stable id for the provider, e.g. `"novelai"`.
  String get providerId;
}

/// Thrown by a [TextGenService] when generation fails.
///
/// [statusCode] is the HTTP status when the error came from the server
/// (null for client-side errors like a missing token or a network failure).
class TextGenException implements Exception {
  final int? statusCode;
  final String message;

  TextGenException(this.message, {this.statusCode});

  @override
  String toString() => statusCode == null
      ? 'TextGenException: $message'
      : 'TextGenException($statusCode): $message';
}

/// `phrase_rep_pen` enum values accepted by the legacy (Kayra/Clio/Erato) text
/// API. Not used by GLM-style chat models.
const List<String> kPhraseRepPenOptions = <String>[
  'off',
  'very_light',
  'light',
  'medium',
  'aggressive',
  'very_aggressive',
];

/// Model ids known to work with the NovelAI text API.
///
/// `glm-4-6` / `glm-4-5` / `xialong-v1` use the OpenAI-compatible completions
/// endpoint; `kayra-v1` / `clio-v1` / `llama-3-erato-v1` use the legacy
/// `{input, parameters}` body. The panel also allows a free-text override since
/// NovelAI ships new finetunes under ids that change.
const List<String> kKnownTextModels = <String>[
  'glm-4-6',
  'glm-4-5',
  'xialong-v1',
  'llama-3-erato-v1',
  'kayra-v1',
  'clio-v1',
];

const String kDefaultTextModel = 'glm-4-6';

/// True if [model] should be driven via the chat/completions-style API
/// (`messages` + OpenAI-ish params, response `choices[0].text`) rather than the
/// legacy `{input, parameters}` text-completion API.
///
/// Currently that's the GLM family; NovelAI's docs say only models that use the
/// "OpenAI-like completions endpoint" support this path. New chat-style ids can
/// be picked up by name pattern.
bool isChatStyleModel(String model) {
  final m = model.toLowerCase().trim();
  return m.startsWith('glm') ||
      m.contains('xialong') ||
      m.contains('chat');
}

/// Tunable sampling parameters.
///
/// Covers both the legacy `parameters` object (Kayra/Clio/Erato) and the
/// OpenAI-compatible completions params (GLM/Xialong). Only the relevant subset
/// is serialized for each transport — see [toLegacyParametersJson] and
/// [TextGenRequest.toCompletionsJson].
class TextGenParams {
  // — Shared / chat-style —
  final double temperature;

  /// Output length in tokens. Maps to `max_length` (legacy) / `max_tokens`
  /// (chat). Free/Tablet tiers cap this lower than Scroll/Opus.
  final int maxLength;
  final int minLength;
  final int topK;
  final double topP;

  /// Chat-only: OpenAI-style frequency penalty (≈ legacy
  /// `repetition_penalty_frequency`).
  final double frequencyPenalty;

  /// Chat-only: OpenAI-style presence penalty (≈ legacy
  /// `repetition_penalty_presence`).
  final double presencePenalty;

  /// Chat-only: min-p sampling cutoff (0 disables).
  final double minP;

  // — Legacy-only —
  final double topA;
  final double typicalP;
  final double tailFreeSampling;
  final double repetitionPenalty;
  final int repetitionPenaltyRange;
  final double repetitionPenaltySlope;
  final double repetitionPenaltyFrequency;
  final double repetitionPenaltyPresence;
  final String phraseRepPen;
  final bool generateUntilSentence;
  final List<int> order;

  const TextGenParams({
    this.temperature = 1.0,
    this.maxLength = 150,
    this.minLength = 1,
    this.topK = 0,
    this.topP = 1.0,
    this.frequencyPenalty = 0.0,
    this.presencePenalty = 0.0,
    this.minP = 0.0,
    this.topA = 1.0,
    this.typicalP = 1.0,
    this.tailFreeSampling = 1.0,
    this.repetitionPenalty = 1.0,
    this.repetitionPenaltyRange = 2048,
    this.repetitionPenaltySlope = 0.0,
    this.repetitionPenaltyFrequency = 0.0,
    this.repetitionPenaltyPresence = 0.0,
    this.phraseRepPen = 'aggressive',
    this.generateUntilSentence = true,
    this.order = const [0, 1, 2, 3],
  });

  /// Neutral GLM defaults (also the overall default).
  factory TextGenParams.glmDefault() => const TextGenParams();

  /// A low-temperature / more deterministic variant.
  factory TextGenParams.deterministic() =>
      const TextGenParams(temperature: 0.6);

  static const List<String> presetNames = <String>[
    'GLM Default',
    'Deterministic (low temp)',
  ];

  static TextGenParams byPresetName(String name) {
    switch (name) {
      case 'Deterministic (low temp)':
        return TextGenParams.deterministic();
      case 'GLM Default':
      default:
        return TextGenParams.glmDefault();
    }
  }

  TextGenParams copyWith({
    double? temperature,
    int? maxLength,
    int? minLength,
    int? topK,
    double? topP,
    double? frequencyPenalty,
    double? presencePenalty,
    double? minP,
    double? topA,
    double? typicalP,
    double? tailFreeSampling,
    double? repetitionPenalty,
    int? repetitionPenaltyRange,
    double? repetitionPenaltySlope,
    double? repetitionPenaltyFrequency,
    double? repetitionPenaltyPresence,
    String? phraseRepPen,
    bool? generateUntilSentence,
    List<int>? order,
  }) {
    return TextGenParams(
      temperature: temperature ?? this.temperature,
      maxLength: maxLength ?? this.maxLength,
      minLength: minLength ?? this.minLength,
      topK: topK ?? this.topK,
      topP: topP ?? this.topP,
      frequencyPenalty: frequencyPenalty ?? this.frequencyPenalty,
      presencePenalty: presencePenalty ?? this.presencePenalty,
      minP: minP ?? this.minP,
      topA: topA ?? this.topA,
      typicalP: typicalP ?? this.typicalP,
      tailFreeSampling: tailFreeSampling ?? this.tailFreeSampling,
      repetitionPenalty: repetitionPenalty ?? this.repetitionPenalty,
      repetitionPenaltyRange:
          repetitionPenaltyRange ?? this.repetitionPenaltyRange,
      repetitionPenaltySlope:
          repetitionPenaltySlope ?? this.repetitionPenaltySlope,
      repetitionPenaltyFrequency:
          repetitionPenaltyFrequency ?? this.repetitionPenaltyFrequency,
      repetitionPenaltyPresence:
          repetitionPenaltyPresence ?? this.repetitionPenaltyPresence,
      phraseRepPen: phraseRepPen ?? this.phraseRepPen,
      generateUntilSentence:
          generateUntilSentence ?? this.generateUntilSentence,
      order: order ?? this.order,
    );
  }

  /// The legacy `parameters` object for `kayra-v1` / `clio-v1` /
  /// `llama-3-erato-v1` on `POST /ai/generate(-stream)`.
  ///
  /// Matches the shape SillyTavern sends (and the NovelAI Swagger
  /// `AiGenerateParameters`). `use_string` is always true in v1; token-id
  /// features (`bad_words_ids`, token-array `stop_sequences`) are omitted.
  Map<String, dynamic> toLegacyParametersJson() => {
        'use_string': true,
        'temperature': temperature,
        'max_length': maxLength,
        'min_length': minLength,
        'top_k': topK,
        'top_p': topP,
        'top_a': topA,
        'typical_p': typicalP,
        'tail_free_sampling': tailFreeSampling,
        'repetition_penalty': repetitionPenalty,
        'repetition_penalty_range': repetitionPenaltyRange,
        'repetition_penalty_slope': repetitionPenaltySlope,
        'repetition_penalty_frequency': repetitionPenaltyFrequency,
        'repetition_penalty_presence': repetitionPenaltyPresence,
        'phrase_rep_pen': phraseRepPen,
        'generate_until_sentence': generateUntilSentence,
        'order': order,
        // Required by the Swagger schema for the legacy endpoint.
        'force_emotion': false,
      };

  /// The OpenAI-completions param fields for GLM/Xialong. (The full body is
  /// assembled by [TextGenRequest.toCompletionsJson]; this is just the param
  /// subset, kept for tests/inspection.)
  Map<String, dynamic> toChatJson() => {
        'temperature': temperature,
        'max_tokens': maxLength,
        'top_p': topP,
        if (topK > 0) 'top_k': topK,
        if (frequencyPenalty != 0.0) 'frequency_penalty': frequencyPenalty,
        if (presencePenalty != 0.0) 'presence_penalty': presencePenalty,
        if (minP > 0.0) 'min_p': minP,
      };

  /// Serialization used by tests / history: a stable superset of all fields.
  Map<String, dynamic> toJson() => {
        'temperature': temperature,
        'max_length': maxLength,
        'min_length': minLength,
        'top_k': topK,
        'top_p': topP,
        'frequency_penalty': frequencyPenalty,
        'presence_penalty': presencePenalty,
        'min_p': minP,
        'top_a': topA,
        'typical_p': typicalP,
        'tail_free_sampling': tailFreeSampling,
        'repetition_penalty': repetitionPenalty,
        'repetition_penalty_range': repetitionPenaltyRange,
        'repetition_penalty_slope': repetitionPenaltySlope,
        'repetition_penalty_frequency': repetitionPenaltyFrequency,
        'repetition_penalty_presence': repetitionPenaltyPresence,
        'phrase_rep_pen': phraseRepPen,
        'generate_until_sentence': generateUntilSentence,
        'order': order,
      };

  factory TextGenParams.fromJson(Map<String, dynamic> json) {
    double d(String k, double fallback) {
      final v = json[k];
      return v is num ? v.toDouble() : fallback;
    }

    int i(String k, int fallback) {
      final v = json[k];
      return v is num ? v.toInt() : fallback;
    }

    bool b(String k, bool fallback) {
      final v = json[k];
      return v is bool ? v : fallback;
    }

    return TextGenParams(
      temperature: d('temperature', 1.0),
      maxLength: i('max_length', i('max_tokens', 150)),
      minLength: i('min_length', 1),
      topK: i('top_k', 0),
      topP: d('top_p', 1.0),
      frequencyPenalty: d('frequency_penalty', 0.0),
      presencePenalty: d('presence_penalty', 0.0),
      minP: d('min_p', 0.0),
      topA: d('top_a', 1.0),
      typicalP: d('typical_p', 1.0),
      tailFreeSampling: d('tail_free_sampling', 1.0),
      repetitionPenalty: d('repetition_penalty', 1.0),
      repetitionPenaltyRange: i('repetition_penalty_range', 2048),
      repetitionPenaltySlope: d('repetition_penalty_slope', 0.0),
      repetitionPenaltyFrequency: d('repetition_penalty_frequency', 0.0),
      repetitionPenaltyPresence: d('repetition_penalty_presence', 0.0),
      phraseRepPen: (json['phrase_rep_pen'] is String)
          ? json['phrase_rep_pen'] as String
          : 'aggressive',
      generateUntilSentence: b('generate_until_sentence', true),
      order: (json['order'] is List)
          ? (json['order'] as List)
              .whereType<num>()
              .map((e) => e.toInt())
              .toList()
          : const [0, 1, 2, 3],
    );
  }
}

/// A single text-generation request.
///
/// [input] is the raw text the model should continue. NAI text models
/// *continue* text — they don't follow chat turns. For GLM-style models we send
/// it as the `prompt` of NovelAI's OpenAI-compatible **completions** endpoint
/// (`POST text.novelai.net/oa/v1/completions`); for legacy models (Kayra/Clio/
/// Erato) it's the `input` of `POST text.novelai.net/ai/generate`.
///
/// [systemPrompt], if set, is prepended to the prompt (the completions endpoint
/// has no separate system role).
///
/// [stopStrings] is forwarded as the `stop` array (GLM) and *also* enforced
/// client-side (the reliable v1 behaviour, and the only one for legacy models).
class TextGenRequest {
  final String input;
  final String model;
  final TextGenParams params;
  final List<String>? stopStrings;
  final String systemPrompt;

  /// Whether to keep the echoed `input` if the server prepends it (defaults to
  /// false — we only want the continuation).
  final bool returnFullText;

  const TextGenRequest({
    required this.input,
    this.model = kDefaultTextModel,
    this.params = const TextGenParams(),
    this.stopStrings,
    this.systemPrompt = '',
    this.returnFullText = false,
  });

  bool get isChatStyle => isChatStyleModel(model);

  /// The full prompt string (system prefix + input).
  String get prompt =>
      systemPrompt.trim().isEmpty ? input : '${systemPrompt.trim()}\n$input';

  List<String>? get cleanStops {
    final s = stopStrings;
    if (s == null) return null;
    final out = s.where((x) => x.isNotEmpty).toList();
    return out.isEmpty ? null : out;
  }

  /// JSON body for a legacy `{input, model, parameters}` request
  /// (`/ai/generate(-stream)`, Kayra/Clio/Erato).
  Map<String, dynamic> toLegacyJson() => {
        'input': input,
        'model': model,
        'parameters': params.toLegacyParametersJson(),
      };

  /// JSON body for the OpenAI-compatible completions endpoint
  /// (`/oa/v1/completions`, GLM/Xialong). [stream] toggles SSE.
  Map<String, dynamic> toCompletionsJson({bool stream = false}) => {
        'prompt': prompt,
        'model': model,
        'max_tokens': params.maxLength,
        'temperature': params.temperature,
        'top_p': params.topP,
        if (params.topK > 0) 'top_k': params.topK,
        if (params.minP > 0.0) 'min_p': params.minP,
        if (params.frequencyPenalty != 0.0)
          'frequency_penalty': params.frequencyPenalty,
        if (params.presencePenalty != 0.0)
          'presence_penalty': params.presencePenalty,
        if (cleanStops != null) 'stop': cleanStops,
        'stream': stream,
      };

  /// Picks the right *non-stream* body for [model] (used by [toJson] and tests).
  Map<String, dynamic> toJson() =>
      isChatStyle ? toCompletionsJson(stream: false) : toLegacyJson();

  /// Returns the index of the earliest stop string in [text], or -1 if none of
  /// [stopStrings] occur. Empty stop strings are ignored.
  int firstStopIndex(String text) {
    final stops = stopStrings;
    if (stops == null || stops.isEmpty) return -1;
    int best = -1;
    for (final s in stops) {
      if (s.isEmpty) continue;
      final idx = text.indexOf(s);
      if (idx >= 0 && (best == -1 || idx < best)) best = idx;
    }
    return best;
  }
}

/// One entry in the panel's local generation history.
class TextGenHistoryEntry {
  final String input;
  final String output;
  final TextGenParams params;
  final String model;
  final DateTime timestamp;

  TextGenHistoryEntry({
    required this.input,
    required this.output,
    required this.params,
    required this.model,
    required this.timestamp,
  });
}

/// Pulls the generated continuation out of a parsed response body, handling
/// both the legacy `{"output": "..."}` shape and the chat `{"choices":[{"text"|
/// "message":{"content"}}]}` shape. Returns null if nothing usable is found.
String? extractGeneratedText(dynamic decoded) {
  if (decoded is! Map) return decoded is String ? decoded : null;
  // Legacy text-completion shape.
  final out = decoded['output'];
  if (out is String && out.isNotEmpty) return out;
  // Chat/completions shape.
  final choices = decoded['choices'];
  if (choices is List && choices.isNotEmpty) {
    final c0 = choices.first;
    if (c0 is Map) {
      final text = c0['text'];
      if (text is String) return text;
      final msg = c0['message'];
      if (msg is Map && msg['content'] is String) return msg['content'] as String;
      final delta = c0['delta'];
      if (delta is Map && delta['content'] is String) {
        return delta['content'] as String;
      }
    }
  }
  // Some streamed shapes nest token text directly.
  if (decoded['token'] is String) return decoded['token'] as String;
  return null;
}

/// Result of parsing one SSE event from a NovelAI text stream.
class SseEvent {
  final String token;
  final bool isFinal;
  final bool isDone;

  const SseEvent({this.token = '', this.isFinal = false, this.isDone = false});

  static const SseEvent empty = SseEvent();
}

/// Incremental parser for NovelAI text streams (`/ai/generate-stream`).
///
/// Tolerates the messiness of real SSE: `data:` with or without a leading
/// space, multi-line `data:` values, blank-line event terminators, `[DONE]`
/// sentinels, comment/`event:`/`id:` lines, and a non-streamed plain-JSON body
/// (`{"output":...}` or `{"choices":[...]}`) that some deployments return
/// instead of an event stream.
///
/// Recognised event payloads:
/// * legacy text: `{"token":"...","ptr":N,"final":bool}`
/// * chat-completions chunk: `{"choices":[{"delta":{"content":"..."}}]}` or
///   `{"choices":[{"text":"..."}]}`
/// * one-shot: `{"output":"..."}` (treated as a single final token)
class SseTextParser {
  final StringBuffer _buf = StringBuffer();
  final List<String> _dataLines = [];

  /// Feeds a raw chunk of the response body; returns events that completed.
  List<SseEvent> addChunk(String chunk) {
    _buf.write(chunk);
    final text = _buf.toString();
    _buf.clear();

    final out = <SseEvent>[];
    // `split('\n')` always yields a trailing element after the final separator:
    // for "a\n" that's "" (a spurious empty fragment, NOT a blank line); for
    // "a\nb" that's "b" (a partial line). Either way the last fragment is held
    // back here — re-buffered if the chunk didn't end with '\n', dropped if it
    // did.
    final parts = text.split('\n');
    final lastIsPartial = !text.endsWith('\n');
    final lineCount = parts.length - 1;
    for (int i = 0; i < lineCount; i++) {
      final raw = parts[i];
      final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      final ev = _consumeLine(line);
      if (ev != null) out.add(ev);
    }
    if (lastIsPartial) _buf.write(parts.last);
    return out;
  }

  /// Flushes any pending event (e.g. a final `data:` line with no trailing
  /// blank line). Returns the event if one was pending, else null.
  SseEvent? finish() {
    if (_buf.isNotEmpty) {
      final leftover = _buf.toString();
      _buf.clear();
      final ev = _consumeLine(leftover.endsWith('\r')
          ? leftover.substring(0, leftover.length - 1)
          : leftover);
      if (ev != null) return ev;
    }
    return _flushEvent();
  }

  SseEvent? _consumeLine(String line) {
    if (line.isEmpty) return _flushEvent();
    if (line.startsWith(':')) return null; // comment / heartbeat
    if (line.startsWith('event:') ||
        line.startsWith('id:') ||
        line.startsWith('retry:')) {
      return null;
    }
    if (line.startsWith('data:')) {
      var payload = line.substring(5);
      if (payload.startsWith(' ')) payload = payload.substring(1);
      _dataLines.add(payload);
      return null;
    }
    final trimmed = line.trim();
    if (trimmed == '[DONE]') {
      _dataLines.clear();
      return const SseEvent(isDone: true);
    }
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      _dataLines.add(trimmed);
    }
    return null;
  }

  SseEvent? _flushEvent() {
    if (_dataLines.isEmpty) return null;
    final joined = _dataLines.join('\n').trim();
    _dataLines.clear();
    if (joined.isEmpty) return null;
    if (joined == '[DONE]') return const SseEvent(isDone: true);
    try {
      final decoded = json.decode(joined);
      if (decoded is Map<String, dynamic>) {
        // An `error` field usually means end-of-stream (legacy behaviour).
        // We surface it as a terminal empty event; the caller logs the body.
        if (decoded['error'] is String &&
            (decoded['error'] as String).isNotEmpty &&
            !decoded.containsKey('token') &&
            !decoded.containsKey('choices')) {
          return const SseEvent(isFinal: true);
        }
        // Legacy token event.
        if (decoded.containsKey('token')) {
          return SseEvent(
            token: decoded['token']?.toString() ?? '',
            isFinal: decoded['final'] == true,
          );
        }
        // Chat-completions chunk.
        final choices = decoded['choices'];
        if (choices is List && choices.isNotEmpty) {
          final c0 = choices.first;
          String tok = '';
          var fin = false;
          if (c0 is Map) {
            final delta = c0['delta'];
            if (delta is Map && delta['content'] is String) {
              tok = delta['content'] as String;
            } else if (c0['text'] is String) {
              tok = c0['text'] as String;
            } else if (c0['message'] is Map &&
                (c0['message'] as Map)['content'] is String) {
              tok = (c0['message'] as Map)['content'] as String;
            }
            final fr = c0['finish_reason'];
            if (fr != null && fr != false) fin = true;
          }
          return SseEvent(token: tok, isFinal: fin);
        }
        // One-shot body that slipped into the stream.
        if (decoded.containsKey('output')) {
          return SseEvent(
            token: decoded['output']?.toString() ?? '',
            isFinal: true,
          );
        }
      }
    } catch (_) {
      // Not JSON — ignore this event rather than crash the stream.
    }
    return null;
  }
}
