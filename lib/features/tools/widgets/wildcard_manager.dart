import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_tokens.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/manager_list_tile.dart';
import '../../../core/widgets/manager_shell.dart';
import '../../../core/widgets/ui/app_states.dart';
import '../../../core/widgets/tag_suggestion_overlay.dart';
import '../../../core/widgets/text_input_dialog.dart';
import '../../../core/services/wildcard_processor.dart';
import '../providers/wildcard_notifier.dart';
import '../../../core/theme/vision_metrics.dart';

class WildcardManager extends StatefulWidget {
  const WildcardManager({super.key});

  @override
  State<WildcardManager> createState() => _WildcardManagerState();
}

class _WildcardManagerState extends State<WildcardManager> {
  bool _showingEditor = false;

  Future<void> _openEditor(WildcardNotifier notifier, File file) async {
    await notifier.selectFile(file);
    if (mounted) setState(() => _showingEditor = true);
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<WildcardNotifier>();
    final t = context.t;
    final l = context.l;
    final selected = notifier.state.selectedFile;
    final helpButton = ManagerIconButton(
      icon: Icons.help_outline,
      tooltip: l.wildcardHelp,
      onPressed: () => _showWildcardHelp(t),
    );

    // Edits are written to disk as the user types (debounced), so there are
    // never unsaved changes to guard; leaving the editor just flushes them.
    return ManagerMasterDetailShell(
      showDetail: _showingEditor && selected != null,
      masterHeader: ManagerHeader(
        title: l.wildcardManager,
        subtitle: l.wildcardManageDesc,
        actions: [helpButton],
      ),
      detailTitle: selected == null
          ? ''
          : p.basenameWithoutExtension(selected.path).toUpperCase(),
      detailActions: [helpButton],
      onCloseDetail: () {
        notifier.flushPendingSave();
        setState(() => _showingEditor = false);
      },
      master: _buildFileList(context, notifier, t),
      detail: _buildEditor(context, notifier, t),
    );
  }

