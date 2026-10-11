import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/gateway/backend_permissions.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/utils/responsive.dart';
import '../../director_ref/widgets/reference_add_actions.dart';
import '../../vibe_transfer/providers/vibe_transfer_notifier.dart';
import '../../vibe_transfer/widgets/vibe_transfer_chip.dart';
import '../../vibe_transfer/widgets/vibe_transfer_editor_sheet.dart';
import 'billing_text.dart';

class VibeTransferShelf extends StatelessWidget {
  const VibeTransferShelf({super.key});

  void _openEditor(
    BuildContext context,
    VibeTransferNotifier notifier,
    vibeTransfer,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VibeTransferEditorSheet(
        vibe: vibeTransfer,
        onStrengthChanged: (v) => notifier.updateStrength(vibeTransfer.id, v),
        onInfoExtractedChanged: (v) =>
            notifier.updateInfoExtracted(vibeTransfer.id, v),
        onToggleEnabled: () => notifier.toggleEnabled(vibeTransfer.id),
        onRemove: () => notifier.removeVibe(vibeTransfer.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VibeTransferNotifier>(
      builder: (context, notifier, _) {
        final vibes = notifier.vibes;
        final mobile = isMobile(context);
        // Encoding a new vibe is a paid tool; existing ones can still be
        // opened and removed.
        final canEncode = hasBackendPermission(
          context,
          BackendPermission.imageEncodeVibe,
        );

        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: Container(
            height: mobile ? 52 : 44,
            margin: const EdgeInsets.only(top: 2, bottom: 2),
            child: ListView(
              scrollDirection: Axis.horizontal,
              shrinkWrap: true,
              children: [
                ...vibes.map(
                  (vibe) => VibeTransferChip(
                    vibe: vibe,
                    onTap: () => _openEditor(context, notifier, vibe),
                    onLongPress: () => notifier.removeVibe(vibe.id),
                    pausedReason: notifier.isPaused(vibe)
                        ? pausedReasonText(context.l, notifier.access)
                        : null,
                  ),
                ),
                _AddVibeButton(
                  isProcessing: notifier.isProcessing,
                  disabledReason: canEncode
                      ? null
                      : context.l.refVibeNoPermission,
                  onTap: () => pickAndAddVibes(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AddVibeButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isProcessing;

  /// Why a new vibe cannot be encoded; null when it can.
  final String? disabledReason;

  const _AddVibeButton({
    required this.onTap,
    this.isProcessing = false,
    this.disabledReason,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final mobile = isMobile(context);
    final reason = disabledReason;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: reason ?? paidToolCapLabel(context, PaidTool.encodeVibe) ?? '',
        child: GestureDetector(
          onTap: isProcessing || reason != null ? null : onTap,
          child: Opacity(
            opacity: reason == null ? 1 : 0.4,
            child: Container(
              height: mobile ? 44 : 36,
              width: mobile ? 52 : 42,
              decoration: BoxDecoration(
                color: t.accentVibeTransfer.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.center,
              child: Text(
                'VIBE',
                style: TextStyle(
                  fontSize: t.fontSize(mobile ? 9 : 7),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  color: t.accentVibeTransfer,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
