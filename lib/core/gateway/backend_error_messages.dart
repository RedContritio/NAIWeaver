import 'package:dio/dio.dart';

import '../../l10n/app_localizations.dart';
import 'backend_exception.dart';

/// The user-facing text for any failed call. Gateway errors are mapped by
/// their contract `code` (docs/GATEWAY_CONTRACT.md §1); raw exception text is
/// never shown.
String backendErrorMessage(AppLocalizations l, Object error) {
  if (error is! BackendException) return l.gatewayErrUnknown;
  switch (error.code) {
    case BackendErrorCode.notAuthenticated:
      return l.gatewayErrNotAuthenticated;
    case BackendErrorCode.authUnavailable:
      return l.gatewayErrAuthUnavailable;
    case BackendErrorCode.loginFailed:
      return l.gatewayErrLoginFailed;
    case BackendErrorCode.accountNotLinked:
      return l.gatewayErrAccountNotLinked;
    case BackendErrorCode.permissionDenied:
      return l.gatewayErrPermissionDenied;
    case BackendErrorCode.invalidParameters:
      return l.gatewayErrInvalidParameters;
    case BackendErrorCode.pointsInsufficient:
      return l.gatewayErrPointsInsufficient;
    case BackendErrorCode.quoteChanged:
      return l.gatewayErrQuoteChanged;
    case BackendErrorCode.freeAllowanceExhausted:
      return l.gatewayErrFreeAllowanceExhausted;
    case BackendErrorCode.queueFull:
      return l.gatewayErrQueueFull;
    case BackendErrorCode.duplicateRequest:
      return l.gatewayErrDuplicateRequest;
    case BackendErrorCode.requestTooLarge:
      return l.gatewayErrRequestTooLarge;
    case BackendErrorCode.upstreamError:
      return l.gatewayErrUpstream;
    case BackendErrorCode.interrupted:
      return l.gatewayErrInterrupted;
    case BackendErrorCode.notFound:
      return l.gatewayErrNotFound;
    case BackendErrorCode.taskActive:
      return l.gatewayErrTaskActive;
    case BackendErrorCode.duplicateGeneration:
    case BackendErrorCode.duplicateWithinBatch:
      return l.gatewayErrDuplicateGeneration;
    case BackendErrorCode.rateLimited:
      return l.gatewayErrRateLimited;
    case BackendErrorCode.serviceUnavailable:
      return l.gatewayErrServiceUnavailable;
    case BackendErrorCode.internalError:
      return l.gatewayErrInternal;
    case BackendErrorCode.network:
      return l.gatewayErrNetwork;
    case BackendErrorCode.timeout:
      return l.gatewayErrTimeout;
  }
  // No contract code (a proxy or load balancer answered): go by status.
  final status = error.statusCode;
  if (status == 401) return l.gatewayErrNotAuthenticated;
  if (status == 403) return l.gatewayErrPermissionDenied;
  if (status == 404) return l.gatewayErrNotFound;
  if (status == 429) return l.gatewayErrRateLimited;
  if (status != null && status >= 500) return l.gatewayErrServiceUnavailable;
  return l.gatewayErrUnknown;
}

/// Why a generation item failed, or null while it has not. Items carry a
/// contract `error_code` (docs/GATEWAY_CONTRACT.md §7), never to be replaced
/// by the server's raw `error_message`.
String? taskItemFailureMessage(
  AppLocalizations l,
  String status,
  String? errorCode,
) {
  if (status != 'failed' && status != 'rejected' && status != 'cancelled') {
    return null;
  }
  if (errorCode == null) return l.gatewayErrUnknown;
  return backendErrorMessage(
    l,
    BackendException(statusCode: null, code: errorCode),
  );
}

/// Text for a failure of a direct NovelAI call (native builds with a personal
/// API key). NovelAI's statuses differ from the gateway's: 402 means the
/// account lacks Anlas and 429 is NovelAI's own rate limit.
String directApiErrorMessage(AppLocalizations l, Object error) {
  if (error is! DioException) return l.gatewayErrUnknown;
  switch (error.response?.statusCode) {
    case 400:
    case 422:
      return l.gatewayErrInvalidParameters;
    case 402:
      return l.gatewayErrDirectAnlas;
    case 403:
      return l.gatewayErrDirectForbidden;
    case 429:
      return l.gatewayErrDirectRateLimited;
    case final int status when status >= 500:
      return l.gatewayErrServiceUnavailable;
    case null:
      return switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout => l.gatewayErrTimeout,
        DioExceptionType.connectionError => l.gatewayErrNetwork,
        _ => l.gatewayErrUnknown,
      };
  }
  return l.gatewayErrUnknown;
}
