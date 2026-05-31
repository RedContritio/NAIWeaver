import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'text_gen_service.dart';

/// NovelAI text-generation backend.
///
/// Transports, picked from the model (and whether thinking is on):
/// * **GLM / Xialong** → `POST text.novelai.net/oa/v1/completions`
///   (OpenAI-compatible "completions" — body `{prompt, model, max_tokens,
///   temperature, top_p, [top_k, min_p, frequency_penalty, presence_penalty,
///   stop], stream}`; non-stream `{"choices":[{"text":"…"}]}`; stream is SSE
///   `data: {"choices":[{"text":"…"}]}` lines ending with `data: [DONE]`).
/// * **GLM / Xialong with `enable_thinking`** → `POST text.novelai.net/oa/v1/chat/completions`
///   (OpenAI chat-completions — the input becomes one `user` message so GLM's
///   chat template, which is where `enable_thinking` inserts the
///   `<think>…</think>` scaffolding, is applied; response
///   `{"choices":[{"message":{"content":"…","reasoning_content":"…"}}]}`).
/// * **Kayra / Clio / Erato** (legacy) → `POST text.novelai.net/ai/generate(-stream)`
///   (body `{input, model, parameters:{…}}`; response `{"output":"…"}`; stream
///   is SSE `data: {"token":"…","ptr":N,"final":bool}`).
///
/// Same `pst-` bearer token as image gen. Mirrors [NovelAIService]'s timeouts +
/// light retry on transient 5xx/429.
class NaiTextService implements TextGenService {
  static const String _textHost = 'https://text.novelai.net';

  final Dio _dio = Dio();
  final String _apiKey;
  final Random _rng = Random();

