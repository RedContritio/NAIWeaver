import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';

import '../gateway/backend_exception.dart';
import '../gateway/backend_gateway.dart';
import '../gateway/backend_rules.dart';

/// A fresh opaque id for an idempotency key / client request id (8..128
/// characters, docs/GATEWAY_CONTRACT.md §4 and §5).
String newClientRequestId() {
  final random = math.Random.secure();
  int uint32() => random.nextInt(1 << 16) * (1 << 16) + random.nextInt(1 << 16);
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-'
      '${uint32().toRadixString(16).padLeft(8, '0')}-'
      '${uint32().toRadixString(16).padLeft(8, '0')}';
}

/// Request-option key: a 401 `not_authenticated` on this call is handled by
/// the caller and must not raise the session-expired flow.
const String backendSkipAuthCallbackKey = 'backend_skip_auth_callback';

const String _retryAttemptKey = 'backend_retry_attempt';

/// The single HTTP client for everything the web app sends to the gateway.
///
/// Every failure surfaces as a [BackendException]; only idempotent GETs are
/// retried (a POST may already have been charged), and a 401
/// `not_authenticated` is reported through [onNotAuthenticated].
class BackendClient {
  BackendClient({
    Dio? dio,
    this.retryDelays = const [Duration(seconds: 1), Duration(seconds: 2)],
  }) : dio = dio ?? Dio() {
    this.dio.options
      ..connectTimeout = const Duration(seconds: 20)
      ..receiveTimeout = const Duration(seconds: 30);
    this.dio.interceptors.add(_BackendInterceptor(this));
  }

  static final BackendClient shared = BackendClient();

  /// Paid tools and text generation hold the connection while NovelAI works.
  static const Duration longReceiveTimeout = Duration(minutes: 5);

  static Options longRunning({
    ResponseType? responseType,
    Map<String, dynamic>? headers,
  }) => Options(
    responseType: responseType,
    headers: headers,
    receiveTimeout: longReceiveTimeout,
  );

  final Dio dio;

  /// Waits between the automatic retries of a failed GET; its length is the
  /// number of retries.
  final List<Duration> retryDelays;

  /// Called for every 401 `not_authenticated` (the gateway session is gone).
  void Function()? onNotAuthenticated;

  /// The image rules of the signed-in user, from `/api/me`.
  ImageRules? imageRules;

  /// The rules, fetched from `/api/me` when no one has supplied them yet.
  Future<ImageRules> requireImageRules() async {
    final known = imageRules;
    if (known != null) return known;
    final response = await get<dynamic>('/api/me');
    final data = response.data;
    final rules = ImageRules.tryParse(
      data is Map<String, dynamic> ? data['rules'] : null,
    );
    if (rules == null) {
      throw const BackendException(
        statusCode: null,
        code: BackendErrorCode.invalidResponse,
      );
    }
    return imageRules = rules;
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => request<T>(
    'GET',
    path,
    queryParameters: queryParameters,
    options: options,
  );

  Future<Response<T>> post<T>(String path, {Object? data, Options? options}) =>
      request<T>('POST', path, data: data, options: options);

  Future<Response<T>> delete<T>(String path, {Options? options}) =>
      request<T>('DELETE', path, options: options);

  /// Sends [method] to the gateway path [path]; throws [BackendException].
  Future<Response<T>> request<T>(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await dio.request<T>(
        backendUrl(path),
        data: data,
        queryParameters: queryParameters,
        options: (options ?? Options()).copyWith(method: method),
      );
    } on DioException catch (error) {
      final mapped = error.error;
      if (mapped is BackendException) throw mapped;
      rethrow;
    }
  }
}

class _BackendInterceptor extends Interceptor {
  _BackendInterceptor(this._client);

  final BackendClient _client;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final attempt = (options.extra[_retryAttemptKey] as int?) ?? 0;
    if (options.method == 'GET' &&
        attempt < _client.retryDelays.length &&
        _isTransient(err)) {
      await Future<void>.delayed(_client.retryDelays[attempt]);
      options.extra[_retryAttemptKey] = attempt + 1;
      try {
        handler.resolve(await _client.dio.fetch<dynamic>(options));
      } on DioException catch (retryError) {
        handler.reject(retryError);
      }
      return;
    }
    final exception = await _toException(err);
    if (exception.isNotAuthenticated &&
        options.extra[backendSkipAuthCallbackKey] != true) {
      _client.onNotAuthenticated?.call();
    }
    handler.reject(
      DioException(
        requestOptions: options,
        response: err.response,
        type: err.type,
        error: exception,
      ),
    );
  }

  bool _isTransient(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return true;
      default:
        final status = error.response?.statusCode;
        return status == 503 || status == 504;
    }
  }

  Future<BackendException> _toException(DioException error) async {
    final response = error.response;
    if (response == null) {
      final timedOut =
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout;
      return BackendException(
        statusCode: null,
        code: timedOut ? BackendErrorCode.timeout : BackendErrorCode.network,
      );
    }
    return parseBackendError(
      response.statusCode,
      await _decodeBody(response.data),
    );
  }

  /// JSON bodies arrive as maps, but `bytes`/`stream` response types hand
  /// the error body over undecoded.
  Future<Object?> _decodeBody(Object? data) async {
    try {
      var raw = data;
      if (raw is ResponseBody) {
        raw = [await for (final chunk in raw.stream) ...chunk];
      }
      if (raw is List<int>) raw = utf8.decode(raw, allowMalformed: true);
      if (raw is String) return jsonDecode(raw);
      return raw;
    } catch (_) {
      return null;
    }
  }
}

/// Builds the typed exception for a gateway error response ([body] already
/// decoded; anything but the contract's `{"detail": ...}` shape is tolerated).
BackendException parseBackendError(int? status, Object? body) {
  final detail = body is Map ? body['detail'] : null;
  if (detail is Map) {
    final fields = detail.map((key, value) => MapEntry(key.toString(), value));
    final code = fields.remove('code') as String? ?? BackendErrorCode.http;
    final message = fields.remove('message') as String? ?? '';
    if (code == BackendErrorCode.quoteChanged) {
      return QuoteChangedException(
        statusCode: status,
        message: message,
        details: fields,
      );
    }
    return BackendException(
      statusCode: status,
      code: code,
      message: message,
      details: fields,
    );
  }
  // FastAPI validation failures arrive as a list of field errors.
  return BackendException(
    statusCode: status,
    code: detail is List && status == 422
        ? BackendErrorCode.invalidParameters
        : BackendErrorCode.http,
    message: detail is String ? detail : '',
  );
}