  Widget _buildFileList(
    BuildContext context,
    WildcardNotifier notifier,
    VisionTokens t,
  ) {
    final l = context.l;
    final state = notifier.state;
    return ColoredBox(
      color: t.surfaceMid,
      child: Column(
        children: [
          ManagerListHeader(
            title: l.wildcardFiles,
            actions: [
              ManagerIconButton(
                icon: Icons.add,
                tooltip: l.wildcardNew,
                color: t.secondaryText,
                onPressed: () => _showCreateDialog(context, notifier),
              ),
            ],
          ),
          Divider(height: 1, color: t.textMinimal),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: state.files.length,
              onReorder: notifier.reorderFiles,
              proxyDecorator: (child, index, animation) {
                return Material(
                  color: t.surfaceHigh,
                  borderRadius: BorderRadius.circular(VisionMetrics.radius4),
                  elevation: 4,
                  child: child,
                );
              },
              itemBuilder: (context, index) {
                final file = state.files[index];
                final isSelected = state.selectedFile?.path == file.path;
                final fileName = p.basenameWithoutExtension(file.path);
                final isFav = notifier.isFavorite(file);

                return ManagerListTile(
                  key: ValueKey(file.path),
                  title: fileName.toUpperCase(),
                  dragIndex: index,
                  selected: isSelected,
                  leading: Icon(
                    isFav ? Icons.star : Icons.description_outlined,
                    size: 12,
                    color: isFav
                        ? t.accentFavorite
                        : (isSelected ? t.textPrimary : t.secondaryText),
                  ),
                  onTap: () => _openEditor(notifier, file),
                  menuActions: [
                    ManagerListAction(
                      label: l.commonRename,
                      icon: Icons.drive_file_rename_outline,
                      onSelected: () =>
                          _showRenameDialog(context, notifier, file, fileName),
                    ),
                    ManagerListAction(
                      label: isFav
                          ? l.commonRemoveFavorite
                          : l.commonAddFavorite,
                      icon: isFav ? Icons.star : Icons.star_border,
                      onSelected: () => notifier.toggleFavorite(file),
                    ),
                    ManagerListAction(
                      label: l.commonDelete,
                      icon: Icons.delete_outline,
                      destructive: true,
                      onSelected: () => _showDeleteConfirm(
                        context,
                        notifier,
                        file,
                        fileName,
                        t,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor(
    BuildContext context,
    WildcardNotifier notifier,
    VisionTokens t,
  ) {
    final state = notifier.state;
    if (state.selectedFile == null) {
      return EmptyState(message: context.l.wildcardSelectOrCreate);
    }

    final hasResults = state.invalidTags.isNotEmpty || state.validCount > 0;
    final totalChecked = state.validCount + state.invalidTags.length;
    final currentMode = notifier.getFileMode(state.selectedFile!);
    final l = context.l;

    return Column(
      children: [
        TagSuggestionOverlay(
          suggestions: state.tagSuggestions,
          onTagSelected: notifier.applyTagSuggestion,
        ),
        // Validation toolbar
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: VisionMetrics.space12,
            vertical: VisionMetrics.space8,
          ),
          color: t.surfaceMid,
          child: Row(
            children: [
              ManagerIconButton(
                icon: Icons.verified_outlined,
                color: t.textSecondary,
                onPressed: notifier.validateCurrentFile,
                tooltip: context.l.wildcardValidateTags,
              ),
              if (hasResults) ...[
                const SizedBox(width: VisionMetrics.space8),
                Text(
                  context.l.wildcardRecognized(state.validCount, totalChecked),
                  style: TextStyle(
                    color: state.invalidTags.isEmpty
                        ? t.accentSuccess
                        : t.accentFavorite,
                    fontSize: t.fontSize(9),
                    letterSpacing: 1,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
              const Spacer(),
              if (hasResults)
                ManagerIconButton(
                  icon: Icons.close,
                  onPressed: notifier.clearValidation,
                  tooltip: context.l.wildcardClear,
                ),
              const SizedBox(width: VisionMetrics.space4),
              Text(
                l.wildcardMode,
                style: TextStyle(
                  color: t.textDisabled,
                  fontSize: t.fontSize(8),
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: VisionMetrics.space4),
              SizedBox(
                height: context.hitSize,
                child: DropdownButton<WildcardMode>(
                  value: currentMode,
                  dropdownColor: t.surfaceHigh,
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: t.fontSize(9),
                    letterSpacing: 1,
                  ),
                  items: WildcardMode.values.map((mode) {
                    return DropdownMenuItem(
                      value: mode,
                      child: Text(_modeLabel(mode, l)),
                    );
                  }).toList(),
                  onChanged: (mode) {
                    if (mode != null) {
                      notifier.setFileMode(state.selectedFile!, mode);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TextField(
            textAlignVertical: TextAlignVertical.top,
            onTapOutside: (_) {
              Future.delayed(const Duration(milliseconds: 200), () {
                notifier.clearTagSuggestions();
              });
            },
            controller: notifier.editorController,
            maxLines: null,
            expands: true,
            onChanged: (val) {
              notifier.handleTagSuggestions(
                val,
                notifier.editorController.selection,
              );
              // Debounced: coalesces disk writes so editing a wildcard with
              // hundreds of entries doesn't lag on every keystroke.
              notifier.saveCurrentFileDebounced();
            },
            style: TextStyle(
              color: t.textSecondary,
              fontSize: t.fontSize(13),
              fontFamily: 'monospace',
              height: 1.5,
            ),
            decoration: InputDecoration(
              hintText: context.l.wildcardStartTyping,
              hintStyle: TextStyle(
                color: t.textMinimal,
                fontSize: t.fontSize(9),
                letterSpacing: 2,
              ),
              contentPadding: const EdgeInsets.all(VisionMetrics.space24),
              border: InputBorder.none,
              fillColor: Colors.transparent,
              filled: true,
            ),
          ),
        ),
        // Invalid tags list
        if (state.invalidTags.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 120),
            width: double.infinity,
            color: t.surfaceMid,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Divider(height: 1, color: t.textMinimal),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: VisionMetrics.space12,
                    vertical: VisionMetrics.space8,
                  ),
                  child: Text(
                    context.l.wildcardUnrecognized(state.invalidTags.length),
                    style: TextStyle(
                      color: t.accentFavorite,
                      fontSize: t.fontSize(8),
                      letterSpacing: 1,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(
                      left: VisionMetrics.space12,
                      right: VisionMetrics.space12,
                      bottom: VisionMetrics.space8,
                    ),
                    itemCount: state.invalidTags.length,
                    itemExtent: 20,
                    itemBuilder: (context, index) {
                      return Text(
                        state.invalidTags[index],
                        style: TextStyle(
                          color: t.accentCharacter,
                          fontSize: t.fontSize(10),
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _modeLabel(WildcardMode mode, AppLocalizations l) {
    switch (mode) {
      case WildcardMode.random:
        return l.wildcardModeRandom;
      case WildcardMode.sequential:
        return l.wildcardModeSequential;
      case WildcardMode.shuffle:
        return l.wildcardModeShuffle;
      case WildcardMode.weighted:
        return l.wildcardModeWeighted;
    }
  }

  void _showWildcardHelp(VisionTokens t) {
    final l = context.l;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: t.surfaceHigh,
          title: Text(
            l.wildcardHelpTitle,
            style: TextStyle(
              fontSize: t.fontSize(11),
              letterSpacing: 2,
              color: t.textSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _helpRow(t, '__name__', l.wildcardHelpRandom),
                const SizedBox(height: VisionMetrics.space12),
                _helpRow(t, '__summer.clothes__', l.wildcardHelpDotSyntax),
                const SizedBox(height: VisionMetrics.space12),
                _helpRow(t, '__', l.wildcardHelpBrowse),
                const SizedBox(height: VisionMetrics.space16),
                Text(
                  l.wildcardHelpNesting,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: t.fontSize(10),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: VisionMetrics.space4),
                Text(
                  l.wildcardHelpNestingDesc,
                  style: TextStyle(
                    color: t.hintText,
                    fontSize: t.fontSize(9),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: VisionMetrics.space16),
                Text(
                  l.wildcardMode,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: t.fontSize(10),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: VisionMetrics.space4),
                _modeHelpRow(t, l.wildcardModeRandom, l.wildcardModeRandomDesc),
                const SizedBox(height: 2),
                _modeHelpRow(
                  t,
                  l.wildcardModeSequential,
                  l.wildcardModeSequentialDesc,
                ),
                const SizedBox(height: 2),
                _modeHelpRow(
                  t,
                  l.wildcardModeShuffle,
                  l.wildcardModeShuffleDesc,
                ),
                const SizedBox(height: 2),
                _modeHelpRow(
                  t,
                  l.wildcardModeWeighted,
                  l.wildcardModeWeightedDesc,
                ),
                const SizedBox(height: VisionMetrics.space16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.star,
                      size: VisionMetrics.iconSmall,
                      color: t.accentFavorite,
                    ),
                    const SizedBox(width: VisionMetrics.space8),
                    Expanded(
                      child: Text(
                        l.wildcardHelpFavorites,
                        style: TextStyle(
                          color: t.hintText,
                          fontSize: t.fontSize(9),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: VisionMetrics.space8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: VisionMetrics.iconSmall,
                      color: t.accentFavorite,
                    ),
                    const SizedBox(width: VisionMetrics.space8),
                    Expanded(
                      child: Text(
                        l.wildcardHelpTip,
                        style: TextStyle(
                          color: t.hintText,
                          fontSize: t.fontSize(9),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                l.commonClose,
                style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(9)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _helpRow(VisionTokens t, String code, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: VisionMetrics.space8,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: t.borderSubtle,
            borderRadius: BorderRadius.circular(VisionMetrics.radius4),
          ),
          child: Text(
            code,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: t.fontSize(10),
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: VisionMetrics.space8),
        Expanded(
          child: Text(
            description,
            style: TextStyle(
              color: t.hintText,
              fontSize: t.fontSize(9),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _modeHelpRow(VisionTokens t, String label, String description) {
    return Padding(
      padding: const EdgeInsets.only(left: VisionMetrics.space4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                color: t.textSecondary,
                fontSize: t.fontSize(9),
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(width: VisionMetrics.space8),
          Expanded(
            child: Text(
              description,
              style: TextStyle(
                color: t.hintText,
                fontSize: t.fontSize(9),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteConfirm(
    BuildContext context,
    WildcardNotifier notifier,
    File file,
    String fileName,
    VisionTokens t,
  ) async {
    final l = context.l;
    final confirm = await showConfirmDialog(
      context,
      title: l.wildcardDeleteTitle,
      message: l.wildcardDeleteConfirm(fileName),
      confirmLabel: l.commonDelete,
      confirmColor: t.accentDanger,
    );
    if (confirm == true) {
      notifier.deleteFile(file);
    }
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    WildcardNotifier notifier,
    File file,
    String currentName,
  ) async {
    final l = context.l;
    final name = await showTextInputDialog(
      context,
      title: l.wildcardRenameTitle,
      confirmLabel: l.commonRename,
      hintText: l.wildcardFileName,
      initialValue: currentName,
    );
    if (name == null || name == currentName) return;
    final success = await notifier.renameFile(file, name);
    if (!success && context.mounted) {
      showErrorSnackBar(context, l.wildcardRenameExists);
    }
  }

  Future<void> _showCreateDialog(
    BuildContext context,
    WildcardNotifier notifier,
  ) async {
    final l = context.l;
    final name = await showTextInputDialog(
      context,
      title: l.wildcardCreateTitle,
      confirmLabel: l.commonCreate,
      hintText: l.wildcardFileName,
    );
    if (name != null) await notifier.createFile(name.replaceAll(' ', '.'));
  }
}
