import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'text_gen_service.dart';

/// NovelAI text-generation backend.
///
/// Talks to `text.novelai.net` (a *different* host from image gen's
/// `image.novelai.net`) using the same `pst-` bearer token. Mirrors
/// [NovelAIService]'s timeout + light-retry behaviour.
class NaiTextService implements TextGenService {
  static const String _base = 'https://text.novelai.net';
  static const String _generateUrl = '$_base/ai/generate';
  static const String _generateStreamUrl = '$_base/ai/generate-stream';

  final Dio _dio = Dio();
  final String _apiKey;

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

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      };

  void _requireToken() {
    if (_apiKey.trim().isEmpty) {
      throw TextGenException(
        'NovelAI token not set — add it in Settings.',
      );
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

  /// Maps a [DioException] onto a clear, typed [TextGenException].
  Never _throwForDio(DioException e) {
    final code = e.response?.statusCode;
    final body = _decodeBody(e.response?.data);
    if (code == 401) {
      throw TextGenException(
        'NovelAI rejected the token (401). Check your API key in Settings.',
        statusCode: 401,
      );
    }
    if (code == 402 || code == 403) {
      throw TextGenException(
        'Your NovelAI subscription tier may not allow text generation '
        '(or the requested length). Server said: ${body ?? code}',
        statusCode: code,
      );
    }
    if (code != null) {
      throw TextGenException(
        'NovelAI text API error $code${body != null ? ': $body' : ''}',
        statusCode: code,
      );
    }
    throw TextGenException('Network error talking to NovelAI: ${e.message}');
  }

  String? _decodeBody(dynamic data) {
    if (data == null) return null;
    try {
      if (data is List<int>) return utf8.decode(data, allowMalformed: true);
      if (data is String) return data;
      return data.toString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String> generate(TextGenRequest req) async {
    _requireToken();
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _dio.post(
          _generateUrl,
          data: jsonEncode(req.toJson()),
          options: Options(headers: _headers, responseType: ResponseType.json),
        );
        return _extractOutput(response.data, req);
      } on DioException catch (e) {
        if (_isRetryable(e) && attempt < 2) {
          debugPrint('NaiTextService: retry ${attempt + 1} for generate');
          await Future.delayed(Duration(seconds: (attempt + 1) * 2));
          continue;
        }
        _throwForDio(e);
      }
    }
    throw StateError('unreachable');
  }

  /// Pulls the continuation text out of a non-stream response body.
  ///
  /// Handles `{"output": "..."}` (the common case), a bare string body, and
  /// deployments that echo the `input` back prefixed to the output.
  String _extractOutput(dynamic data, TextGenRequest req) {
    Map<String, dynamic>? map;
    if (data is Map<String, dynamic>) {
      map = data;
    } else if (data is String) {
      final s = data.trim();
      if (s.startsWith('{')) {
        try {
          final decoded = json.decode(s);
          if (decoded is Map<String, dynamic>) map = decoded;
        } catch (_) {}
      }
      map ??= {'output': data};
    } else if (data is List<int>) {
      return _extractOutput(utf8.decode(data, allowMalformed: true), req);
    } else {
      map = {'output': data?.toString() ?? ''};
    }

    var output = map['output']?.toString() ?? '';
    // Some deployments echo the input prefixed to the continuation.
    if (!req.returnFullText &&
        req.input.isNotEmpty &&
        output.startsWith(req.input)) {
      output = output.substring(req.input.length);
    }
    final stopIdx = req.firstStopIndex(output);
    if (stopIdx >= 0) output = output.substring(0, stopIdx);
    return output;
  }

  @override
  Stream<String> generateStream(TextGenRequest req) {
    _requireToken();
    final controller = StreamController<String>();
    StreamSubscription<List<int>>? sub;
    var cancelled = false;

    Future<void> run() async {
      try {
        final response = await _dio.post<ResponseBody>(
          _generateStreamUrl,
          data: jsonEncode(req.toJson()),
          options: Options(
            headers: _headers,
            responseType: ResponseType.stream,
          ),
        );

        final body = response.data;
        if (body == null) {
          controller.close();
          return;
        }

        final parser = SseTextParser();
        final accumulated = StringBuffer();
        var done = false;

        void emitToken(String token) {
          if (token.isEmpty || done) return;
          final before = accumulated.toString();
          final candidate = before + token;
          final stopIdx = req.firstStopIndex(candidate);
          if (stopIdx >= 0) {
            // Emit only the part up to the stop string, then end.
            final keep = candidate.substring(before.length, stopIdx);
            if (keep.isNotEmpty) {
              accumulated.write(keep);
              controller.add(keep);
            }
            done = true;
            return;
          }
          accumulated.write(token);
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
        final completer = Completer<void>();
        sub = body.stream.listen(
          (bytes) {
            if (done || cancelled) return;
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
        await controller.close();
      } on DioException catch (e) {
        // The server may have returned a plain JSON {"output":...} body with a
        // non-stream content type — try to salvage it before erroring.
        if (e.response?.statusCode == 200) {
          try {
            final txt = await _readResponseBodyString(e.response?.data);
            if (txt != null) {
              final out = _extractOutput(txt, req);
              if (out.isNotEmpty) controller.add(out);
              await controller.close();
              return;
            }
          } catch (_) {}
        }
        if (!controller.isClosed) {
          try {
            _throwForDio(e);
          } on TextGenException catch (te) {
            controller.addError(te);
          }
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

  Future<String?> _readResponseBodyString(dynamic data) async {
    if (data == null) return null;
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
  }
}
