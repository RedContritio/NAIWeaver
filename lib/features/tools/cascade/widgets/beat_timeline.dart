import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../providers/cascade_notifier.dart';
import '../../../../core/theme/vision_metrics.dart';

class BeatTimeline extends StatelessWidget {
  const BeatTimeline({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;

    return Consumer<CascadeNotifier>(
      builder: (context, notifier, child) {
        final state = notifier.state;
        if (state.activeCascade == null) return const SizedBox.shrink();

        final beats = state.activeCascade!.beats;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: VisionMetrics.space16,
                vertical: VisionMetrics.space8,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l.cascadeBeatTimeline,
                    style: TextStyle(
                      color: t.textDisabled,
                      fontSize: t.fontSize(9),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  Text(
                    l.cascadeBeatsCount(beats.length),
                    style: TextStyle(
                      color: t.textMinimal,
                      fontSize: t.fontSize(8),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 100,
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: VisionMetrics.space12,
                ),
                itemCount: beats.length + 1,
                proxyDecorator: (child, index, animation) {
                  return Material(color: Colors.transparent, child: child);
                },
                onReorder: (oldIndex, newIndex) {
                  if (oldIndex < beats.length && newIndex <= beats.length) {
                    notifier.reorderBeats(oldIndex, newIndex);
                  }
                },
                itemBuilder: (context, index) {
                  if (index == beats.length) {
                    return _buildAddButton(
                      context,
                      notifier,
                      key: const ValueKey('add_beat'),
                    );
                  }

                  final isSelected = state.selectedBeatIndex == index;
                  return _buildBeatCard(
                    context,
                    index,
                    isSelected,
                    notifier,
                    key: ValueKey('beat_$index'),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBeatCard(
    BuildContext context,
    int index,
    bool isSelected,
    CascadeNotifier notifier, {
    required Key key,
  }) {
    final t = context.t;
    final l = context.l;
    return Container(
      key: key,
      width: 120,
      margin: const EdgeInsets.symmetric(
        horizontal: VisionMetrics.space4,
        vertical: VisionMetrics.space8,
      ),
      child: Stack(
        children: [
          InkWell(
            onTap: () => notifier.selectBeat(index),
            borderRadius: BorderRadius.circular(VisionMetrics.radius8),
            child: Container(
              decoration: BoxDecoration(
                color: isSelected ? t.borderMedium : t.borderSubtle,
                borderRadius: BorderRadius.circular(VisionMetrics.radius8),
                border: Border.all(
                  color: isSelected ? t.textTertiary : t.borderSubtle,
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    l.cascadeBeatN(index + 1),
                    style: TextStyle(
                      color: isSelected ? t.textPrimary : t.textDisabled,
                      fontSize: t.fontSize(10),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: VisionMetrics.space4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildQuickAction(
                        context: context,
                        icon: Icons.copy,
                        onPressed: () {
                          notifier.cloneBeat(index);
                          showAppSnackBar(context, l.cascadeCloneBeat);
                        },
                        tooltip: l.cascadeCloneBeat,
                      ),
                      _buildQuickAction(
                        context: context,
                        icon: Icons.delete_outline,
                        onPressed: () async {
                          final confirmed = await showConfirmDialog(
                            context,
                            title: l.cascadeRemoveBeat,
                            message: l.cascadeRemoveBeatMessage,
                            confirmLabel: l.cascadeRemoveBeat,
                            cancelLabel: l.commonCancel,
                          );
                          if (confirmed == true) notifier.removeBeat(index);
                        },
                        color: t.accentDanger.withValues(
                          alpha: VisionMetrics.opacityScrim,
                        ),
                        tooltip: l.cascadeRemoveBeat,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isSelected)
            Positioned(
              bottom: 0,
              left: 20,
              right: 20,
              child: Container(height: 2, color: t.textPrimary),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickAction({
    required BuildContext context,
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
    required String tooltip,
  }) {
    final t = context.t;
    return IconButton(
      icon: Icon(icon, size: 14, color: color ?? t.textDisabled),
      onPressed: onPressed,
      tooltip: tooltip,
      constraints: const BoxConstraints(),
      padding: const EdgeInsets.all(VisionMetrics.space4),
    );
  }

  Widget _buildAddButton(
    BuildContext context,
    CascadeNotifier notifier, {
    required Key key,
  }) {
    final t = context.t;
    return Container(
      key: key,
      width: 60,
      margin: const EdgeInsets.symmetric(
        horizontal: VisionMetrics.space4,
        vertical: VisionMetrics.space8,
      ),
      child: OutlinedButton(
        onPressed: () => notifier.addBeat(),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: t.borderSubtle),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(VisionMetrics.radius8),
          ),
          padding: EdgeInsets.zero,
        ),
        child: Icon(Icons.add, color: t.textDisabled),
      ),
    );
  }
}
