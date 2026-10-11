import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/vision_metrics.dart';
import '../../../core/widgets/ui/app_pill.dart';
import '../../../core/widgets/ui/app_tone.dart';
import '../../../core/services/backend_auth_api.dart';
import '../backend_auth_notifier.dart';

class BackendQuotaBadge extends StatelessWidget {
  const BackendQuotaBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<BackendAuthNotifier>();
    final user = auth.user;
    final quota = auth.quota;
    if (user == null || quota == null) return const SizedBox.shrink();

    // A fully discounted bucket has no useful balance to display. In
    // particular, administrators should see their finite red-point balance,
    // not a misleading green infinity symbol.
    final showGreen =
        !quota.free.unlimited &&
        (quota.free.enabled ||
            quota.free.pointLimit != null ||
            quota.free.greenPointLimit != null);
    final showRed = quota.paid.enabled && !quota.paid.unlimited;
    if (!showGreen && !showRed) return const SizedBox.shrink();
    final green = _remainingText(context, quota.free);
    final red = _remainingText(context, quota.paid);
    final tooltip = [
      if (showGreen)
        '${context.l.gatewayQuotaFreeLabel}: $green / ${_limitText(context, quota.free)}',
      if (showRed)
        '${context.l.gatewayQuotaPaidLabel}: $red / ${_limitText(context, quota.paid)}',
      context.l.gatewayQuotaRefresh,
    ].join('\n');

    return Padding(
      padding: const EdgeInsets.only(right: VisionMetrics.space4),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: () => context.read<BackendAuthNotifier>().refreshSession(),
          borderRadius: BorderRadius.circular(VisionMetrics.radius4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: VisionMetrics.minHitTarget,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showGreen)
                  AppPill(
                    icon: Icons.account_balance_wallet_outlined,
                    text: green,
                    tone: AppTone.success,
                  ),
                if (showGreen && showRed)
                  const SizedBox(width: VisionMetrics.space4),
                if (showRed)
                  AppPill(
                    icon: showGreen
                        ? null
                        : Icons.account_balance_wallet_outlined,
                    text: red,
                    tone: AppTone.error,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _remainingText(BuildContext context, BackendQuotaBucket bucket) {
    if (bucket.unlimited) return context.l.gatewayQuotaUnlimited;
    return '${bucket.remaining ?? 0}';
  }

  String _limitText(BuildContext context, BackendQuotaBucket bucket) {
    if (bucket.unlimited) return context.l.gatewayQuotaUnlimited;
    return '${bucket.pointLimit ?? bucket.greenPointLimit ?? bucket.redPoints ?? 0}';
  }
}
