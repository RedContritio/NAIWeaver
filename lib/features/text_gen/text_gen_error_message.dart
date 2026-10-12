import 'package:dio/dio.dart';

import '../../core/gateway/backend_error_messages.dart';
import '../../core/services/text_gen_service.dart';
import '../../l10n/app_localizations.dart';

/// The localized text for a failed text generation. [error] is
/// `TextGenNotifier.lastError`; the exception's English message is never
/// shown. Gateway failures go through [backendErrorMessage], direct NovelAI
/// failures through [directApiErrorMessage].
String textGenErrorMessage(AppLocalizations l, Object error) {
  if (error is! TextGenException) return l.gatewayErrUnknown;
  final cause = error.cause;
  if (cause is TextGenIssue) {
    return switch (cause) {
      TextGenIssue.noToken => l.textGenErrNoToken,
      TextGenIssue.emptyInput => l.textGenErrEmptyInput,
    };
  }
  if (cause is DioException) {
    if (cause.response?.statusCode == 401) return l.toolErrApiKeyRejected;
    return directApiErrorMessage(l, cause);
  }
  if (cause != null) return backendErrorMessage(l, cause);
  return l.gatewayErrUnknown;
}
