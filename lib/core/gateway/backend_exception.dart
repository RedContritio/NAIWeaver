/// Error codes of the gateway contract (docs/GATEWAY_CONTRACT.md §1) plus the
/// few the client assigns itself when no gateway JSON error is available.
abstract final class BackendErrorCode {
  static const notAuthenticated = 'not_authenticated';
  static const authUnavailable = 'auth_unavailable';
  static const loginFailed = 'login_failed';
  static const accountNotLinked = 'account_not_linked';
  static const permissionDenied = 'permission_denied';
  static const invalidParameters = 'invalid_parameters';
  static const pointsInsufficient = 'points_insufficient';
  static const quoteChanged = 'quote_changed';
  static const freeAllowanceExhausted = 'free_allowance_exhausted';
  static const queueFull = 'queue_full';
  static const duplicateRequest = 'duplicate_request';
  static const requestTooLarge = 'request_too_large';
  static const upstreamError = 'upstream_error';
  static const interrupted = 'interrupted';
  static const notFound = 'not_found';
  static const taskActive = 'task_active';
  static const duplicateGeneration = 'duplicate_generation';
  static const duplicateWithinBatch = 'duplicate_within_batch';
  static const rateLimited = 'rate_limited';
  static const methodNotAllowed = 'method_not_allowed';
  static const serviceUnavailable = 'service_unavailable';
  static const internalError = 'internal_error';

  // Assigned by the client, never sent by the gateway.
  static const network = 'network_error';
  static const timeout = 'timeout';
  static const invalidResponse = 'invalid_response';
  static const http = 'http_error';
}

/// Every failed gateway call, whatever the transport reported. [statusCode]
/// is null when no HTTP response arrived; [details] holds the extra fields of
/// the contract's `detail` object (`point_kind`, `quote`, `limit`, ...).
class BackendException implements Exception {
  const BackendException({
    required this.statusCode,
    required this.code,
    this.message = '',
    this.details = const <String, dynamic>{},
  });

  final int? statusCode;
  final String code;
  final String message;
  final Map<String, dynamic> details;

  bool get isNetworkError =>
      code == BackendErrorCode.network || code == BackendErrorCode.timeout;

  bool get isNotAuthenticated => code == BackendErrorCode.notAuthenticated;

  String? get pointKind => details['point_kind'] as String?;

  String? get existingTaskId => details['task_id'] as String?;

  @override
  String toString() => 'BackendException($statusCode, $code)';
}

/// 409 `quote_changed`: the price the client showed differs from the
/// server's. [quote] is the server quote (`mode`, `points`, ...).
class QuoteChangedException extends BackendException {
  const QuoteChangedException({
    required super.statusCode,
    super.message,
    super.details,
  }) : super(code: BackendErrorCode.quoteChanged);

  Map<String, dynamic> get quote {
    final raw = details['quote'];
    return raw is Map<String, dynamic> ? raw : const <String, dynamic>{};
  }

  String? get mode => quote['mode'] as String?;

  int? get points => (quote['points'] as num?)?.toInt();
}
