import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/gateway/backend_gateway.dart';
import '../../../core/gateway/backend_permissions.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/services/preferences_service.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_metrics.dart';
import '../../../core/theme/vision_tokens.dart';
import '../../../core/widgets/ui/app_pill.dart';
import '../../auth/backend_auth_notifier.dart';
import '../../auth/widgets/backend_quota_badge.dart';
import '../../auth/widgets/backend_queue_badge.dart';
import '../providers/generation_notifier.dart';
import 'generation_page_layout.dart';

enum _MenuAction { help, gallery, history, logout }

/// The generation page's app bar.
///
/// Phone-width windows keep the balance, the queue and Tools in the bar and
/// fold help, gallery, history and the account into one overflow menu, so
/// the bar cannot overflow on a narrow screen.
class GenerationAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GenerationAppBar({
    super.key,
    required this.layout,
    required this.toolbarHeight,
    required this.onHelp,
    required this.onGallery,
    required this.onServerHistory,
    required this.onTools,
  });

  final GenerationLayoutSpec layout;
  final double toolbarHeight;
  final VoidCallback onHelp;
  final VoidCallback onGallery;
  final VoidCallback onServerHistory;
  final VoidCallback onTools;

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight);

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    final touch = layout.touch;
    final compact = layout.compact;
    final state = context.watch<GenerationNotifier>().state;
    final showLocalGallery = !(useBackendGateway && kIsWeb);
    final canOpenHistory =
        useBackendGateway &&
        hasBackendPermission(context, BackendPermission.historyRead);
    final username = useBackendGateway
        ? context.watch<BackendAuthNotifier>().user?.username
        : null;
    final iconSize = touch ? VisionMetrics.iconMedium : VisionMetrics.iconSmall;
    final labelStyle = TextStyle(
      color: t.headerText,
      fontSize: t.fontSize(touch ? 11 : 8),
      letterSpacing: 2,
      fontWeight: FontWeight.bold,
    );

    Widget barButton(String label, VoidCallback onPressed) => TextButton(
      onPressed: onPressed,
      child: Text(label.toUpperCase(), style: labelStyle),
    );

    return AppBar(
      title: Image.asset(
        'assets/logo.png',
        height: 28,
        filterQuality: FilterQuality.medium,
        color: t.logoColor,
        colorBlendMode: BlendMode.srcIn,
      ),
      centerTitle: false,
      backgroundColor: t.background,
      elevation: 0,
      toolbarHeight: toolbarHeight,
      actions: [
        if (context.read<PreferencesService>().showAnlasTracker)
          if (useBackendGateway && kIsWeb)
            const BackendQuotaBadge()
          else if (state.anlas != null)
            Padding(
              padding: const EdgeInsets.only(right: VisionMetrics.space4),
              child: AppPill(
                icon: Icons.toll,
                text: '${state.anlas}',
                tooltip: l.mainRefreshAnlas,
                onTap: () => context.read<GenerationNotifier>().fetchAnlas(),
              ),
            ),
        if (!compact) ...[
          IconButton(
            onPressed: onHelp,
            icon: Icon(
              Icons.help_outline,
              color: t.headerText,
              size: iconSize,
            ),
            tooltip: l.mainHelp,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: VisionMetrics.space8),
          if (showLocalGallery) barButton(l.mainGallery, onGallery),
          if (canOpenHistory) barButton(l.mainServerHistory, onServerHistory),
        ],
        barButton(l.mainTools, onTools),
        if (useBackendGateway) const BackendQueueBadge(),
        if (compact)
          PopupMenuButton<_MenuAction>(
            tooltip: l.mainMoreActions,
            icon: Icon(Icons.more_vert, color: t.headerText, size: iconSize),
            onSelected: (action) {
              switch (action) {
                case _MenuAction.help:
                  onHelp();
                case _MenuAction.gallery:
                  onGallery();
                case _MenuAction.history:
                  onServerHistory();
                case _MenuAction.logout:
                  context.read<BackendAuthNotifier>().logout();
              }
            },
            itemBuilder: (context) => [
              _item(t, _MenuAction.help, Icons.help_outline, l.mainHelp),
              if (showLocalGallery)
                _item(
                  t,
                  _MenuAction.gallery,
                  Icons.photo_library_outlined,
                  l.mainGallery,
                ),
              if (canOpenHistory)
                _item(
                  t,
                  _MenuAction.history,
                  Icons.history,
                  l.mainServerHistory,
                ),
              if (useBackendGateway) ...[
                if (username != null)
                  PopupMenuItem<_MenuAction>(
                    enabled: false,
                    child: Text(
                      username,
                      style: TextStyle(
                        color: t.textTertiary,
                        fontSize: t.fontSize(11),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                _item(t, _MenuAction.logout, Icons.logout, l.gatewayLogout),
              ],
            ],
          )
        else if (useBackendGateway)
          PopupMenuButton<_MenuAction>(
            tooltip: username ?? l.gatewayLogout,
            icon: Icon(
              Icons.account_circle_outlined,
              color: t.headerText,
              size: iconSize,
            ),
            onSelected: (_) => context.read<BackendAuthNotifier>().logout(),
            itemBuilder: (context) => [
              if (username != null)
                PopupMenuItem<_MenuAction>(
                  enabled: false,
                  child: Text(
                    username,
                    style: TextStyle(
                      color: t.textTertiary,
                      fontSize: t.fontSize(11),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              _item(t, _MenuAction.logout, Icons.logout, l.gatewayLogout),
            ],
          ),
      ],
    );
  }

  PopupMenuItem<_MenuAction> _item(
    VisionTokens t,
    _MenuAction value,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem<_MenuAction>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: VisionMetrics.iconSmall, color: t.textPrimary),
          const SizedBox(width: VisionMetrics.space8),
          Text(
            label,
            style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(11)),
          ),
        ],
      ),
    );
  }
}
