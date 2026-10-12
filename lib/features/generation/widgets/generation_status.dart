import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/gateway/backend_gateway.dart';
import '../../../core/gateway/backend_permissions.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/services/nai_cost_estimator.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_metrics.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/ui/app_pill.dart';
import '../../../core/widgets/ui/app_tone.dart';
import '../../director_ref/providers/director_ref_notifier.dart';
import '../../vibe_transfer/providers/vibe_transfer_notifier.dart';
import '../models/generation_quote.dart';
import '../providers/generation_notifier.dart';
import 'billing_text.dart';

/// What the next image costs and what it carries, for every layout: the
/// price of the request that would be sent, then the references and vibes in
/// it. Gateway prices come from the rules; a direct NovelAI account sees its
/// Anlas estimate.
class GenerationStatus extends StatelessWidget {
  const GenerationStatus({
    super.key,
    required this.compact,
    required this.onOpenInputs,
  });

  final bool compact;
  final VoidCallback onOpenInputs;

  /// Height of the whole block, so the action rail can reserve it.
  static double heightOf({required bool compact, required bool touch}) =>
      _badgeHeight(compact: compact, touch: touch) +
      VisionMetrics.radius2 +
      _indicatorHeight;

  static double _badgeHeight({required bool compact, required bool touch}) =>
      compact ? 22 : (touch ? 26 : 23);

  static const double _indicatorHeight = 14;

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<GenerationNotifier>();
    final touch = windowSizeClassOf(context).isTouchSized;
    final Widget badge;
    if (useBackendGateway) {
      final quote = notifier.quote;
      badge = quote == null
          ? const SizedBox.shrink()
          : QuoteBadge(
              quote: quote,
              discount: notifier.imageRules?.greenPointDiscount ?? 0,
              onAdjust: notifier.adjustToFreeParameters,
            );
    } else {
      badge = AnlasBadge(notifier: notifier);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _badgeHeight(compact: compact, touch: touch),
          width: double.infinity,
          child: badge,
        ),
        const SizedBox(height: VisionMetrics.radius2),
        SizedBox(
          height: _indicatorHeight,
          width: double.infinity,
          child: ActiveInputsIndicator(onTap: onOpenInputs),
        ),
      ],
    );
  }
}

/// The local price: a green or red point, the points, and in the tooltip the
/// reasons it is red. A free-only account whose request would be red gets the
/// way back to free parameters here, as an explicit tap.
class QuoteBadge extends StatelessWidget {
  const QuoteBadge({
    super.key,
    required this.quote,
    required this.discount,
    required this.onAdjust,
  });

  final GenerationQuote quote;
  final int discount;
  final VoidCallback onAdjust;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final price = quote.quote;
    final adjustable = quote.canAdjustToFree;
    final red = price == null || price.isPaid;
    final label = adjustable
        ? l.quoteAdjustToFree
        : price == null
        ? l.quoteInvalidBadge
        : '${price.points}';
    final details = <String>[
      if (price == null)
        l.quoteInvalidTooltip(quote.invalidField ?? '')
      else
        price.isPaid
            ? l.quotePointsTooltipPaid(price.points)
            : l.quotePointsTooltipFree(price.points),
      if (price != null) ...[
        for (final reason in price.reasons) '• ${quoteReasonText(l, reason)}',
        '${l.mainEstimatedCostBase}: ${price.base}',
        if (price.directorRefs > 0)
          '${l.mainEstimatedCostReference}: ${price.directorRefs}',
        if (price.extraVibes > 0)
          '${l.mainEstimatedCostVibe}: ${price.extraVibes}',
        if (price.images > 1)
          '${l.mainEstimatedCostSerialImages}: ${price.images}',
        if (!price.isPaid && discount > 0) l.quoteDiscountNote(discount),
      ],
      if (adjustable) l.quoteAdjustToFreeTooltip,
      if (quote.blocked && quote.freeAllowanceExhausted)
        l.quoteFreeAllowanceUnavailable,
    ];

    return _PriceChip(
      icon: Icons.toll,
      label: label,
      tone: red ? AppTone.error : AppTone.success,
      tooltip: details.join('\n'),
      onTap: adjustable ? onAdjust : null,
    );
  }
}

