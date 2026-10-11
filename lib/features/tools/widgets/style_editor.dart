import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_tokens.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/manager_list_tile.dart';
import '../../../core/widgets/manager_shell.dart';
import '../../../core/widgets/section_title.dart';
import '../../../core/widgets/ui/app_states.dart';
import '../../../core/widgets/ui/app_tabs.dart';
import 'shelf_toggle.dart';
import '../../../core/widgets/tag_suggestion_overlay.dart';
import '../../../core/services/styles.dart';
import '../../generation/providers/generation_notifier.dart';
import '../../characters/providers/character_library_notifier.dart';
import '../providers/style_notifier.dart';
import '../../../core/theme/vision_metrics.dart';

class StyleEditor extends StatelessWidget {
  final String? initialStyleName;
  const StyleEditor({super.key, this.initialStyleName});

  @override
  Widget build(BuildContext context) {
    final genNotifier = context.watch<GenerationNotifier>();
    final charLib = context.read<CharacterLibraryNotifier>();

    return ChangeNotifierProvider(
      create: (_) => StyleNotifier(
        tagService: genNotifier.tagService,
        wildcardService: genNotifier.wildcardService,
        initialStyles: genNotifier.state.styles,
        stylesFilePath: genNotifier.stylesFilePath,
        onStylesChanged: () => genNotifier.refreshStyles(),
        initialStyleName: initialStyleName,
        characterSuggestionsFor: (q) => charLib.suggestionTags(q),
      ),
      child: _StyleEditorContent(hasInitialStyle: initialStyleName != null),
    );
  }
}

class _StyleEditorContent extends StatefulWidget {
  final bool hasInitialStyle;
  const _StyleEditorContent({this.hasInitialStyle = false});

  @override
  State<_StyleEditorContent> createState() => _StyleEditorContentState();
}

class _StyleEditorContentState extends State<_StyleEditorContent> {
  bool _showingEditor = false;

  @override
  void initState() {
    super.initState();
    if (widget.hasInitialStyle) {
      _showingEditor = true;
    }
  }

  UnsavedChangesGuard _guard(StyleNotifier notifier) => UnsavedChangesGuard(
    hasChanges: notifier.state.isModified,
    onSave: () => _save(notifier),
    onDiscard: () => _discard(notifier),
  );

  /// Saves the edited style, asking first when its new name is taken.
  Future<bool> _save(StyleNotifier notifier) async {
    if (notifier.hasNameConflict() && !await _confirmOverwrite(notifier)) {
      return false;
    }
    await notifier.saveStyle();
    return true;
  }

  /// Drops pending edits by reloading the stored version, if there is one.
  void _discard(StyleNotifier notifier) {
    final state = notifier.state;
    notifier.selectStyle(
      state.styles.where((s) => s.name == state.originalName).firstOrNull,
    );
  }

  /// Opens the editor on [style], or on a fresh style when it is null, after
  /// pending edits on another style are saved or discarded.
  Future<void> _openEditor(StyleNotifier notifier, [PromptStyle? style]) async {
    final editing =
        notifier.state.selectedStyle != null &&
        style != null &&
        notifier.state.originalName == style.name;
    if (!editing) {
      if (!await _guard(notifier).resolve(context) || !mounted) return;
      style == null ? notifier.createNewStyle() : notifier.selectStyle(style);
    }
    setState(() => _showingEditor = true);
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<StyleNotifier>();
    final t = context.t;
    final l = context.l;
    final selected = notifier.state.selectedStyle;
    final modified = notifier.state.isModified;

    return ManagerMasterDetailShell(
      showDetail: _showingEditor && selected != null,
      masterHeader: ManagerHeader(
        title: l.styleEditor,
        subtitle: l.styleManageDesc,
        actions: [
          if (modified)
            ManagerSaveChangesButton(onPressed: () => _save(notifier)),
        ],
      ),
      detailTitle: selected?.name.toUpperCase() ?? '',
      detailActions: [
        if (modified)
          ManagerIconButton(
            key: const ValueKey<String>('style-mobile-save'),
            icon: Icons.save_outlined,
            tooltip: l.commonSave,
            color: t.textPrimary,
            onPressed: () => _save(notifier),
          ),
      ],
      onCloseDetail: () => setState(() => _showingEditor = false),
      guard: _guard(notifier),
      master: _buildStyleList(context, notifier, t),
      detail: _buildEditor(context, notifier, t),
    );
  }

