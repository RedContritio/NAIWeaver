import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_metrics.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/section_title.dart';
import '../../../core/widgets/text_input_dialog.dart';
import '../../../core/widgets/ui/app_panel.dart';
import '../../../core/widgets/ui/app_sheet.dart';
import '../../../core/widgets/ui/app_tabs.dart';
import '../../../core/widgets/syntax_highlight_controller.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/resizable_lines.dart';
import '../../../core/widgets/line_resize_handle.dart';
import '../../../core/widgets/tag_suggestion_overlay.dart';
import '../../../core/widgets/touch_scroll_wrap.dart';
import '../../../core/services/tag_service.dart';
import '../../../core/services/preferences_service.dart';
import '../models/nai_character.dart';
import '../models/character_preset.dart';
import '../providers/generation_notifier.dart';
import '../../characters/providers/character_library_notifier.dart';
import 'nai_grid_selector.dart';
import 'action_interaction_sheet.dart';
import 'chip_actions.dart';

class _CharEditorState {
  final List<NaiCharacter> characters;
  final List<NaiInteraction> interactions;
  final bool autoPositioning;
  final String characterEditorMode;
  final List<CharacterPreset> characterPresets;

  const _CharEditorState({
    required this.characters,
    required this.interactions,
    required this.autoPositioning,
    required this.characterEditorMode,
    required this.characterPresets,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _CharEditorState &&
          listEquals(characters, other.characters) &&
          listEquals(interactions, other.interactions) &&
          autoPositioning == other.autoPositioning &&
          characterEditorMode == other.characterEditorMode &&
          listEquals(characterPresets, other.characterPresets);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(characters),
    Object.hashAll(interactions),
    autoPositioning,
    characterEditorMode,
    Object.hashAll(characterPresets),
  );
}

class InlineCharacterEditor extends StatelessWidget {
  const InlineCharacterEditor({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<GenerationNotifier, _CharEditorState>(
      selector: (_, n) => _CharEditorState(
        characters: n.state.characters,
        interactions: n.state.interactions,
        autoPositioning: n.state.autoPositioning,
        characterEditorMode: n.state.characterEditorMode,
        characterPresets: n.state.characterPresets,
      ),
      shouldRebuild: (prev, next) => prev != next,
      builder: (context, editorState, _) {
        final notifier = context.read<GenerationNotifier>();
        final t = context.t;
        final l = context.l;
        final mobile = windowSizeClassOf(context).isTouchSized;

        final mode = editorState.characterEditorMode;
        final isExpanded = mode == 'expanded';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: label, then the mode switch and the auto chip
            SectionTitle(l.charEditorTitle.toUpperCase(), t: t),
            Wrap(
              spacing: VisionMetrics.space8,
              runSpacing: VisionMetrics.space8,
              children: [
                AppSegmented<bool>(
                  options: [
                    AppOption(value: true, label: l.charEditorExpanded),
                    AppOption(value: false, label: l.charEditorCompact),
                  ],
                  selected: isExpanded,
                  onChanged: (expanded) => notifier.setCharacterEditorMode(
                    expanded ? 'expanded' : 'compact',
                  ),
                ),
                if (isExpanded && editorState.characters.isNotEmpty)
                  _ToggleChip(
                    label: l.charEditorAutoPosition,
                    isSelected: editorState.autoPositioning,
                    onTap: () => notifier.setAutoPositioning(
                      !editorState.autoPositioning,
                    ),
                  ),
              ],
            ),

            if (!isExpanded) ...[
              const SizedBox(height: VisionMetrics.space8),
              Text(
                l.charEditorUsingCompactShelf.toUpperCase(),
                style: TextStyle(
                  fontSize: t.fontSize(mobile ? 9 : 8),
                  color: t.textMinimal,
                  letterSpacing: 1,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],

            if (isExpanded) ...[
              const SizedBox(height: VisionMetrics.space12),
              // Character cards
              for (int i = 0; i < editorState.characters.length; i++) ...[
                _CharacterCard(
                  key: ValueKey('char_$i'),
                  index: i,
                  character: editorState.characters[i],
                  autoPositioning: editorState.autoPositioning,
                  characterPresets: editorState.characterPresets,
                ),
                if (i < editorState.characters.length - 1)
                  const SizedBox(height: VisionMetrics.space8),
              ],

              // Add character button
              if (editorState.characters.length < 6) ...[
                const SizedBox(height: VisionMetrics.space8),
                _AddButton(
                  onTap: () => notifier.addCharacter(),
                  label: l.charEditorAddCharacter,
                ),
              ],

              // Interactions section
              if (editorState.characters.length >= 2) ...[
                const SizedBox(height: VisionMetrics.space16),
                Divider(color: t.borderSubtle, height: 1),
                const SizedBox(height: VisionMetrics.space12),
                _InteractionsSection(
                  characters: editorState.characters,
                  interactions: editorState.interactions,
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

// ─── Toggle Chip ─────────────────────────────────────────────────────────────

/// An on/off chip. Built on the segmented control so it wraps and keeps the
/// shared touch size instead of carrying its own padding.
class _ToggleChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppSegmented<bool>(
      options: [AppOption(value: true, label: label)],
      selected: isSelected,
      onChanged: (_) => onTap(),
    );
  }
}

// ─── Add Button ──────────────────────────────────────────────────────────────

class _AddButton extends StatelessWidget {
  final VoidCallback onTap;
  final String label;

  const _AddButton({required this.onTap, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final radius = BorderRadius.circular(VisionMetrics.radius4);
    return Material(
      color: t.accent.withValues(alpha: VisionMetrics.opacityPressed),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: t.accent.withValues(alpha: VisionMetrics.opacityScrim),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: context.hitSize,
            minWidth: double.infinity,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: VisionMetrics.iconSmall, color: t.accent),
              const SizedBox(width: VisionMetrics.space8),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: t.fontSize(9),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    color: t.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Character Card ──────────────────────────────────────────────────────────

class _CharacterCard extends StatefulWidget {
  final int index;
  final NaiCharacter character;
  final bool autoPositioning;
  final List<CharacterPreset> characterPresets;

  const _CharacterCard({
    super.key,
    required this.index,
    required this.character,
    required this.autoPositioning,
    required this.characterPresets,
  });

  @override
  State<_CharacterCard> createState() => _CharacterCardState();
}

class _CharacterCardState extends State<_CharacterCard> {
  late TextEditingController _nameController;
  late SyntaxHighlightController _promptController;
  late SyntaxHighlightController _ucController;

  List<DanbooruTag> _promptSuggestions = [];
  List<DanbooruTag> _ucSuggestions = [];

  Timer? _debounce;
  bool _syncing = false;
  bool _isCollapsed = false;
  bool _showTitle = false;
  bool _showUc = false;
  bool _showPosition = false;
  bool _showPresets = false;
  int _promptLines = kCharPromptDefaultLines;

  TagService? _tagService;
  CharacterLibraryNotifier? _characterLibrary;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.character.name);
    _promptController = SyntaxHighlightController(
      text: widget.character.prompt,
    );
    _ucController = SyntaxHighlightController(text: widget.character.uc);

    _nameController.addListener(_onTextChanged);
    _promptController.addListener(_onPromptChanged);
    _ucController.addListener(_onUcChanged);

    // Restore persisted toggle states
    final prefs = Provider.of<PreferencesService>(context, listen: false);
    _showTitle = prefs.uiCharShowTitle;
    _showUc = prefs.uiCharShowUc;
    _showPosition = prefs.uiCharShowPosition;
    _showPresets = prefs.uiCharShowPresets;
    _promptLines = prefs.uiCharPromptLines;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tagService ??= context.read<GenerationNotifier>().tagService;
    _characterLibrary ??= context.read<CharacterLibraryNotifier>();
  }

  @override
  void didUpdateWidget(covariant _CharacterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFromExternal(oldWidget);
  }

  void _syncFromExternal(_CharacterCard oldWidget) {
    // Only sync if the data changed from an external source (preset apply, session restore)
    // and not from our own controller edits
    if (_syncing) return;

    final oldChar = oldWidget.character;
    final newChar = widget.character;

    bool changed = false;
    if (oldChar.name != newChar.name && _nameController.text != newChar.name) {
      changed = true;
    }
    if (oldChar.prompt != newChar.prompt &&
        _promptController.text != newChar.prompt) {
      changed = true;
    }
    if (oldChar.uc != newChar.uc && _ucController.text != newChar.uc) {
      changed = true;
    }

    if (changed) {
      _syncing = true;
      if (_nameController.text != newChar.name) {
        _nameController.text = newChar.name;
      }
      if (_promptController.text != newChar.prompt) {
        _promptController.text = newChar.prompt;
      }
      if (_ucController.text != newChar.uc) _ucController.text = newChar.uc;
      _syncing = false;
    }
  }

  void _onTextChanged() {
    if (_syncing) return;
    _scheduleSave();
  }

  void _onPromptChanged() {
    if (_syncing) return;
    _scheduleSave();
    _updatePromptSuggestions();
  }

  void _onUcChanged() {
    if (_syncing) return;
    _scheduleSave();
    _updateUcSuggestions();
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _syncing = true;
      final notifier = context.read<GenerationNotifier>();
      notifier.updateCharacter(
        widget.index,
        widget.character.copyWith(
          name: _nameController.text,
          prompt: _promptController.text,
          uc: _ucController.text,
        ),
      );
      _syncing = false;
    });
  }

  void _updatePromptSuggestions() {
    if (!mounted || _tagService == null) return;
    final text = _promptController.text;
    if (text.isEmpty) {
      if (_promptSuggestions.isNotEmpty) {
        setState(() => _promptSuggestions = []);
      }
      return;
    }
    final parts = text.split(',');
    final lastPart = parts.last.trim();
    final minLength = TagService.containsNonAscii(lastPart) ? 1 : 2;
    if (lastPart.length < minLength) {
      if (_promptSuggestions.isNotEmpty) {
        setState(() => _promptSuggestions = []);
      }
      return;
    }
    final charMatches = _characterLibrary?.suggestionTags(lastPart) ?? const [];
    final suggestions = [
      ...charMatches,
      ..._tagService!.getSuggestions(lastPart),
    ];
    setState(() => _promptSuggestions = suggestions);
  }

  void _updateUcSuggestions() {
    if (!mounted || _tagService == null) return;
    final text = _ucController.text;
    if (text.isEmpty) {
      if (_ucSuggestions.isNotEmpty) setState(() => _ucSuggestions = []);
      return;
    }
    final parts = text.split(',');
    final lastPart = parts.last.trim();
    final minLength = TagService.containsNonAscii(lastPart) ? 1 : 2;
    if (lastPart.length < minLength) {
      if (_ucSuggestions.isNotEmpty) setState(() => _ucSuggestions = []);
      return;
    }
    final suggestions = _tagService!.getSuggestions(lastPart);
    setState(() => _ucSuggestions = suggestions);
  }

  void _onTagSelected(
    TextEditingController controller,
    DanbooruTag tag, {
    TextEditingController? negativeTarget,
  }) {
    final insertText = tag.typeName == 'saved_character'
        ? ((tag.expansion != null && tag.expansion!.trim().isNotEmpty)
              ? tag.expansion!.trim()
              : tag.tag)
        : (tag.matchedAlias ?? tag.tag);
    // Drop the half-typed word the suggestion completes, then append through
    // the shared character-insertion entry so negatives follow the same rules
    // everywhere.
    final parts = controller.text.split(',')..removeLast();
    final isSavedCharacter = tag.typeName == 'saved_character';
    controller.text = parts.join(',');
    // A saved character inserted into this character's PROMPT routes its
    // negative tags to this character's own UC field, not the global negative.
    final routeNegatives =
        isSavedCharacter &&
        negativeTarget != null &&
        (tag.negativeExpansion ?? '').trim().isNotEmpty;
    context.read<GenerationNotifier>().insertCharacterTags(
      insertText,
      routeNegatives ? tag.negativeExpansion : null,
      promptTarget: controller,
      negativeTarget: routeNegatives ? negativeTarget : null,
    );
    // Reveal the UC field so the injected negatives are visible.
    if (routeNegatives && !_showUc) {
      setState(() => _showUc = true);
      context.read<PreferencesService>().setUiCharShowUc(true);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final notifier = context.read<GenerationNotifier>();
    final t = context.tRead;
    final l = context.l;
    final name = widget.character.name.isNotEmpty
        ? widget.character.name
        : l.charEditorCharacterN(widget.index + 1);

    final confirm = await showConfirmDialog(
      context,
      title: l.charEditorDeleteCharacter,
      message: l.charEditorDeleteConfirm(name),
      confirmLabel: l.commonDelete,
      confirmColor: t.accentDanger,
    );
    if (confirm == true) {
      notifier.removeCharacter(widget.index);
    }
  }

  Future<void> _saveAsPreset(BuildContext context) async {
    final notifier = context.read<GenerationNotifier>();
    final l = context.l;
    final name = await showTextInputDialog(
      context,
      title: l.charEditorSavePreset,
      confirmLabel: l.commonSave,
      hintText: l.charEditorPresetName.toUpperCase(),
      initialValue: widget.character.name,
    );
    if (name == null) return;
    notifier.saveCharacterPreset(
      CharacterPreset(
        id: 'cp_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        prompt: _promptController.text,
        uc: _ucController.text,
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameController.removeListener(_onTextChanged);
    _promptController.removeListener(_onPromptChanged);
    _ucController.removeListener(_onUcChanged);
    _nameController.dispose();
    _promptController.dispose();
    _ucController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final highlight = SyntaxHighlightColors.fromTokens(t);
    _promptController.colors = highlight;
    _ucController.colors = highlight;
    final l = context.l;
    final mobile = windowSizeClassOf(context).isTouchSized;

    final displayName = widget.character.name.isNotEmpty
        ? widget.character.name.toUpperCase()
        : l.charEditorCharacterN(widget.index + 1).toUpperCase();

    return AppPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header
          InkWell(
            onTap: () => setState(() => _isCollapsed = !_isCollapsed),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: VisionMetrics.space12,
                vertical: VisionMetrics.space8,
              ),
              child: Row(
                children: [
                  Icon(
                    _isCollapsed ? Icons.expand_more : Icons.expand_less,
                    size: VisionMetrics.iconMedium,
                    color: t.textTertiary,
                  ),
                  const SizedBox(width: VisionMetrics.space8),
                  Expanded(
                    child: Text(
                      displayName,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: t.fontSize(mobile ? 11 : 9),
                        letterSpacing: 2,
                        color: t.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => _confirmDelete(context),
                    tooltip: l.charEditorDeleteCharacter,
                    icon: Icon(
                      Icons.close,
                      size: VisionMetrics.iconSmall,
                      color: t.textTertiary,
                    ),
                    constraints: BoxConstraints(
                      minWidth: context.hitSize,
                      minHeight: context.hitSize,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),

          // Collapsible body
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _isCollapsed
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(
                      VisionMetrics.space12,
                      0,
                      VisionMetrics.space12,
                      VisionMetrics.space12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Prompt field
                        TouchScrollWrap(
                          child: TextField(
                            controller: _promptController,
                            // Drag-resizable via the handle below, persisted
                            // across sessions (issue #15).
                            maxLines: _promptLines,
                            minLines: _promptLines < 2 ? _promptLines : 2,
                            style: TextStyle(
                              fontSize: t.fontSize(11),
                              color: t.textSecondary,
                              height: 1.4,
                            ),
                            decoration: InputDecoration(
                              hintText: l.charEditorPromptHint.toUpperCase(),
                              hintStyle: TextStyle(
                                fontSize: t.fontSize(9),
                                color: t.textMinimal,
                              ),
                              fillColor: t.surfaceHigh,
                              filled: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  VisionMetrics.radius4,
                                ),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  VisionMetrics.radius4,
                                ),
                                borderSide: BorderSide(color: t.borderMedium),
                              ),
                              contentPadding: const EdgeInsets.all(
                                VisionMetrics.space12,
                              ),
                            ),
                          ),
                        ),
                        LineResizeHandle(
                          lines: _promptLines,
                          lineHeightPx: t.fontSize(11) * 1.4,
                          onLines: (lines) =>
                              setState(() => _promptLines = lines),
                          onDone: (lines) => context
                              .read<PreferencesService>()
                              .setUiCharPromptLines(lines),
                        ),
                        if (_promptSuggestions.isNotEmpty)
                          TagSuggestionOverlay(
                            suggestions: _promptSuggestions,
                            onTagSelected: (tag) => _onTagSelected(
                              _promptController,
                              tag,
                              negativeTarget: _ucController,
                            ),
                          ),

                        // Sub-section toggle chips
                        const SizedBox(height: VisionMetrics.space8),
                        Wrap(
                          spacing: VisionMetrics.space4,
                          runSpacing: VisionMetrics.space4,
                          children: [
                            _ToggleChip(
                              label: l.charEditorShowTitle,
                              isSelected: _showTitle,
                              onTap: () {
                                setState(() => _showTitle = !_showTitle);
                                context
                                    .read<PreferencesService>()
                                    .setUiCharShowTitle(_showTitle);
                              },
                            ),
                            _ToggleChip(
                              label: l.charEditorShowUc,
                              isSelected: _showUc,
                              onTap: () {
                                setState(() => _showUc = !_showUc);
                                context
                                    .read<PreferencesService>()
                                    .setUiCharShowUc(_showUc);
                              },
                            ),
                            _ToggleChip(
                              label: l.charEditorShowPosition,
                              isSelected: _showPosition,
                              onTap: () {
                                setState(() => _showPosition = !_showPosition);
                                context
                                    .read<PreferencesService>()
                                    .setUiCharShowPosition(_showPosition);
                              },
                            ),
                            _ToggleChip(
                              label: l.charEditorShowPresets,
                              isSelected: _showPresets,
                              onTap: () {
                                setState(() => _showPresets = !_showPresets);
                                context
                                    .read<PreferencesService>()
                                    .setUiCharShowPresets(_showPresets);
                              },
                            ),
                          ],
                        ),

                        // Title/name section
                        if (_showTitle) ...[
                          const SizedBox(height: VisionMetrics.space12),
                          SectionTitle(
                            l.charEditorCharacterName.toUpperCase(),
                            t: t,
                            variant: SectionTitleVariant.compact,
                          ),
                          SizedBox(
                            width: mobile ? double.infinity : 400,
                            child: TextField(
                              controller: _nameController,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: t.fontSize(9),
                                color: t.textSecondary,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: l
                                    .charEditorCharacterN(widget.index + 1)
                                    .toUpperCase(),
                                hintStyle: TextStyle(
                                  fontSize: t.fontSize(9),
                                  color: t.textMinimal,
                                ),
                                fillColor: t.surfaceHigh,
                                filled: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    VisionMetrics.radius4,
                                  ),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    VisionMetrics.radius4,
                                  ),
                                  borderSide: BorderSide(color: t.borderMedium),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: VisionMetrics.space12,
                                  vertical: VisionMetrics.space12,
                                ),
                              ),
                            ),
                          ),
                        ],

                        // UC section
                        if (_showUc) ...[
                          const SizedBox(height: VisionMetrics.space12),
                          TouchScrollWrap(
                            child: TextField(
                              controller: _ucController,
                              maxLines: 2,
                              minLines: 1,
                              style: TextStyle(
                                fontSize: t.fontSize(11),
                                color: t.textSecondary,
                                height: 1.4,
                              ),
                              decoration: InputDecoration(
                                hintText: l.charEditorUcHint.toUpperCase(),
                                hintStyle: TextStyle(
                                  fontSize: t.fontSize(9),
                                  color: t.textMinimal,
                                ),
                                fillColor: t.surfaceHigh,
                                filled: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    VisionMetrics.radius4,
                                  ),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    VisionMetrics.radius4,
                                  ),
                                  borderSide: BorderSide(color: t.borderMedium),
                                ),
                                contentPadding: const EdgeInsets.all(
                                  VisionMetrics.space12,
                                ),
                              ),
                            ),
                          ),
                          if (_ucSuggestions.isNotEmpty)
                            TagSuggestionOverlay(
                              suggestions: _ucSuggestions,
                              onTagSelected: (tag) =>
                                  _onTagSelected(_ucController, tag),
                            ),
                        ],

                        // Position section
                        if (_showPosition) ...[
                          const SizedBox(height: VisionMetrics.space12),
                          if (widget.autoPositioning)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: VisionMetrics.space16,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                l.charEditorAiDecidesPosition.toUpperCase(),
                                style: TextStyle(
                                  color: t.accentCharacter,
                                  fontSize: t.fontSize(10),
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2,
                                ),
                              ),
                            )
                          else
                            Center(
                              child: SizedBox(
                                height: 120,
                                width: 120,
                                child: NaiGridSelector(
                                  selectedCoordinate: widget.character.center,
                                  onCoordinateSelected: (coord) {
                                    final notifier = context
                                        .read<GenerationNotifier>();
                                    notifier.updateCharacter(
                                      widget.index,
                                      widget.character.copyWith(center: coord),
                                    );
                                  },
                                ),
                              ),
                            ),
                        ],

                        // Presets section
                        if (_showPresets) ...[
                          const SizedBox(height: VisionMetrics.space12),
                          Row(
                            children: [
                              ActionChip(
                                avatar: Icon(
                                  Icons.save_outlined,
                                  size: 14,
                                  color: t.textTertiary,
                                ),
                                label: Text(
                                  l.charEditorSavePreset,
                                  style: TextStyle(
                                    fontSize: t.fontSize(8),
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                    color: t.textTertiary,
                                  ),
                                ),
                                backgroundColor: t.borderSubtle,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: VisionMetrics.space4,
                                ),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    VisionMetrics.radius2,
                                  ),
                                ),
                                side: BorderSide(
                                  color: t.textMinimal,
                                  width: VisionMetrics.borderWidth,
                                ),
                                onPressed: () => _saveAsPreset(context),
                              ),
                            ],
                          ),
                          const SizedBox(height: VisionMetrics.space8),
                          if (widget.characterPresets.isEmpty)
                            Text(
                              l.charEditorNoPresets.toUpperCase(),
                              style: TextStyle(
                                fontSize: t.fontSize(8),
                                color: t.textMinimal,
                                letterSpacing: 1,
                              ),
                            )
                          else
                            Wrap(
                              spacing: VisionMetrics.space4,
                              runSpacing: VisionMetrics.space4,
                              children: widget.characterPresets.map((preset) {
                                return GestureDetector(
                                  onLongPress: () => showChipActions(
                                    context,
                                    title: preset.name,
                                    onDelete: () => context
                                        .read<GenerationNotifier>()
                                        .deleteCharacterPreset(preset.id),
                                    deleteMessage: l.panelDeletePresetConfirm(
                                      preset.name,
                                    ),
                                  ),
                                  child: ActionChip(
                                    label: Text(
                                      preset.name.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: t.fontSize(8),
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                        color: t.textTertiary,
                                      ),
                                    ),
                                    backgroundColor: t.borderSubtle,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: VisionMetrics.space4,
                                    ),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        VisionMetrics.radius2,
                                      ),
                                    ),
                                    side: BorderSide(
                                      color: t.textMinimal,
                                      width: VisionMetrics.borderWidth,
                                    ),
                                    onPressed: () {
                                      final notifier = context
                                          .read<GenerationNotifier>();
                                      notifier.applyCharacterPreset(
                                        widget.index,
                                        preset,
                                      );
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Interactions Section ────────────────────────────────────────────────────

class _InteractionsSection extends StatelessWidget {
  final List<NaiCharacter> characters;
  final List<NaiInteraction> interactions;

  const _InteractionsSection({
    required this.characters,
    required this.interactions,
  });

  void _openInteractionEditor(
    BuildContext context, {
    required List<int> sourceIndices,
    required List<int> targetIndices,
    required InteractionType type,
    NaiInteraction? existing,
  }) {
    final notifier = context.read<GenerationNotifier>();

    showAppSheet(
      context: context,
      builder: (context) => ActionInteractionSheet(
        sourceIndices: sourceIndices,
        targetIndices: targetIndices,
        initialType: type,
        characters: characters,
        initialInteraction: existing,
        onSave: (updated) =>
            notifier.updateInteraction(updated, replacing: existing),
        onDelete: () {
          if (existing != null) notifier.removeInteraction(existing);
        },
      ),
    );
  }

  void _showAddInteractionPicker(BuildContext context) {
    final l = context.l;
    var isMutual = false;
    final selectedSources = <int>{};
    final selectedTargets = <int>{};

    showAppSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final t = ctx.t;

          Widget buildCharChip(int i, Set<int> selected, {Set<int>? excluded}) {
            final name = characters[i].name.isNotEmpty
                ? characters[i].name
                : l.charEditorCharacterN(i + 1);
            final isExcluded = excluded?.contains(i) ?? false;
            return FilterChip(
              label: Text(name.toUpperCase()),
              selected: selected.contains(i),
              showCheckmark: false,
              onSelected: isExcluded
                  ? null
                  : (on) => setSheetState(() {
                      if (on) {
                        selected.add(i);
                      } else {
                        selected.remove(i);
                      }
                    }),
            );
          }

          Widget picker(String title, Set<int> selected, {Set<int>? excluded}) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle(
                  title.toUpperCase(),
                  t: t,
                  variant: SectionTitleVariant.compact,
                ),
                Wrap(
                  spacing: VisionMetrics.space8,
                  runSpacing: VisionMetrics.space8,
                  children: [
                    for (var i = 0; i < characters.length; i++)
                      buildCharChip(i, selected, excluded: excluded),
                  ],
                ),
              ],
            );
          }

          final canContinue = isMutual
              ? selectedSources.length >= 2
              : selectedSources.isNotEmpty && selectedTargets.isNotEmpty;

          return AppPickerSheet(
            title: l.charEditorAddInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSegmented<bool>(
                  options: [
                    AppOption(value: false, label: l.charEditorSourceTarget),
                    AppOption(value: true, label: l.charEditorMutual),
                  ],
                  selected: isMutual,
                  onChanged: (mutual) => setSheetState(() {
                    isMutual = mutual;
                    selectedTargets.clear();
                  }),
                ),
                const SizedBox(height: VisionMetrics.space16),
                if (isMutual)
                  picker(l.charEditorParticipants, selectedSources)
                else ...[
                  picker(
                    l.charEditorSelectSource,
                    selectedSources,
                    excluded: selectedTargets,
                  ),
                  const SizedBox(height: VisionMetrics.space16),
                  picker(
                    l.charEditorSelectTarget,
                    selectedTargets,
                    excluded: selectedSources,
                  ),
                ],
                const SizedBox(height: VisionMetrics.space24),
                ElevatedButton(
                  onPressed: canContinue
                      ? () {
                          Navigator.pop(ctx);
                          _openInteractionEditor(
                            context,
                            sourceIndices: selectedSources.toList()..sort(),
                            targetIndices: isMutual
                                ? []
                                : (selectedTargets.toList()..sort()),
                            type: isMutual
                                ? InteractionType.mutual
                                : InteractionType.sourceTarget,
                          );
                        }
                      : null,
                  child: Text(l.charEditorContinue.toUpperCase()),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          l.charEditorInteractions.toUpperCase(),
          t: t,
          variant: SectionTitleVariant.compact,
        ),
        // Existing interactions
        for (final interaction in interactions) ...[
          _InteractionTile(
            interaction: interaction,
            characters: characters,
            onTap: () => _openInteractionEditor(
              context,
              sourceIndices: interaction.sourceCharacterIndices,
              targetIndices: interaction.targetCharacterIndices,
              type: interaction.type,
              existing: interaction,
            ),
          ),
          const SizedBox(height: VisionMetrics.space4),
        ],
        // Add interaction button
        _AddButton(
          onTap: () => _showAddInteractionPicker(context),
          label: l.charEditorAddInteraction,
        ),
      ],
    );
  }
}

// ─── Interaction Tile ────────────────────────────────────────────────────────

class _InteractionTile extends StatelessWidget {
  final NaiInteraction interaction;
  final List<NaiCharacter> characters;
  final VoidCallback onTap;

