import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../providers/cascade_notifier.dart';
import '../models/prompt_cascade.dart';
import '../../../../core/theme/vision_metrics.dart';

class CascadeLibraryView extends StatelessWidget {
  const CascadeLibraryView({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;

    return Consumer<CascadeNotifier>(
      builder: (context, notifier, child) {
        final state = notifier.state;

        if (state.isLoading) {
          return Center(
            child: CircularProgressIndicator(color: t.textDisabled),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.all(isTouchSized(context) ? 16.0 : 24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.cascadeLibrary,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: t.fontSize(isTouchSized(context) ? 14 : 18),
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                      Text(
                        l.cascadeSequencesSaved(state.savedCascades.length),
                        style: TextStyle(
                          color: t.textDisabled,
                          fontSize: t.fontSize(9),
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  if (isTouchSized(context))
                    IconButton(
                      tooltip: context.l.cascadeNew,
                      onPressed: () => _showCreateDialog(context, notifier),
                      icon: Icon(Icons.add, color: t.background, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: t.accent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            VisionMetrics.radius4,
                          ),
                        ),
                      ),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: () => _showCreateDialog(context, notifier),
                      icon: const Icon(Icons.add, size: 16),
                      label: Text(l.cascadeNew),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: t.accent,
                        foregroundColor: t.background,
                        textStyle: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: t.fontSize(10),
                          letterSpacing: 1,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            VisionMetrics.radius4,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: state.savedCascades.isEmpty
                  ? _buildEmptyState(context)
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: VisionMetrics.space24,
                      ),
                      itemCount: state.savedCascades.length,
                      itemBuilder: (context, index) {
                        final cascade = state.savedCascades[index];
                        return _buildCascadeCard(context, cascade, notifier);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final t = context.t;
    final l = context.l;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.movie_filter, size: 48, color: t.borderSubtle),
          const SizedBox(height: VisionMetrics.space16),
          Text(
            l.cascadeNoCascades,
            style: TextStyle(
              color: t.textMinimal,
              fontSize: t.fontSize(10),
              letterSpacing: 2,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCascadeCard(
    BuildContext context,
    PromptCascade cascade,
    CascadeNotifier notifier,
  ) {
    final t = context.t;
    final l = context.l;
    return Container(
      margin: const EdgeInsets.only(bottom: VisionMetrics.space12),
      decoration: BoxDecoration(
        color: t.borderSubtle,
        borderRadius: BorderRadius.circular(VisionMetrics.radius8),
        border: Border.all(color: t.borderSubtle),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: VisionMetrics.space16,
          vertical: VisionMetrics.space8,
        ),
        onTap: () => notifier.setActiveCascade(cascade),
        title: Text(
          cascade.name.toUpperCase(),
          style: TextStyle(
            color: t.textPrimary,
            fontSize: t.fontSize(12),
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: VisionMetrics.space4),
          child: Text(
            l.cascadeBeatsAndSlots(
              cascade.beats.length,
              cascade.characterCount,
            ),
            style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(9)),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.delete_outline, color: t.textDisabled, size: 18),
              tooltip: context.l.commonDelete,
              onPressed: () => _confirmDelete(context, cascade, notifier),
            ),
            Icon(Icons.chevron_right, color: t.textDisabled),
          ],
        ),
      ),
    );
  }

  void _showCreateDialog(BuildContext context, CascadeNotifier notifier) {
    final nameController = TextEditingController();
    int charCount = 2;
    bool autoPosition = false;

    showDialog(
      context: context,
      builder: (context) {
        final t = context.t;
        final l = context.l;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            backgroundColor: t.surfaceHigh,
            title: Text(
              l.cascadeCreateNew,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: t.fontSize(12),
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameController,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: t.fontSize(13),
                  ),
                  decoration: InputDecoration(
                    hintText: l.cascadeName,
                    hintStyle: TextStyle(
                      color: t.textMinimal,
                      fontSize: t.fontSize(10),
                    ),
                    filled: true,
                    fillColor: t.borderSubtle,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        VisionMetrics.radius4,
                      ),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: VisionMetrics.space24),
                Text(
                  l.cascadeCharSlotsLabel,
                  style: TextStyle(
                    color: t.textDisabled,
                    fontSize: t.fontSize(9),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: VisionMetrics.space8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (int i = 0; i <= 5; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                          child: InkWell(
                            onTap: () => setState(() => charCount = i),
                            child: Container(
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: charCount == i
                                    ? t.accent
                                    : t.borderSubtle,
                                borderRadius: BorderRadius.circular(
                                  VisionMetrics.radius4,
                                ),
                              ),
                              child: Text(
                                '$i',
                                style: TextStyle(
                                  color: charCount == i
                                      ? t.background
                                      : t.textPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (charCount > 0) ...[
                  const SizedBox(height: VisionMetrics.space16),
                  InkWell(
                    onTap: () => setState(() => autoPosition = !autoPosition),
                    child: Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: autoPosition
                                ? t.accentFavorite
                                : t.borderSubtle,
                            borderRadius: BorderRadius.circular(
                              VisionMetrics.radius4,
                            ),
                            border: Border.all(
                              color: autoPosition
                                  ? t.accentFavorite
                                  : t.textMinimal,
                            ),
                          ),
                          child: autoPosition
                              ? Icon(Icons.check, size: 14, color: t.background)
                              : null,
                        ),
                        const SizedBox(width: VisionMetrics.space12),
                        Text(
                          l.cascadeAutoPosition,
                          style: TextStyle(
                            color: autoPosition
                                ? t.accentFavorite
                                : t.textDisabled,
                            fontSize: t.fontSize(9),
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  l.commonCancel,
                  style: TextStyle(
                    color: t.textDisabled,
                    fontSize: t.fontSize(10),
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  if (nameController.text.isNotEmpty) {
                    notifier.createNewCascade(
                      nameController.text,
                      charCount,
                      useCoords: !autoPosition,
                    );
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.accent,
                  foregroundColor: t.background,
                ),
                child: Text(
                  l.commonCreate,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: t.fontSize(10),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    PromptCascade cascade,
    CascadeNotifier notifier,
  ) async {
    final t = context.t;
    final l = context.l;
    final confirm = await showConfirmDialog(
      context,
      title: l.cascadeDeleteTitle,
      message: l.cascadeDeleteConfirm(cascade.name),
      confirmLabel: l.commonDelete,
      confirmColor: t.accentDanger,
    );
    if (confirm == true) {
      notifier.deleteCascade(cascade.name);
    }
  }
}