/// A direct NovelAI account is charged Anlas by NovelAI; this is the
/// estimate from the request that would be sent.
class AnlasBadge extends StatelessWidget {
  const AnlasBadge({super.key, required this.notifier});

  final GenerationNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final parameters =
        notifier.previewRequest().body['parameters'] as Map<String, dynamic>;
    int count(String key) => (parameters[key] as List?)?.length ?? 0;
    final estimate = estimateNaiImageCost(
      width: parameters['width'] as int,
      height: parameters['height'] as int,
      steps: parameters['steps'] as int,
      smea: parameters['sm'] == true,
      smeaDyn: parameters['sm_dyn'] == true,
      serialImages: notifier.state.batchCount,
      directorReferenceCount: count('director_reference_images'),
      vibeReferenceCount: count('reference_image_multiple'),
      isOpus: false,
    );
    final details = <String>[
      l.mainEstimatedCostTooltip,
      '${l.mainEstimatedCostBase}: ${estimate.baseAnlas} ${l.mainAnlas}',
      if (estimate.hasReferenceCost)
        '${l.mainEstimatedCostReference}: ${estimate.directorReferenceAnlas} ${l.mainAnlas}',
      if (estimate.hasVibeCost)
        '${l.mainEstimatedCostVibe}: ${estimate.vibeReferenceAnlas} ${l.mainAnlas}',
      if (estimate.serialImages > 1)
        '${l.mainEstimatedCostSerialImages}: ${estimate.serialImages}',
    ];
    return _PriceChip(
      icon: Icons.toll,
      label: '${l.mainEstimatedCostLabel} ${estimate.totalAnlas}',
      tone: AppTone.info,
      tooltip: details.join('\n'),
    );
  }
}

/// An [AppPill] filling the badge slot, tappable when [onTap] is set.
class _PriceChip extends StatelessWidget {
  const _PriceChip({
    required this.icon,
    required this.label,
    required this.tone,
    required this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final AppTone tone;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget chip = Align(
      child: AppPill(icon: icon, text: label, tone: tone),
    );
    if (onTap != null) {
      chip = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VisionMetrics.radius4),
        child: chip,
      );
    }
    return Tooltip(message: tooltip, child: chip);
  }
}

/// `REF n · VIBE m`: the references and vibes the next image carries, with
/// the ones held back for lack of access counted apart. Tapping opens where
/// they are managed. It does not depend on the shelf visibility settings.
class ActiveInputsIndicator extends StatelessWidget {
  const ActiveInputsIndicator({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    final directors = context.watch<DirectorRefNotifier>();
    final vibes = context.watch<VibeTransferNotifier>();
    final paused = directors.pausedCount + vibes.pausedCount;
    final style = TextStyle(
      color: t.textTertiary,
      fontSize: t.fontSize(8),
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
    );
    return Tooltip(
      message: l.generationInputsTooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VisionMetrics.radius4),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.generationInputsActive(directors.sentCount, vibes.sentCount),
                maxLines: 1,
                style: style,
              ),
              if (paused > 0) ...[
                Text(' · ', style: style),
                Icon(
                  Icons.pause_circle_outline,
                  size: 10,
                  color: t.accentDanger,
                ),
                const SizedBox(width: VisionMetrics.radius2),
                Text(
                  l.generationInputsPaused(paused),
                  maxLines: 1,
                  style: style.copyWith(color: t.accentDanger),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The generate button of every layout. It stays off while a generation
/// runs, when the account cannot generate, or when the request would cost
/// what the account cannot pay.
class GenerateButton extends StatelessWidget {
  const GenerateButton({
    super.key,
    required this.compact,
    required this.onPressed,
  });

  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final notifier = context.watch<GenerationNotifier>();
    final loading = notifier.state.isLoading;
    final allowed =
        canGenerateImage(context) && (notifier.quote?.canSubmit ?? true);
    return ElevatedButton(
      onPressed: loading || !allowed ? null : onPressed,
      style: ElevatedButton.styleFrom(
        padding: EdgeInsets.zero,
        backgroundColor: t.accent,
        foregroundColor: t.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VisionMetrics.radius4),
        ),
        elevation: 0,
      ),
      child: loading
          ? SizedBox(
              width: compact ? 17 : 20,
              height: compact ? 17 : 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: t.background,
              ),
            )
          : Icon(Icons.arrow_forward_ios, size: compact ? 14 : 16),
    );
  }
}