  Widget _buildStyleList(
    BuildContext context,
    StyleNotifier notifier,
    VisionTokens t,
  ) {
    final l = context.l;
    final state = notifier.state;
    return ColoredBox(
      color: t.surfaceMid,
      child: Column(
        children: [
          ManagerListHeader(
            title: l.styleList,
            actions: [
              ManagerIconButton(
                icon: Icons.restore,
                tooltip: l.styleResetDefaults,
                color: t.secondaryText,
                onPressed: () async {
                  final confirmed = await showConfirmDialog(
                    context,
                    title: l.commonConfirm,
                    message: l.styleResetDefaults,
                    confirmLabel: l.commonConfirm,
                  );
                  if (confirmed == true) {
                    await notifier.resetToDefaults();
                  }
                },
              ),
              ManagerIconButton(
                icon: Icons.add,
                tooltip: l.styleNew,
                color: t.secondaryText,
                onPressed: () => _openEditor(notifier),
              ),
            ],
          ),
          Divider(height: 1, color: t.textMinimal),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: state.styles.length,
              onReorder: notifier.reorderStyles,
              proxyDecorator: (child, index, animation) {
                return Material(
                  color: t.surfaceHigh,
                  borderRadius: BorderRadius.circular(VisionMetrics.radius4),
                  elevation: 4,
                  child: child,
                );
              },
              itemBuilder: (context, index) {
                final style = state.styles[index];
                final isSelected = state.selectedStyle?.name == style.name;

                return ManagerListTile(
                  key: ValueKey(style.name),
                  title: style.name.toUpperCase(),
                  dragIndex: index,
                  selected: isSelected,
                  leading: Icon(
                    Icons.auto_awesome,
                    size: 12,
                    color: isSelected ? t.textPrimary : t.secondaryText,
                  ),
                  onTap: () => _openEditor(notifier, style),
                  menuActions: [
                    ManagerListAction(
                      label: l.commonDuplicate,
                      icon: Icons.copy,
                      onSelected: () => notifier.duplicateStyle(style),
                    ),
                    ManagerListAction(
                      label: l.commonDelete,
                      icon: Icons.delete_outline,
                      destructive: true,
                      onSelected: () =>
                          _showDeleteConfirm(context, notifier, style, t),
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
    StyleNotifier notifier,
    VisionTokens t,
  ) {
    final state = notifier.state;
    if (state.selectedStyle == null) {
      return EmptyState(message: context.l.styleSelectToEdit);
    }

    final bool isPrefix =
        state.selectedStyle!.prefix.isNotEmpty ||
        state.selectedStyle!.suffix.isEmpty;

    return Column(
      children: [
        if (state.tagSuggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              VisionMetrics.space24,
              VisionMetrics.space8,
              VisionMetrics.space24,
              0,
            ),
            child: TagSuggestionOverlay(
              suggestions: state.tagSuggestions,
              onTagSelected: notifier.applyTagSuggestion,
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(VisionMetrics.space24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle(context.l.styleIdentity, t),
                _buildTextField(
                  controller: notifier.nameController,
                  label: context.l.styleName,
                  onChanged: (val) => notifier.updateCurrentStyle(name: val),
                  t: t,
                ),
                const SizedBox(height: VisionMetrics.space12),
                ShelfToggle(
                  label: context.l.styleDefaultOnLaunch,
                  value: state.selectedStyle?.isDefault ?? false,
                  onChanged: (val) =>
                      notifier.updateCurrentStyle(isDefault: val),
                ),
                const SizedBox(height: VisionMetrics.space24),
                _buildSectionTitle(context.l.styleTargetPrompt, t),
                _buildTargetSelector(notifier, t),
                const SizedBox(height: VisionMetrics.space24),
                _buildSectionTitle(
                  state.isEditingNegative
                      ? context.l.styleNegativeContent
                      : context.l.stylePositiveContent,
                  t,
                ),
                Focus(
                  onFocusChange: (hasFocus) {
                    if (!hasFocus) {
                      Future.delayed(const Duration(milliseconds: 200), () {
                        notifier.clearTagSuggestions();
                      });
                    }
                  },
                  child: _buildTextField(
                    controller: notifier.contentController,
                    label: context.l.styleContent,
                    maxLines: 4,
                    onChanged: (val) {
                      notifier.handleTagSuggestions(
                        val,
                        notifier.contentController.selection,
                      );
                      notifier.updateCurrentStyle(content: val);
                    },
                    t: t,
                  ),
                ),
                if (!state.isEditingNegative) ...[
                  const SizedBox(height: VisionMetrics.space24),
                  _buildSectionTitle(context.l.stylePlacement, t),
                  _buildPlacementSelector(notifier, isPrefix, t),
                ],
                const SizedBox(height: VisionMetrics.space24),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, VisionTokens t) =>
      SectionTitle(title, t: t);

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
    required Function(String) onChanged,
    required VisionTokens t,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: t.textMinimal,
            fontSize: t.fontSize(8),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: VisionMetrics.space4),
        TextField(
          controller: controller,
          maxLines: maxLines,
          onChanged: onChanged,
          style: TextStyle(
            color: t.textSecondary,
            fontSize: t.fontSize(13),
            height: 1.5,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: t.borderSubtle,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(VisionMetrics.radius4),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.all(VisionMetrics.space12),
          ),
        ),
      ],
    );
  }

  Widget _buildTargetSelector(StyleNotifier notifier, VisionTokens t) {
    return AppSegmented<bool>(
      options: [
        AppOption(value: false, label: context.l.stylePositive),
        AppOption(value: true, label: context.l.styleNegative),
      ],
      selected: notifier.state.isEditingNegative,
      onChanged: notifier.setEditingNegative,
    );
  }

  Widget _buildPlacementSelector(
    StyleNotifier notifier,
    bool isPrefix,
    VisionTokens t,
  ) {
    return AppSegmented<bool>(
      options: [
        AppOption(value: true, label: context.l.styleBeginningPrefix),
        AppOption(value: false, label: context.l.styleEndSuffix),
      ],
      selected: isPrefix,
      onChanged: (prefix) => notifier.updateCurrentStyle(isPrefix: prefix),
    );
  }

  Future<void> _showDeleteConfirm(
    BuildContext context,
    StyleNotifier notifier,
    PromptStyle style,
    VisionTokens t,
  ) async {
    final l = context.l;
    final confirm = await showConfirmDialog(
      context,
      title: l.styleDeleteTitle,
      message: l.styleDeleteConfirm(style.name),
      confirmLabel: l.commonDelete,
      confirmColor: t.accentDanger,
    );
    if (confirm == true) {
      notifier.deleteStyle(style);
    }
  }

  Future<bool> _confirmOverwrite(StyleNotifier notifier) async {
    final l = context.l;
    final confirm = await showConfirmDialog(
      context,
      title: l.styleOverwriteTitle,
      message: l.styleOverwriteConfirm(notifier.nameController.text),
      confirmLabel: l.commonOverwrite,
      confirmColor: context.tRead.textPrimary,
    );
    return confirm == true;
  }
}
