import 'package:flutter/widgets.dart';

import '../../../core/gateway/image_quote.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../models/generation_quote.dart';

/// Asks whether to go on at the price the server decided, for every image
/// call that can meet a price change (generation, img2img, cascade, enhance).
/// A [context] that is gone counts as no.
Future<bool> confirmQuoteChange(
  BuildContext context,
  QuoteConfirmation confirmation,
) async {
  if (!context.mounted) return false;
  final l = context.l;
  final price = confirmation.serverMode == QuoteMode.paid
      ? l.quoteConfirmPriceRed(confirmation.serverPoints)
      : l.quoteConfirmPriceGreen(confirmation.serverPoints);
  final reason = confirmation.allowanceExhausted
      ? l.quoteConfirmReasonAllowance
      : l.quoteConfirmReasonOther;
  final confirmed = await showConfirmDialog(
    context,
    title: l.quoteConfirmTitle,
    message:
        '$price\n${l.quoteConfirmShown(confirmation.shown.points)}\n$reason',
    confirmLabel: l.quoteConfirmContinue,
    cancelLabel: l.commonCancel,
    confirmColor: context.tRead.accent,
  );
  return confirmed == true;
}
