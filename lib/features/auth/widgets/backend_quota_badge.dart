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

    final showPaid =
        user.isAdmin || user.permissions.contains('image.generate.paid');
    final bucket = showPaid ? quota.paid : quota.free;
    final mobile = isMobile(context);
    final t = context.t;
    final shortLabel = showPaid
        ? context.l.gatewayQuotaPaidShort
        : context.l.gatewayQuotaFreeShort;
    final fullLabel = showPaid
        ? context.l.gatewayQuotaPaidLabel
        : context.l.gatewayQuotaFreeLabel;
    final remaining = _remainingText(context, bucket);
    final limit = _limitText(context, bucket);
    final tooltip =
        '$fullLabel: $remaining / $limit\n${context.l.gatewayQuotaRefresh}';

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
                Text(
                  '$shortLabel $remaining',
                  style: TextStyle(
                    color: t.headerText,
                    fontSize: t.fontSize(mobile ? 10 : 8),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
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
    return '${bucket.pointLimit ?? bucket.dailyLimit ?? 0}';
  }
}
