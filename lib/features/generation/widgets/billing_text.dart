import '../../../core/gateway/backend_permissions.dart';
import '../../../core/gateway/image_quote.dart';
import '../../../l10n/app_localizations.dart';
import '../services/reference_access_monitor.dart';

/// Why a request is paid, in the user's language.
String quoteReasonText(AppLocalizations l, String reason) => switch (reason) {
  QuoteReason.sizeNotFree => l.quoteReasonSizeNotFree,
  QuoteReason.stepsOverFreeLimit => l.quoteReasonStepsOverFreeLimit,
  QuoteReason.smea => l.quoteReasonSmea,
  QuoteReason.imageInput => l.quoteReasonImageInput,
  QuoteReason.directorRefs => l.quoteReasonDirectorRefs,
  QuoteReason.vibes => l.quoteReasonVibes,
  QuoteReason.allowanceExhausted => l.quoteReasonAllowanceExhausted,
  QuoteReason.paidTool => l.quoteReasonPaidTool,
  _ => reason,
};

/// Why references and vibes are not sent while [access] is missing.
String pausedReasonText(AppLocalizations l, PaidImageAccess access) =>
    access == PaidImageAccess.noRedPoints
    ? l.refPausedNoRedPoints
    : l.refPausedNoPermission;

/// The one-time message for a change of the account's paid-input access.
String referenceAccessNoticeText(
  AppLocalizations l,
  ReferenceAccessNotice notice,
) {
  final items = [
    if (notice.references > 0) l.refAccessCountRefs(notice.references),
    if (notice.vibes > 0) l.refAccessCountVibes(notice.vibes),
  ].join(l.refAccessSeparator);
  if (notice.resumed) return l.refAccessResumed(items);
  return notice.access == PaidImageAccess.noRedPoints
      ? l.refAccessPausedNoRedPoints(items)
      : l.refAccessPausedNoPermission(items);
}
