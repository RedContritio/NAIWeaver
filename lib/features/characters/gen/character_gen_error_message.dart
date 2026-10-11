import '../../../core/services/text_gen_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../text_gen/text_gen_error_message.dart';
import 'character_gen_service.dart';

/// The localized text for a failed character generation. [error] is
/// `CharacterGenNotifier.lastError`; the exception's English message is never
/// shown.
String characterGenErrorMessage(AppLocalizations l, Object error) {
  if (error is TextGenException && error.cause == CharacterGenIssue.unusableJson) {
    return l.charsGenErrUnusable;
  }
  return textGenErrorMessage(l, error);
}
