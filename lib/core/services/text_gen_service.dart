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

/// `phrase_rep_pen` enum values accepted by the NovelAI text API.
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
/// The panel also allows a free-text override, since NovelAI ships new
/// finetunes (e.g. their "Xialong" GLM-4.6 variant) under ids that change.
const List<String> kKnownTextModels = <String>[
  'glm-4-6',
  'llama-3-erato-v1',
  'kayra-v1',
  'clio-v1',
];

const String kDefaultTextModel = 'glm-4-6';

/// All tunable sampling parameters for a text-generation request.
///
/// Field names map 1:1 onto the NovelAI `parameters` object. Defaults match
/// NovelAI's documented neutral values; [use_string] is always true in v1.
class TextGenParams {
  /// Accept/return plain strings instead of token-id arrays. Always true in v1.
  final bool useString;

  final double temperature;

  /// Output length in tokens. Free/Tablet tiers cap this around ~150;
  /// Scroll/Opus allow much more. Exposed in the UI; default 150.
  final int maxLength;
  final int minLength;

  final int topK;
  final double topP;
  final double topA;
  final double typicalP;
  final double tailFreeSampling;

  final double repetitionPenalty;
  final int repetitionPenaltyRange;
  final double repetitionPenaltySlope;
  final double repetitionPenaltyFrequency;
  final double repetitionPenaltyPresence;

  /// One of [kPhraseRepPenOptions].
  final String phraseRepPen;

  final bool bracketBan;
  final bool generateUntilSentence;

  /// Sampler order. Default `[0,1,2,3]`.
  final List<int> order;

  const TextGenParams({
    this.useString = true,
    this.temperature = 1.0,
    this.maxLength = 150,
    this.minLength = 1,
    this.topK = 0,
    this.topP = 1.0,
    this.topA = 1.0,
    this.typicalP = 1.0,
    this.tailFreeSampling = 1.0,
    this.repetitionPenalty = 1.0,
    this.repetitionPenaltyRange = 2048,
    this.repetitionPenaltySlope = 0.0,
    this.repetitionPenaltyFrequency = 0.0,
    this.repetitionPenaltyPresence = 0.0,
    this.phraseRepPen = 'aggressive',
    this.bracketBan = true,
    this.generateUntilSentence = true,
    this.order = const [0, 1, 2, 3],
  });

  /// NovelAI's neutral GLM preset (also the default).
  factory TextGenParams.glmDefault() => const TextGenParams();

  /// A low-temperature / more deterministic variant.
  factory TextGenParams.deterministic() => const TextGenParams(
        temperature: 0.6,
      );

  /// Named presets surfaced in the panel's preset dropdown.
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
    bool? useString,
    double? temperature,
    int? maxLength,
    int? minLength,
    int? topK,
    double? topP,
    double? topA,
    double? typicalP,
    double? tailFreeSampling,
    double? repetitionPenalty,
    int? repetitionPenaltyRange,
    double? repetitionPenaltySlope,
    double? repetitionPenaltyFrequency,
    double? repetitionPenaltyPresence,
    String? phraseRepPen,
    bool? bracketBan,
    bool? generateUntilSentence,
    List<int>? order,
  }) {
    return TextGenParams(
      useString: useString ?? this.useString,
      temperature: temperature ?? this.temperature,
      maxLength: maxLength ?? this.maxLength,
      minLength: minLength ?? this.minLength,
      topK: topK ?? this.topK,
      topP: topP ?? this.topP,
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
      bracketBan: bracketBan ?? this.bracketBan,
      generateUntilSentence:
          generateUntilSentence ?? this.generateUntilSentence,
      order: order ?? this.order,
    );
  }

  /// Serializes to the exact `parameters` shape the NovelAI text API expects.
  ///
  /// Token-id features (`bad_words_ids`, `stop_sequences`) are emitted as empty
  /// arrays — they're out of scope for v1's string-only mode but the API still
  /// accepts the keys.
  Map<String, dynamic> toJson() => {
        'use_string': useString,
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
        'bad_words_ids': const <List<int>>[],
        'stop_sequences': const <List<int>>[],
        'bracket_ban': bracketBan,
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
      useString: b('use_string', true),
      temperature: d('temperature', 1.0),
      maxLength: i('max_length', 150),
      minLength: i('min_length', 1),
      topK: i('top_k', 0),
      topP: d('top_p', 1.0),
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
      bracketBan: b('bracket_ban', true),
      generateUntilSentence: b('generate_until_sentence', true),
      order: (json['order'] is List)
          ? (json['order'] as List).whereType<num>().map((e) => e.toInt()).toList()
          : const [0, 1, 2, 3],
    );
  }
}

