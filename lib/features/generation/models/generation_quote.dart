import '../../../core/gateway/image_quote.dart';

/// The price of the request that would be sent now, and whether this account
/// may send it.
class GenerationQuote {
  const GenerationQuote({
    required this.quote,
    required this.invalidField,
    required this.freeOnly,
  });

  /// Null when the gateway would reject the parameters ([invalidField]).
  final ImageQuote? quote;
  final String? invalidField;

  /// The account can only generate for free.
  final bool freeOnly;

  /// A free-only account cannot send what would cost red points.
  bool get blocked => freeOnly && (quote == null || quote!.isPaid);

  /// Only the free allowance is missing: no parameter change helps.
  bool get freeAllowanceExhausted =>
      quote != null &&
      quote!.reasons.length == 1 &&
      quote!.reasons.single == QuoteReason.allowanceExhausted;

  /// The user can fix the parameters so the request is free again.
  bool get canAdjustToFree => blocked && !freeAllowanceExhausted;

  /// Whether the request may be submitted.
  bool get canSubmit => quote != null && !blocked;
}

/// What the user is asked to confirm when the gateway prices a request
/// differently from what was shown.
class QuoteConfirmation {
  const QuoteConfirmation({
    required this.shown,
    required this.serverMode,
    required this.serverPoints,
    required this.reasons,
  });

  /// The local quote that was shown and sent.
  final ImageQuote shown;
  final String serverMode;
  final int serverPoints;

  /// Why the server charges what it does (`reasons` of its quote).
  final List<String> reasons;

  bool get allowanceExhausted =>
      reasons.contains(QuoteReason.allowanceExhausted);
}

/// Asks the user whether to go on at the server's price.
typedef QuoteConfirmer = Future<bool> Function(QuoteConfirmation confirmation);
