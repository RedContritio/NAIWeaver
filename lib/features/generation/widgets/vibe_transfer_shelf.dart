import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/gateway/backend_permissions.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_metrics.dart';
import '../../../core/widgets/ui/app_sheet.dart';
import '../../director_ref/widgets/reference_add_actions.dart';
import '../../vibe_transfer/providers/vibe_transfer_notifier.dart';
import '../../vibe_transfer/widgets/vibe_transfer_chip.dart';
import '../../vibe_transfer/widgets/vibe_transfer_editor_sheet.dart';
import 'billing_text.dart';
import 'chip_actions.dart';

class VibeTransferShelf extends StatelessWidget {
  const VibeTransferShelf({super.key});

  void _openEditor(
    BuildContext context,
    VibeTransferNotifier notifier,
    vibeTransfer,
  ) {
    showAppSheet(
      context: context,
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
        // Encoding a new vibe is a paid tool; existing ones can still be
        // opened and removed.
        final canEncode = hasBackendPermission(
          context,
          BackendPermission.imageEncodeVibe,
        );

        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: Container(
            height: context.hitSize + VisionMetrics.space8,
            margin: const EdgeInsets.symmetric(vertical: VisionMetrics.radius2),
            child: ListView(
              scrollDirection: Axis.horizontal,
              shrinkWrap: true,
              children: [
                ...vibes.map(
                  (vibe) => VibeTransferChip(
                    vibe: vibe,
                    onTap: () => _openEditor(context, notifier, vibe),
                    onLongPress: () => showChipActions(
                      context,
                      title: context.l.refVibeLabel,
                      onDelete: () => notifier.removeVibe(vibe.id),
                      deleteMessage: context.l.refVibeRemoveConfirm,
                    ),
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
    final reason = disabledReason;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VisionMetrics.space4),
      child: Tooltip(
        message: reason ?? paidToolCapLabel(context, PaidTool.encodeVibe) ?? '',
        child: GestureDetector(
          onTap: isProcessing || reason != null ? null : onTap,
          child: Opacity(
            opacity: reason == null ? 1 : VisionMetrics.opacityDisabled,
            child: Container(
              constraints: BoxConstraints(
                minHeight: context.hitSize,
                minWidth: context.hitSize + VisionMetrics.space8,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: VisionMetrics.space8,
              ),
              decoration: BoxDecoration(
                color: t.accentVibeTransfer.withValues(
                  alpha: VisionMetrics.opacityPressed,
                ),
                borderRadius: BorderRadius.circular(VisionMetrics.radius4),
              ),
              alignment: Alignment.center,
              child: Text(
                context.l.refVibeLabel,
                style: TextStyle(
                  fontSize: t.fontSize(9),
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