  const _InteractionTile({
    required this.interaction,
    required this.characters,
    required this.onTap,
  });

  String _charName(int index, BuildContext context) {
    if (index >= 0 &&
        index < characters.length &&
        characters[index].name.isNotEmpty) {
      return characters[index].name;
    }
    return context.l.charEditorCharacterN(index + 1);
  }

  String _joinNames(List<int> indices, BuildContext context) {
    return indices.map((i) => _charName(i, context)).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;

    final String display;
    if (interaction.type == InteractionType.mutual) {
      final participants = interaction.sourceCharacterIndices
          .map((i) => _charName(i, context))
          .join(' \u2194 ');
      display = '$participants: ${interaction.actionName}';
    } else {
      final source = _joinNames(interaction.sourceCharacterIndices, context);
      final target = _joinNames(interaction.targetCharacterIndices, context);
      display = l.charEditorInteractionDisplay(
        source,
        target,
        interaction.actionName,
      );
    }

    final radius = BorderRadius.circular(VisionMetrics.radius4);
    return Material(
      color: t.borderSubtle,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: t.accentSuccess.withValues(alpha: VisionMetrics.opacityScrim),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: VisionMetrics.space12,
            vertical: VisionMetrics.space8,
          ),
          child: Text(
            display,
            style: TextStyle(
              fontSize: t.fontSize(9),
              color: t.textSecondary,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