/// A single text-generation request.
///
/// [stopStrings] is a *client-side* post-process: as output accumulates, the
/// first occurrence of any stop string truncates the result and ends the stream.
/// (v1 doesn't use token-id `stop_sequences`.)
class TextGenRequest {
  /// The full raw prompt as one text block. NAI text models continue text —
  /// they don't follow chat turns.
  final String input;
  final String model;
  final TextGenParams params;
  final List<String>? stopStrings;

  /// Whether to return the echoed `input` prepended to the output. Defaults to
  /// false — we only want the continuation.
  final bool returnFullText;

  const TextGenRequest({
    required this.input,
    this.model = kDefaultTextModel,
    this.params = const TextGenParams(),
    this.stopStrings,
    this.returnFullText = false,
  });

  /// The JSON body for `POST /ai/generate` (and `/ai/generate-stream`).
  Map<String, dynamic> toJson() => {
        'input': input,
        'model': model,
        'parameters': params.toJson(),
      };

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

/// Result of parsing a NovelAI text SSE event.
class SseEvent {
  final String token;
  final bool isFinal;
  final bool isDone;

  const SseEvent({this.token = '', this.isFinal = false, this.isDone = false});

  static const SseEvent empty = SseEvent();
}

/// Incremental parser for NovelAI's text `generate-stream` Server-Sent Events.
///
/// The wire format is loosely:
/// ```
/// event: newToken
/// data: {"token":"...", "ptr":<int>, "final":<bool>}
///
/// ```
/// but real deployments are messy: `data:` may or may not have a leading space,
/// events are separated by blank lines, `[DONE]` may appear as a sentinel, and
/// some deployments just return a plain `{"output":"..."}` body instead of a
/// stream. This parser tolerates all of that.
///
/// Feed it raw chunk strings via [addChunk]; it returns the [SseEvent]s that
/// completed within (and across) those chunks. Multi-line `data:` values are
/// concatenated. A flush of any trailing buffered line happens in [finish].
class SseTextParser {
  final StringBuffer _buf = StringBuffer();
  // Accumulated `data:` payload lines for the event currently being assembled.
  final List<String> _dataLines = [];

  /// Feeds a raw chunk of the response body and returns any events that
  /// completed. A blank line (event terminator) flushes the pending event.
  List<SseEvent> addChunk(String chunk) {
    _buf.write(chunk);
    final text = _buf.toString();
    _buf.clear();

    final out = <SseEvent>[];
    // Split on \n. `split` always yields a trailing element after the final
    // separator: for "a\n" that's "" (a spurious empty fragment, NOT a blank
    // line), for "a\nb" (no trailing \n) that's "b" (a partial line to
    // re-buffer). Either way the last fragment is held back here.
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
    // Treat any leftover buffered text as a final line.
    if (_buf.isNotEmpty) {
      final leftover = _buf.toString();
      _buf.clear();
      final ev = _consumeLine(
          leftover.endsWith('\r') ? leftover.substring(0, leftover.length - 1) : leftover);
      if (ev != null) return ev;
    }
    return _flushEvent();
  }

  // Returns a completed event when [line] terminates one (blank line), else null.
  SseEvent? _consumeLine(String line) {
    if (line.isEmpty) {
      return _flushEvent();
    }
    // Comments / heartbeats.
    if (line.startsWith(':')) return null;
    // `event:` / `id:` / `retry:` lines — irrelevant to us.
    if (line.startsWith('event:') || line.startsWith('id:') || line.startsWith('retry:')) {
      return null;
    }
    if (line.startsWith('data:')) {
      var payload = line.substring(5);
      if (payload.startsWith(' ')) payload = payload.substring(1);
      _dataLines.add(payload);
      return null;
    }
    // A bare line that is itself JSON or a sentinel (some servers omit `data:`).
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
        // Streaming token event.
        if (decoded.containsKey('token')) {
          return SseEvent(
            token: decoded['token']?.toString() ?? '',
            isFinal: decoded['final'] == true,
          );
        }
        // Non-streaming-style payload that slipped into the stream.
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
