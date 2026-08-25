import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/utils/responsive.dart';
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
    final mobile = isMobile(context);
    final t = context.t;
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
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: () => context.read<BackendAuthNotifier>().refreshSession(),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: mobile ? 10 : 8,
              vertical: mobile ? 4 : 2,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.borderMedium),
              color: t.borderSubtle,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: mobile ? 14 : 11,
                  color: t.headerText,
                ),
                const SizedBox(width: 4),
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: t.fontSize(mobile ? 10 : 8),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                    children: [
                      if (showGreen)
                        TextSpan(
                          text: green,
                          style: TextStyle(color: t.accentSuccess),
                        ),
                      if (showGreen && showRed)
                        TextSpan(
                          text: '/',
                          style: TextStyle(color: t.secondaryText),
                        ),
                      if (showRed)
                        TextSpan(
                          text: red,
                          style: TextStyle(color: t.accentDanger),
                        ),
                    ],
                  ),
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