  NaiTextService(this._apiKey) {
    _dio.options.connectTimeout = const Duration(seconds: 60);
    _dio.options.receiveTimeout = const Duration(minutes: 5);
    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        requestHeader: false,
        requestBody: false,
        responseHeader: false,
        responseBody: false,
      ));
    }
  }

  @override
  String get providerId => 'novelai';

  // ─── URLs ─────────────────────────────────────────────────────────────────

  String _urlFor(TextGenRequest req, {required bool stream}) {
    if (isChatStyleModel(req.model)) {
      // GLM/Xialong via NovelAI's OpenAI-compatible endpoints. Streaming is
      // toggled by `"stream": true` in the body, not a separate path.
      // `enable_thinking` only wires in via GLM's chat template, which the
      // *chat* completions endpoint applies — so route thinking requests there.
      return req.params.enableThinking
          ? '$_textHost/oa/v1/chat/completions'
          : '$_textHost/oa/v1/completions';
    }
    return stream
        ? '$_textHost/ai/generate-stream'
        : '$_textHost/ai/generate';
  }

  // ─── headers ──────────────────────────────────────────────────────────────

  String _correlationId() {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return String.fromCharCodes(
        List.generate(6, (_) => alphabet.codeUnitAt(_rng.nextInt(alphabet.length))));
  }

  Map<String, String> _headers({required bool stream}) => {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
        'Accept': stream
            ? 'text/event-stream, application/json'
            : 'application/json',
        'x-correlation-id': _correlationId(),
        'x-initiated-at': DateTime.now().toUtc().toIso8601String(),
      };

  void _requireToken() {
    if (_apiKey.trim().isEmpty) {
      throw TextGenException('NovelAI token not set — add it in Settings.');
    }
  }

  bool _isRetryable(DioException e) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return true;
    }
    final code = e.response?.statusCode;
    return code == 429 || (code != null && code >= 500 && code < 600);
  }

  Map<String, dynamic> _bodyFor(TextGenRequest req, {required bool stream}) {
    if (!req.isChatStyle) return req.toLegacyJson();
    return req.params.enableThinking
        ? req.toChatCompletionsJson(stream: stream)
        : req.toCompletionsJson(stream: stream);
  }

  // ─── non-streaming ────────────────────────────────────────────────────────

  @override
  Future<String> generate(TextGenRequest req) async {
    final result = await generateStructured(req);
    return result.text;
  }

  @override
  Future<TextGenResult> generateStructured(TextGenRequest req) async {
    _requireToken();
    final url = _urlFor(req, stream: false);
    final body = _bodyFor(req, stream: false);
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _dio.post(
          url,
          data: body,
          options: Options(
              headers: _headers(stream: false),
              responseType: ResponseType.json),
        );
        if (kDebugMode && req.params.enableThinking) {
          debugPrint('NaiTextService: thinking response from $url '
              '(sent: ${jsonEncode(body)}) -> ${jsonEncode(response.data)}');
        }
        return _extractResult(response.data, req);
      } on DioException catch (e) {
        if (_isRetryable(e) && attempt < 2) {
          debugPrint('NaiTextService: retry ${attempt + 1} for $url');
          await Future.delayed(Duration(seconds: (attempt + 1) * 2));
          continue;
        }
        final bodyStr = await _readBodyString(e.response?.data);
        debugPrint('NaiTextService: POST $url failed '
            '${e.response?.statusCode}: $bodyStr'
            '${kDebugMode ? '  (sent: ${jsonEncode(body)})' : ''}');
        throw _exceptionForDio(e, bodyStr);
      }
    }
    throw StateError('unreachable');
  }

  /// Decodes a non-stream response into a [TextGenResult], handling input echo,
  /// client-side stop-string truncation, and the `<think>…</think>` split for
  /// thinking-enabled responses (preferring NovelAI's pre-parsed
  /// `parsedReasoning` / `parsedContent` when present, otherwise splitting the
  /// raw text on `</think>` ourselves).
  TextGenResult _extractResult(dynamic data, TextGenRequest req) {
    dynamic decoded = data;
    if (data is String) {
      final s = data.trim();
      if (s.startsWith('{') || s.startsWith('[')) {
        try {
          decoded = json.decode(s);
        } catch (_) {
          decoded = data;
        }
      }
    } else if (data is List<int>) {
      return _extractResult(utf8.decode(data, allowMalformed: true), req);
    }

    if (decoded is Map && decoded['error'] is String) {
      final err = (decoded['error'] as String).trim();
      final preview = extractGeneratedText(decoded);
      if ((preview == null || preview.isEmpty) && err.isNotEmpty) {
        throw TextGenException('NovelAI generation error: $err');
      }
    }

    final raw = extractGeneratedResult(decoded) ?? const TextGenResult(text: '');
    var text = raw.text;
    var reasoning = raw.reasoning;

    // If the server didn't pre-split (e.g. raw `text` field with an inline
    // `<think>` block), split it ourselves.
    if (reasoning.isEmpty && text.contains('</think>')) {
      final split = splitThinkBlock(text);
      reasoning = split.reasoning;
      text = split.answer;
    }

    if (!req.returnFullText &&
        req.input.isNotEmpty &&
        text.startsWith(req.input)) {
      text = text.substring(req.input.length);
    }
    final stopIdx = req.firstStopIndex(text);
    if (stopIdx >= 0) text = text.substring(0, stopIdx);

    return TextGenResult(text: text, reasoning: reasoning);
  }

  // ─── streaming ────────────────────────────────────────────────────────────

  @override
  Stream<String> generateStream(TextGenRequest req) {
    _requireToken();
    // When thinking is on, we want the server's reliable reasoning/answer
    // split — force a non-stream call and emit the answer as a single chunk.
    // Callers that need the reasoning text should call [generateStructured]
    // directly (and the notifier already does for thinking requests).
    if (req.params.enableThinking) {
      final controller = StreamController<String>();
      controller.onListen = () async {
        try {
          final result = await generateStructured(req);
          if (!controller.isClosed) {
            if (result.text.isNotEmpty) controller.add(result.text);
            await controller.close();
          }
        } on TextGenException catch (te) {
          if (!controller.isClosed) {
            controller.addError(te);
            await controller.close();
          }
        } catch (e) {
          if (!controller.isClosed) {
            controller.addError(TextGenException('Text generation failed: $e'));
            await controller.close();
          }
        }
      };
      return controller.stream;
    }
    final controller = StreamController<String>();
    StreamSubscription<List<int>>? sub;
    var cancelled = false;
    var emittedAnything = false;
    final url = _urlFor(req, stream: true);
    final body = _bodyFor(req, stream: true);

    Future<void> fallbackToNonStream(Object? streamError) async {
      if (cancelled || controller.isClosed) return;
      try {
        final out = await generate(req);
        if (!cancelled && !controller.isClosed) {
          if (out.isNotEmpty) controller.add(out);
          await controller.close();
        }
      } on TextGenException catch (te) {
        if (!controller.isClosed) {
          controller.addError(te);
          await controller.close();
        }
      } catch (e) {
        if (!controller.isClosed) {
          controller.addError(streamError is TextGenException
              ? streamError
              : TextGenException('Text generation failed: $e'));
          await controller.close();
        }
      }
    }

    Future<void> run() async {
      try {
        final response = await _dio.post<ResponseBody>(
          url,
          data: body,
          options: Options(
              headers: _headers(stream: true),
              responseType: ResponseType.stream),
        );

        final rb = response.data;
        if (rb == null) {
          await fallbackToNonStream(null);
          return;
        }

        final contentType =
            (response.headers.value('content-type') ?? '').toLowerCase();
        final looksLikeStream = contentType.contains('event-stream') ||
            contentType.isEmpty ||
            contentType.contains('text/');

        final parser = SseTextParser();
        final accumulated = StringBuffer();
        var done = false;

        void emitToken(String token) {
          if (token.isEmpty || done) return;
          final before = accumulated.toString();
          final candidate = before + token;
          final stopIdx = req.firstStopIndex(candidate);
          if (stopIdx >= 0) {
            final keep = candidate.substring(before.length, stopIdx);
            if (keep.isNotEmpty) {
              accumulated.write(keep);
              emittedAnything = true;
              controller.add(keep);
            }
            done = true;
            return;
          }
          accumulated.write(token);
          emittedAnything = true;
          controller.add(token);
        }

        void handleEvent(SseEvent ev) {
          if (done) return;
          if (ev.isDone) {
            done = true;
            return;
          }
          if (ev.token.isNotEmpty) emitToken(ev.token);
          if (ev.isFinal) done = true;
        }

        final decoder = const Utf8Decoder(allowMalformed: true);
        final bodyBytes = <int>[];
        final completer = Completer<void>();
        sub = rb.stream.listen(
          (bytes) {
            if (done || cancelled) return;
            bodyBytes.addAll(bytes);
            final chunk = decoder.convert(bytes);
            for (final ev in parser.addChunk(chunk)) {
              handleEvent(ev);
              if (done) break;
            }
            if (done) {
              sub?.cancel();
              if (!completer.isCompleted) completer.complete();
            }
          },
          onError: (Object e, StackTrace st) {
            if (!completer.isCompleted) completer.completeError(e, st);
          },
          onDone: () {
            if (!done) {
              final ev = parser.finish();
              if (ev != null) handleEvent(ev);
            }
            if (!completer.isCompleted) completer.complete();
          },
          cancelOnError: true,
        );

        await completer.future;

        if (cancelled) {
          if (!controller.isClosed) await controller.close();
          return;
        }

        if (!emittedAnything) {
          // Nothing came through as SSE — maybe the server returned a plain
          // JSON body (some deployments don't stream). Try to parse what we
          // buffered, then fall back to the non-stream call.
          final raw = utf8.decode(bodyBytes, allowMalformed: true).trim();
          if (!looksLikeStream || raw.startsWith('{') || raw.startsWith('[')) {
            try {
              final out = extractGeneratedText(json.decode(raw));
              if (out != null && out.isNotEmpty) {
                var text = out;
                if (!req.returnFullText &&
                    req.input.isNotEmpty &&
                    text.startsWith(req.input)) {
                  text = text.substring(req.input.length);
                }
                final si = req.firstStopIndex(text);
                if (si >= 0) text = text.substring(0, si);
                if (text.isNotEmpty) controller.add(text);
                await controller.close();
                return;
              }
            } catch (_) {/* fall through */}
          }
          await fallbackToNonStream(null);
          return;
        }

        if (!controller.isClosed) await controller.close();
      } on DioException catch (e) {
        final bodyStr = await _readBodyString(e.response?.data);
        if (e.response?.statusCode == 200 && bodyStr != null) {
          try {
            final out = extractGeneratedText(json.decode(bodyStr.trim()));
            if (out != null && out.isNotEmpty && !controller.isClosed) {
              controller.add(out);
              await controller.close();
              return;
            }
          } catch (_) {}
        }
        debugPrint('NaiTextService: POST $url failed '
            '${e.response?.statusCode}: $bodyStr'
            '${kDebugMode ? '  (sent: ${jsonEncode(body)})' : ''}');
        final code = e.response?.statusCode;
        // For ambiguous server-side errors (not auth/billing/bad-request), the
        // non-stream endpoint might still work — try it once.
        if (!emittedAnything &&
            code != 400 &&
            code != 401 &&
            code != 402 &&
            code != 403 &&
            code != null) {
          await fallbackToNonStream(_exceptionForDio(e, bodyStr));
          return;
        }
        if (!controller.isClosed) {
          controller.addError(_exceptionForDio(e, bodyStr));
          await controller.close();
        }
      } on TextGenException catch (te) {
        if (!controller.isClosed) {
          controller.addError(te);
          await controller.close();
        }
      } catch (e) {
        if (!controller.isClosed) {
          controller.addError(TextGenException('Text generation failed: $e'));
          await controller.close();
        }
      }
    }

    controller.onListen = run;
    controller.onCancel = () async {
      cancelled = true;
      await sub?.cancel();
    };
    return controller.stream;
  }

  // ─── error helpers ────────────────────────────────────────────────────────

  TextGenException _exceptionForDio(DioException e, String? body) {
    final code = e.response?.statusCode;
    final detail = _serverMessage(body) ?? _trimBody(body);
    if (code == 401) {
      return TextGenException(
        'NovelAI rejected the token (401).${detail != null ? ' $detail' : ''} '
        'Check your API key in Settings.',
        statusCode: 401,
      );
    }
    if (code == 402) {
      return TextGenException(
        detail != null
            ? 'NovelAI: $detail (402 — an active subscription is required for '
                'this endpoint or model).'
            : 'NovelAI requires an active subscription for this endpoint/model '
                '(402).',
        statusCode: 402,
      );
    }
    if (code == 403) {
      return TextGenException(
        detail != null
            ? 'NovelAI refused the request (403): $detail'
            : 'NovelAI refused the request (403) — your tier may not allow this '
                'model or length.',
        statusCode: 403,
      );
    }
    if (code == 400) {
      return TextGenException(
        'NovelAI rejected the request (400)'
        '${detail != null ? ': $detail' : ' — bad parameters'}.',
        statusCode: 400,
      );
    }
    if (code != null) {
      return TextGenException(
        'NovelAI text API error $code${detail != null ? ': $detail' : ''}',
        statusCode: code,
      );
    }
    return TextGenException('Network error talking to NovelAI: ${e.message}');
  }

  /// Materializes a response body into a string, draining a `ResponseBody`
  /// stream if necessary. Never throws.
  Future<String?> _readBodyString(dynamic data) async {
    if (data == null) return null;
    try {
      if (data is String) return data;
      if (data is List<int>) return utf8.decode(data, allowMalformed: true);
      if (data is ResponseBody) {
        final chunks = <int>[];
        await for (final c in data.stream) {
          chunks.addAll(c);
        }
        return utf8.decode(chunks, allowMalformed: true);
      }
      if (data is Map) return jsonEncode(data);
      return data.toString();
    } catch (_) {
      return null;
    }
  }

  String? _serverMessage(String? body) {
    if (body == null) return null;
    final trimmed = body.trim();
    if (!trimmed.startsWith('{')) return null;
    try {
      final decoded = json.decode(trimmed);
      if (decoded is Map) {
        final m = decoded['message'] ?? decoded['error'] ?? decoded['detail'];
        if (m != null) {
          final s = m.toString().trim();
          if (s.isNotEmpty) return s;
        }
      }
    } catch (_) {}
    return null;
  }

  String? _trimBody(String? body) {
    if (body == null) return null;
    final s = body.trim();
    if (s.isEmpty) return null;
    return s.length > 300 ? '${s.substring(0, 300)}…' : s;
  }
}
