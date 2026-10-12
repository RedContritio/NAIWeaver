import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/gateway/backend_gateway.dart';
import '../../../core/gateway/backend_permissions.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_metrics.dart';
import '../../../core/theme/vision_tokens.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/color_picker_dialog.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/browser_native_selectable_text.dart';
import '../../../core/widgets/section_title.dart';
import '../../../core/widgets/ui/app_panel.dart';
import '../../../core/widgets/ui/app_pill.dart';
import '../../../core/widgets/ui/app_states.dart';
import '../../../core/widgets/ui/app_tone.dart';
import '../../../l10n/app_localizations.dart';
import '../../generation/providers/generation_notifier.dart';
import '../../text_gen/providers/text_gen_notifier.dart';
import '../gen/providers/character_gen_notifier.dart';
import '../gen/widgets/character_gen_dialog.dart';
import '../gen/widgets/character_gen_progress_dialog.dart';
import '../models/closet_outfit.dart';
import '../models/saved_character.dart';
import '../outfit/outfit_renderer.dart';
import '../outfit/outfit_slots.dart';
import '../outfit/widgets/outfit_state_panel.dart';
import '../photoshoot/photoshoot_screen.dart';
import '../providers/character_library_notifier.dart';
import '../services/wardrobe_generator_service.dart';
import 'outfit_editor_sheet.dart';
import 'tag_text_field.dart';
import 'wardrobe_generate_dialog.dart';
import '../gen/character_gen_error_message.dart';

/// Puts a character's [tags] (plus `nsfw` when [dishevelled]) and its
/// [negativeTags] where `charInsertTarget` says, via the shared
/// [GenerationNotifier.insertCharacterTags] entry point.
ApplyTagResult applyCharacterToPrompt(
  GenerationNotifier gen, {
  required String name,
  required String tags,
  String? negativeTags,
  bool dishevelled = false,
}) {
  final clean = tags.trim().replaceAll(RegExp(r',\s*$'), '');
  return gen.insertCharacterTags(
    dishevelled ? '$clean, nsfw' : clean,
    negativeTags,
    name: name,
  );
}

/// The Characters tool page: a saved-character library (list + editor) with a
/// per-character wardrobe and an outfit-state panel.
class CharactersPage extends StatefulWidget {
  const CharactersPage({super.key});

  @override
  State<CharactersPage> createState() => _CharactersPageState();
}

class _CharactersPageState extends State<CharactersPage> {
  String? _selectedId;
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final lib = context.watch<CharacterLibraryNotifier>();
    final sizeClass = windowSizeClassOf(context);
    final touch = sizeClass.isTouchSized;

    final filtered = lib.characters
        .where(
          (c) =>
              _filter.isEmpty ||
              c.name.toLowerCase().contains(_filter.toLowerCase()),
        )
        .toList();
    final selected = _selectedId == null
        ? null
        : lib.characterById(_selectedId!);

    if (touch) {
      // On touch-sized windows: list, then editor pushed.
      if (selected == null) {
        return _buildListPane(context, t, lib, filtered, touch: true);
      }
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _selectedId = null);
        },
        child: _CharacterEditor(
          key: ValueKey(selected.id),
          character: selected,
          onBack: () => setState(() => _selectedId = null),
        ),
      );
    }

    return Row(
      children: [
        SizedBox(
          width: switch (sizeClass) {
            WindowSizeClass.xlarge => 340.0,
            WindowSizeClass.large => 300.0,
            _ => 260.0,
          },
          child: _buildListPane(context, t, lib, filtered, touch: false),
        ),
        VerticalDivider(width: 1, color: t.borderMedium),
        Expanded(
          child: selected == null
              ? EmptyState(
                  icon: Icons.person_outline,
                  message: context.l.charsSelectOrCreate,
                )
              : _CharacterEditor(
                  key: ValueKey(selected.id),
                  character: selected,
                ),
        ),
      ],
    );
  }

  Future<void> _generateCharacter(BuildContext context) async {
    final form = await CharacterGenDialog.show(context);
    if (form == null || !context.mounted) return;
    final id = await CharacterGenProgressDialog.run(context, form);
    if (!context.mounted) return;
    final notifier = context.read<CharacterGenNotifier>();
    if (id != null) {
      if (mounted) setState(() => _selectedId = id);
      showAppSnackBar(context, context.l.charsGenerated);
    } else if (notifier.lastError != null) {
      showErrorSnackBar(context, characterGenErrorMessage(context.l, notifier.lastError!));
    }
  }

  Widget _buildListPane(
    BuildContext context,
    VisionTokens t,
    CharacterLibraryNotifier lib,
    List<SavedCharacter> filtered, {
    required bool touch,
  }) {
    final l = context.l;
    final rowVerticalPad = touch ? VisionMetrics.space12 : VisionMetrics.space8;
    final rowHorizontalPad = touch
        ? VisionMetrics.space16
        : VisionMetrics.space12;
    return Container(
      color: t.surfaceMid,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              VisionMetrics.space8,
              VisionMetrics.space8,
              VisionMetrics.space8,
              VisionMetrics.space4,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _filter = v),
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: t.fontSize(12),
                    ),
                    decoration: InputDecoration(
                      hintText: l.charsSearchHint,
                      hintStyle: TextStyle(
                        color: t.textMinimal,
                        fontSize: t.fontSize(10),
                      ),
                      isDense: true,
                      prefixIcon: Icon(
                        Icons.search,
                        size: VisionMetrics.iconMedium,
                        color: t.textMinimal,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: VisionMetrics.space8,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: t.borderSubtle),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: VisionMetrics.space4),
                Builder(
                  builder: (ctx) {
                    final blocker = _textGenBlocker(
                      ctx,
                      hasService: ctx.watch<CharacterGenNotifier>().hasService,
                    );
                    final canGen = blocker == null;
                    return IconButton(
                      tooltip: canGen ? l.charsGenerateTooltip : blocker,
                      icon: Icon(
                        Icons.auto_awesome,
                        color: canGen ? t.accent : t.textMinimal,
                        size: VisionMetrics.iconMedium,
                      ),
                      onPressed: canGen ? () => _generateCharacter(ctx) : null,
                    );
                  },
                ),
                IconButton(
                  tooltip: l.charsNew,
                  icon: Icon(
                    Icons.add,
                    color: t.accent,
                    size: VisionMetrics.iconMedium,
                  ),
                  onPressed: () async {
                    final c = await lib.createCharacter(l.charsNewDefaultName);
                    if (!mounted) return;
                    setState(() => _selectedId = c.id);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? EmptyState(message: l.charsEmptyList)
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final c = filtered[i];
                      final primary = lib.primaryOutfitFor(c.id);
                      final outfitCount = lib.closetFor(c.id).length;
                      final isSel = c.id == _selectedId;
                      Color swatch = t.accent;
                      if (c.themeAccent != null) {
                        final parsed = _parseHex(c.themeAccent!);
                        if (parsed != null) swatch = parsed;
                      }
                      final primaryDishevelled =
                          primary != null &&
                          primary.items != null &&
                          anyNonIntact(primary.items!.cast<String, dynamic>());
                      return InkWell(
                        onTap: () => setState(() => _selectedId = c.id),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: rowHorizontalPad,
                            vertical: rowVerticalPad,
                          ),
                          decoration: BoxDecoration(
                            color: isSel ? t.borderSubtle : Colors.transparent,
                            border: Border(
                              left: BorderSide(
                                color: isSel ? t.accent : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: swatch,
                                  borderRadius: BorderRadius.circular(
                                    VisionMetrics.radius2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: VisionMetrics.space12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            c.name.isEmpty
                                                ? l.charsUnnamed
                                                : c.name,
                                            style: TextStyle(
                                              color: isSel
                                                  ? t.textPrimary
                                                  : t.textSecondary,
                                              fontSize: t.fontSize(
                                                touch ? 13 : 12,
                                              ),
                                              fontWeight: isSel
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (outfitCount > 0) ...[
                                          const SizedBox(
                                            width: VisionMetrics.space8,
                                          ),
                                          AppPill(
                                            text: '$outfitCount',
                                            dense: true,
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (primary != null)
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              primary.name,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: t.textMinimal,
                                                fontSize: t.fontSize(9),
                                              ),
                                            ),
                                          ),
                                          if (primaryDishevelled) ...[
                                            const SizedBox(
                                              width: VisionMetrics.space8,
                                            ),
                                            Container(
                                              width: 6,
                                              height: 6,
                                              decoration: BoxDecoration(
                                                color: t.accentDanger,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

Color? _parseHex(String hex) {
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

String _toHex(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

/// Why text generation cannot be used right now, or null when it can.
///
/// Behind the gateway the cause is the account's `text.generate` permission
/// (there is no API key to set); with a direct connection it is the missing
/// key. [wardrobe] picks the wording that names the Text Gen settings.
String? _textGenBlocker(
  BuildContext context, {
  required bool hasService,
  bool wardrobe = false,
}) {
  final l = context.l;
  final permitted = hasBackendPermission(
    context,
    BackendPermission.textGenerate,
  );
  if (!permitted || (!hasService && useBackendGateway)) {
    return l.charsTextGenNoPermission;
  }
  if (!hasService) {
    return wardrobe ? l.charsTextGenNeedsKeyWardrobe : l.charsTextGenNeedsKey;
  }
  return null;
}

String _genderLabel(AppLocalizations l, String gender) => switch (gender) {
  'female' => l.charsGenderFemale,
  'male' => l.charsGenderMale,
  'nonbinary' => l.charsGenderNonbinary,
  _ => l.charsGenderUnspecified,
};

class _CharacterEditor extends StatefulWidget {
  final SavedCharacter character;
  final VoidCallback? onBack;
  const _CharacterEditor({super.key, required this.character, this.onBack});

  @override
  State<_CharacterEditor> createState() => _CharacterEditorState();
}

class _CharacterEditorState extends State<_CharacterEditor> {
  late TextEditingController _name;
  late TextEditingController _notes;
  late TextEditingController _base;
  late TextEditingController _face;
  late TextEditingController _hair;
  late TextEditingController _body;
  late TextEditingController _negativeTags;
  late TextEditingController _nsfwTop;
  late TextEditingController _nsfwBottom;
  late TextEditingController _nsfwAlways;
  late TextEditingController _artist;
  late TextEditingController _stylePrefix;
  late TextEditingController _description;
  late TextEditingController _soul;
  late String _gender;
  bool _showNsfw = false;
  bool _showStyle = false;
  bool _showSoul = false;
  String? _selectedOutfitId;

  static const _genders = ['', 'female', 'male', 'nonbinary'];

  @override
  void initState() {
    super.initState();
    _initFrom(widget.character);
  }

  void _initFrom(SavedCharacter c) {
    _name = TextEditingController(text: c.name);
    _notes = TextEditingController(text: c.notes);
    _base = TextEditingController(text: c.baseTags);
    _face = TextEditingController(text: c.faceTags);
    _hair = TextEditingController(text: c.hairTags);
    _body = TextEditingController(text: c.bodyTags_);
    _negativeTags = TextEditingController(text: c.negativeTags);
    _nsfwTop = TextEditingController(text: c.nsfwTop);
    _nsfwBottom = TextEditingController(text: c.nsfwBottom);
    _nsfwAlways = TextEditingController(text: c.nsfwAlways);
    _artist = TextEditingController(text: c.artistTag);
    _stylePrefix = TextEditingController(text: c.stylePrefix);
    _description = TextEditingController(text: c.characterDescription);
    _soul = TextEditingController(text: c.soulMd);
    _gender = _genders.contains(c.gender) ? c.gender : '';
    _showNsfw =
        c.nsfwTop.isNotEmpty ||
        c.nsfwBottom.isNotEmpty ||
        c.nsfwAlways.isNotEmpty;
    _showStyle =
        c.artistTag.isNotEmpty ||
        c.stylePrefix.isNotEmpty ||
        c.characterDescription.isNotEmpty;
    _showSoul = c.soulMd.trim().isNotEmpty;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _notes,
      _base,
      _face,
      _hair,
      _body,
      _negativeTags,
      _nsfwTop,
      _nsfwBottom,
      _nsfwAlways,
      _artist,
      _stylePrefix,
      _description,
      _soul,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  SavedCharacter _collect() => widget.character.copyWith(
    name: _name.text.trim(),
    gender: _gender,
    notes: _notes.text,
    soulMd: _soul.text,
    baseTags: _base.text.trim(),
    faceTags: _face.text.trim(),
    hairTags: _hair.text.trim(),
    bodyTags: _body.text.trim(),
    negativeTags: _negativeTags.text.trim(),
    nsfwTop: _nsfwTop.text.trim(),
    nsfwBottom: _nsfwBottom.text.trim(),
    nsfwAlways: _nsfwAlways.text.trim(),
    artistTag: _artist.text.trim(),
    stylePrefix: _stylePrefix.text.trim(),
    characterDescription: _description.text,
  );

  Future<void> _save(CharacterLibraryNotifier lib) async {
    await lib.updateCharacter(_collect());
  }

  /// The one place this page inserts a character/outfit into the generation
  /// prompt (WEAR and the outfit-state panel both end up here). The target
  /// (main prompt or a new character card) follows `charInsertTarget`.
  void _insertIntoPrompt(
    SavedCharacter character,
    ClosetOutfit outfit,
    String tags,
    bool dishevelled,
  ) {
    if (tags.trim().isEmpty) return;
    final result = applyCharacterToPrompt(
      context.read<GenerationNotifier>(),
      name: character.name,
      tags: tags,
      negativeTags: context
          .read<CharacterLibraryNotifier>()
          .negativeExpansionFor(character, outfit),
      dishevelled: dishevelled,
    );
    if (result == ApplyTagResult.characterLimitReached) {
      showErrorSnackBar(context, context.l.charEditorCharacterLimitReached);
      return;
    }
    showAppSnackBar(context, context.l.charsAddedToPrompt);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    final lib = context.watch<CharacterLibraryNotifier>();
    final c = lib.characterById(widget.character.id) ?? widget.character;
    final closet = lib.closetFor(c.id);
    final primaryOutfit = lib.primaryOutfitFor(c.id);
    final combined = lib.expansionFor(c, primaryOutfit);

    final selectedOutfit = _selectedOutfitId == null
        ? null
        : closet.where((o) => o.id == _selectedOutfitId).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: t.surfaceHigh,
          padding: const EdgeInsets.symmetric(
            horizontal: VisionMetrics.space12,
            vertical: VisionMetrics.space8,
          ),
          child: Row(
            children: [
              if (widget.onBack != null)
                IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  icon: Icon(
                    Icons.arrow_back,
                    size: VisionMetrics.iconMedium,
                    color: t.textSecondary,
                  ),
                  onPressed: widget.onBack,
                ),
              Expanded(
                child: TextField(
                  controller: _name,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: t.fontSize(16),
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: l.charsNamePlaceholder,
                    hintStyle: TextStyle(color: t.textMinimal),
                  ),
                  onSubmitted: (_) => _save(lib),
                ),
              ),
              IconButton(
                tooltip: l.charsPhotoshoot,
                icon: Icon(
                  Icons.photo_camera_outlined,
                  size: VisionMetrics.iconMedium,
                  color: t.accent,
                ),
                onPressed: lib.primaryOutfitFor(c.id) == null
                    ? null
                    : () async {
                        await _save(lib);
                        if (!context.mounted) return;
                        final outfit = lib.primaryOutfitFor(c.id);
                        if (outfit == null) return;
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PhotoshootScreen(
                              characterId: c.id,
                              initialOutfitId: outfit.id,
                            ),
                          ),
                        );
                      },
              ),
              IconButton(
                tooltip: l.commonSave,
                icon: Icon(
                  Icons.save_outlined,
                  size: VisionMetrics.iconMedium,
                  color: t.accent,
                ),
                onPressed: () => _save(lib),
              ),
              IconButton(
                tooltip: l.charsDelete,
                icon: Icon(
                  Icons.delete_outline,
                  size: VisionMetrics.iconMedium,
                  color: t.accentDanger,
                ),
                onPressed: () async {
                  final ok = await showConfirmDialog(
                    context,
                    title: l.charsDelete,
                    message: l.charsDeleteMessage(c.name),
                    confirmLabel: l.commonDelete,
                    cancelLabel: l.commonCancel,
                    confirmColor: t.accentDanger,
                  );
                  if (ok == true && mounted) {
                    await lib.deleteCharacter(c.id);
                    widget.onBack?.call();
                  }
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(VisionMetrics.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      l.charsGender.toUpperCase(),
                      style: TextStyle(
                        color: t.textTertiary,
                        fontSize: t.fontSize(8),
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(width: 10),
                    DropdownButton<String>(
                      value: _gender,
                      isDense: true,
                      dropdownColor: t.surfaceHigh,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: t.fontSize(11),
                      ),
                      onChanged: (v) => setState(() => _gender = v ?? ''),
                      items: [
                        for (final g in _genders)
                          DropdownMenuItem(
                            value: g,
                            child: Text(
                              _genderLabel(l, g),
                              style: TextStyle(fontSize: t.fontSize(11)),
                            ),
                          ),
                      ],
                    ),
                    const Spacer(),
                    ..._themeSwatches(t, c, lib),
                  ],
                ),
                const SizedBox(height: VisionMetrics.space16),
                SectionTitle(
                  l.charsIdentityTags.toUpperCase(),
                  t: t,
                  variant: SectionTitleVariant.compact,
                ),
                TagTextField(
                  controller: _base,
                  label: l.charsBaseLabel,
                  minLines: 1,
                  maxLines: 3,
                ),
                const SizedBox(height: 10),
                TagTextField(
                  controller: _face,
                  label: l.charsFaceLabel,
                  minLines: 1,
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                TagTextField(
                  controller: _hair,
                  label: l.charsHairLabel,
                  minLines: 1,
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                TagTextField(
                  controller: _body,
                  label: l.charsBodyLabel,
                  minLines: 1,
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                TagTextField(
                  controller: _negativeTags,
                  label: l.charsNegativeLabel,
                  minLines: 1,
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                _expander(
                  t,
                  l.charsNsfwSection,
                  _showNsfw,
                  () => setState(() => _showNsfw = !_showNsfw),
                ),
                if (_showNsfw) ...[
                  const SizedBox(height: 8),
                  TagTextField(
                    controller: _nsfwTop,
                    label: l.charsNsfwTop,
                    minLines: 1,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  TagTextField(
                    controller: _nsfwBottom,
                    label: l.charsNsfwBottom,
                    minLines: 1,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  TagTextField(
                    controller: _nsfwAlways,
                    label: l.charsNsfwAlways,
                    minLines: 1,
                    maxLines: 2,
                  ),
                ],
                const SizedBox(height: 10),
                _expander(
                  t,
                  l.charsStyleSection,
                  _showStyle,
                  () => setState(() => _showStyle = !_showStyle),
                ),
                if (_showStyle) ...[
                  const SizedBox(height: 8),
                  TagTextField(
                    controller: _artist,
                    label: l.charsArtistTag,
                    minLines: 1,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 8),
                  TagTextField(
                    controller: _stylePrefix,
                    label: l.charsStylePrefix,
                    minLines: 1,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 8),
                  _plainField(
                    t,
                    l.charsDescriptionLabel,
                    _description,
                    maxLines: 3,
                  ),
                ],
                const SizedBox(height: 10),
                _expander(
                  t,
                  l.charsSoulSection,
                  _showSoul,
                  () => setState(() => _showSoul = !_showSoul),
                ),
                if (_showSoul) ...[
                  const SizedBox(height: 8),
                  if (c.personalitySummary.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        c.personalitySummary.trim(),
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: t.fontSize(11),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  _plainField(t, l.charsSoulLabel, _soul, maxLines: 14),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: AppPanel(
                    variant: AppPanelVariant.inset,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.charsCombinedTags.toUpperCase(),
                          style: TextStyle(
                            color: t.textTertiary,
                            fontSize: t.fontSize(8),
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        BrowserNativeSelectableText(
                          text: combined.isEmpty ? l.charsEmptyValue : combined,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: t.fontSize(11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: VisionMetrics.space16),
                _WardrobeSection(
                  characterId: c.id,
                  selectedOutfitId: _selectedOutfitId,
                  onSelectOutfit: (id) =>
                      setState(() => _selectedOutfitId = id),
                  onApplyToPrompt: (outfit, tags, dishevelled) =>
                      _insertIntoPrompt(c, outfit, tags, dishevelled),
                ),
                if (selectedOutfit != null) ...[
                  const SizedBox(height: VisionMetrics.space16),
                  SizedBox(
                    width: double.infinity,
                    child: AppPanel(
                      variant: AppPanelVariant.inset,
                      child: OutfitStatePanel(
                        key: ValueKey('state_${selectedOutfit.id}'),
                        outfit: selectedOutfit,
                        onChanged: (updated) => lib.updateOutfit(c.id, updated),
                        onApplyToPrompt: (tags, dishevelled) =>
                            _insertIntoPrompt(
                              c,
                              selectedOutfit,
                              tags,
                              dishevelled,
                            ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _themeSwatches(
    VisionTokens t,
    SavedCharacter c,
    CharacterLibraryNotifier lib,
  ) {
    final l = context.l;
    Widget swatch(String label, String? hex, void Function(String?) set) {
      final col = hex != null ? _parseHex(hex) : null;
      return Padding(
        padding: const EdgeInsets.only(left: VisionMetrics.space4),
        child: Tooltip(
          message: label,
          child: InkWell(
            borderRadius: VisionMetrics.borderRadius4,
            onTap: () async {
              final picked = await ColorPickerDialog.show(
                context,
                initialColor: col ?? t.accent,
                label: label,
              );
              if (picked != null) {
                set(_toHex(picked));
              }
            },
            onLongPress: () => set(null),
            child: SizedBox(
              width: context.hitSize,
              height: context.hitSize,
              child: Center(
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: col ?? Colors.transparent,
                    borderRadius: VisionMetrics.borderRadius4,
                    border: Border.all(color: t.borderMedium),
                  ),
                  child: col == null
                      ? Icon(
                          Icons.add,
                          size: VisionMetrics.iconSmall,
                          color: t.textMinimal,
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return [
      Text(
        l.charsTint.toUpperCase(),
        style: TextStyle(
          color: t.textTertiary,
          fontSize: t.fontSize(8),
          letterSpacing: 1.5,
        ),
      ),
      swatch(
        l.charsTintAccent,
        c.themeAccent,
        (h) => lib.updateCharacter(c.copyWith(themeAccent: h)),
      ),
      swatch(
        l.charsTintAccent2,
        c.themeAccentSecondary,
        (h) => lib.updateCharacter(c.copyWith(themeAccentSecondary: h)),
      ),
      swatch(
        l.charsTintBg,
        c.themeBg,
        (h) => lib.updateCharacter(c.copyWith(themeBg: h)),
      ),
    ];
  }

  Widget _expander(
    VisionTokens t,
    String label,
    bool open,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: context.hitSize),
        child: Row(
          children: [
            Icon(
              open ? Icons.expand_less : Icons.expand_more,
              size: VisionMetrics.iconMedium,
              color: t.textTertiary,
            ),
            const SizedBox(width: 4),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: t.textTertiary,
                fontSize: t.fontSize(8),
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _plainField(
    VisionTokens t,
    String label,
    TextEditingController ctrl, {
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: t.textSecondary,
            fontSize: t.fontSize(9),
            letterSpacing: 2,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          minLines: 1,
          maxLines: maxLines,
          style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(12)),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 8,
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: t.borderSubtle),
              borderRadius: BorderRadius.circular(4),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: t.accent),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ],
    );
  }
}

class _WardrobeSection extends StatefulWidget {
  final String characterId;
  final String? selectedOutfitId;
  final ValueChanged<String?> onSelectOutfit;
  final void Function(ClosetOutfit outfit, String tags, bool dishevelled)
  onApplyToPrompt;

  const _WardrobeSection({
    required this.characterId,
    required this.selectedOutfitId,
    required this.onSelectOutfit,
    required this.onApplyToPrompt,
  });

  @override
  State<_WardrobeSection> createState() => _WardrobeSectionState();
}

class _WardrobeSectionState extends State<_WardrobeSection> {
  /// True from the tap on GENERATE until the request settles (covers the
  /// parameter dialog too), so a second tap cannot start a second request.
  bool _busy = false;

  /// True only while the text-generation request itself is running.
  bool _generating = false;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final lib = context.watch<CharacterLibraryNotifier>();
    final closet = lib.closetFor(widget.characterId);
    final c = lib.characterById(widget.characterId);
    final l = context.l;
    final textGen = context.watch<TextGenNotifier>();
    final blocker = _textGenBlocker(
      context,
      hasService: textGen.hasService,
      wardrobe: true,
    );
    final hasTextGen = blocker == null;
    final touch = windowSizeClassOf(context).isTouchSized;

    final generateButton = Tooltip(
      message: hasTextGen ? l.charsGenerateOutfitsTooltip : blocker,
      child: TextButton.icon(
        onPressed: (!hasTextGen || _busy)
            ? null
            : () => _generate(context, lib, c),
        icon: _generating
            ? SizedBox(
                width: VisionMetrics.iconSmall,
                height: VisionMetrics.iconSmall,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: t.accent,
                ),
              )
            : Icon(
                Icons.auto_awesome,
                size: VisionMetrics.iconSmall,
                color: hasTextGen ? t.accent : t.textMinimal,
              ),
        label: Text(
          (_generating ? l.charsGenerating : l.charsGenerateOutfits)
              .toUpperCase(),
          style: TextStyle(fontSize: t.fontSize(9), letterSpacing: 1),
        ),
      ),
    );
    final newOutfitButton = TextButton.icon(
      onPressed: () => _newOutfit(context, lib),
      icon: Icon(Icons.add, size: VisionMetrics.iconSmall, color: t.accent),
      label: Text(
        l.charsNewOutfit.toUpperCase(),
        style: TextStyle(fontSize: t.fontSize(9), letterSpacing: 1),
      ),
    );
    final title = Text(
      l.charsWardrobe.toUpperCase(),
      style: TextStyle(
        color: t.textSecondary,
        fontSize: t.titleSize(10),
        letterSpacing: 3,
        fontWeight: FontWeight.bold,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // On touch-sized windows the title + both action buttons overflow a
        // single row and truncate the labels, so let the buttons wrap onto
        // their own line.
        if (touch)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            spacing: VisionMetrics.space4,
            runSpacing: VisionMetrics.space4,
            children: [
              title,
              Wrap(
                spacing: VisionMetrics.space4,
                children: [generateButton, newOutfitButton],
              ),
            ],
          )
        else
          Row(
            children: [
              title,
              const Spacer(),
              generateButton,
              const SizedBox(width: VisionMetrics.space4),
              newOutfitButton,
            ],
          ),
        const SizedBox(height: VisionMetrics.space8),
        if (closet.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: VisionMetrics.space8),
            child: Text(
              l.charsNoOutfits,
              style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(10)),
            ),
          )
        else if (touch)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final o in closet) ...[
                _OutfitCard(
                  outfit: o,
                  isPrimary: c?.primaryOutfitId == o.id,
                  isSelected: widget.selectedOutfitId == o.id,
                  touch: true,
                  onTapState: () => widget.onSelectOutfit(
                    widget.selectedOutfitId == o.id ? null : o.id,
                  ),
                  onWear: () => _wear(o, c),
                  onEdit: () =>
                      _editOutfit(context, lib, o, c?.primaryOutfitId == o.id),
                  onSetPrimary: () => lib.setPrimaryOutfit(
                    widget.characterId,
                    c?.primaryOutfitId == o.id ? null : o.id,
                  ),
                  onDelete: () => _confirmDelete(context, lib, o),
                ),
                const SizedBox(height: VisionMetrics.space8),
              ],
            ],
          )
        else
          Wrap(
            spacing: VisionMetrics.space12,
            runSpacing: VisionMetrics.space12,
            children: [
              for (final o in closet)
                _OutfitCard(
                  outfit: o,
                  isPrimary: c?.primaryOutfitId == o.id,
                  isSelected: widget.selectedOutfitId == o.id,
                  touch: false,
                  onTapState: () => widget.onSelectOutfit(
                    widget.selectedOutfitId == o.id ? null : o.id,
                  ),
                  onWear: () => _wear(o, c),
                  onEdit: () =>
                      _editOutfit(context, lib, o, c?.primaryOutfitId == o.id),
                  onSetPrimary: () => lib.setPrimaryOutfit(
                    widget.characterId,
                    c?.primaryOutfitId == o.id ? null : o.id,
                  ),
                  onDelete: () => _confirmDelete(context, lib, o),
                ),
            ],
          ),
      ],
    );
  }

  void _wear(ClosetOutfit o, SavedCharacter? c) {
    final r = (o.items != null && o.items!.isNotEmpty)
        ? renderItemsToTags(o.items!.cast<String, dynamic>())
        : applyConcealment(o.tags);
    final body = c == null ? '' : c.derivedBodyTags;
    final combined = [
      if (body.isNotEmpty) body,
      if (r.tags.isNotEmpty) r.tags,
    ].join(', ');
    widget.onApplyToPrompt(o, combined, r.isDishevelled);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    CharacterLibraryNotifier lib,
    ClosetOutfit o,
  ) async {
    final t = context.tRead;
    final l = context.l;
    final ok = await showConfirmDialog(
      context,
      title: l.charsDeleteOutfitTitle,
      message: l.charsDeleteOutfitMessage(o.name),
      confirmLabel: l.commonDelete,
      cancelLabel: l.commonCancel,
      confirmColor: t.accentDanger,
    );
    if (ok == true) {
      if (widget.selectedOutfitId == o.id) widget.onSelectOutfit(null);
      await lib.deleteOutfit(widget.characterId, o.id);
    }
  }

  void _newOutfit(BuildContext context, CharacterLibraryNotifier lib) {
    final draft = ClosetOutfit.create(
      name: context.l.charsNewOutfitDefaultName,
    );
    OutfitEditorSheet.show(
      context,
      outfit: draft,
      isPrimary: false,
      onSave: (o, makePrimary) async {
        await lib.addOutfit(widget.characterId, o);
        if (makePrimary) await lib.setPrimaryOutfit(widget.characterId, o.id);
      },
    );
  }

  void _editOutfit(
    BuildContext context,
    CharacterLibraryNotifier lib,
    ClosetOutfit o,
    bool isPrimary,
  ) {
    OutfitEditorSheet.show(
      context,
      outfit: o,
      isPrimary: isPrimary,
      onSave: (updated, makePrimary) async {
        await lib.updateOutfit(widget.characterId, updated);
        if (makePrimary && !isPrimary) {
          await lib.setPrimaryOutfit(widget.characterId, updated.id);
        } else if (!makePrimary && isPrimary) {
          await lib.setPrimaryOutfit(widget.characterId, null);
        }
      },
    );
  }

  Future<void> _generate(
    BuildContext context,
    CharacterLibraryNotifier lib,
    SavedCharacter? c,
  ) async {
    if (c == null || _busy) return;
    final textGen = context.read<TextGenNotifier>();
    setState(() => _busy = true);
    // Everything after an await first checks `mounted`: the user can leave the
    // page while the dialog or the request is open.
    void snack(String msg, {AppTone tone = AppTone.success}) {
      if (mounted) showAppSnackBar(this.context, msg, tone: tone);
    }

    try {
      final params = await WardrobeGenerateDialog.show(context);
      if (params == null || !mounted) return;
      final service = textGen.service;
      if (service == null) {
        snack(this.context.l.charsTextGenNotConfigured, tone: AppTone.warning);
        return;
      }
      setState(() => _generating = true);
      final svc = WardrobeGeneratorService(service);
      final outfits = await svc.generate(
        characterTags: c.derivedBodyTags.isEmpty ? c.name : c.derivedBodyTags,
        count: params.count,
        eraHint: params.eraHint,
        vibeHint: params.vibeHint,
        gender: c.gender,
        model: textGen.model,
        maxTokens: textGen.params.maxLength,
      );
      if (!mounted) return;
      if (outfits.isEmpty) {
        snack(this.context.l.charsNoOutfitsReturned, tone: AppTone.warning);
        return;
      }
      // Auto-assign primary if exactly one came back flagged.
      await lib.addOutfits(c.id, outfits.map((p) => p.outfit).toList());
      final primaryCandidates = outfits.where((p) => p.isPrimary).toList();
      if (primaryCandidates.length == 1 && c.primaryOutfitId == null) {
        await lib.setPrimaryOutfit(c.id, primaryCandidates.first.outfit.id);
      }
      snack(this.context.l.charsOutfitsAdded(outfits.length));
    } catch (e) {
      snack(this.context.l.charsGenerationFailed('$e'), tone: AppTone.error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _generating = false;
        });
      }
    }
  }
}

class _OutfitCard extends StatelessWidget {
  final ClosetOutfit outfit;
  final bool isPrimary;
  final bool isSelected;
  final bool touch;
  final VoidCallback onTapState;
  final VoidCallback onWear;
  final VoidCallback onEdit;
  final VoidCallback onSetPrimary;
  final VoidCallback onDelete;

  const _OutfitCard({
    required this.outfit,
    required this.isPrimary,
    required this.isSelected,
    required this.touch,
    required this.onTapState,
    required this.onWear,
    required this.onEdit,
    required this.onSetPrimary,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    final rendered = (outfit.items != null && outfit.items!.isNotEmpty)
        ? renderItemsToTags(outfit.items!.cast<String, dynamic>()).tags
        : applyConcealment(outfit.tags).tags;
    final chips = <String>[
      ...outfit.seasons,
      ...outfit.weather.take(3),
      ...outfit.activities.take(2),
      if (outfit.slots.isNotEmpty) outfit.slots.join('/'),
    ];
    return Container(
      width: touch ? null : 240,
      decoration: BoxDecoration(
        color: t.surfaceMid,
        borderRadius: BorderRadius.circular(VisionMetrics.radius8),
        border: Border.all(
          color: isSelected ? t.accent : t.borderSubtle,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(VisionMetrics.space12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    outfit.name,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: t.fontSize(12),
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: l.charsSetPrimary,
                  onPressed: onSetPrimary,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints.tightFor(
                    width: context.hitSize,
                    height: context.hitSize,
                  ),
                  iconSize: VisionMetrics.iconMedium,
                  color: isPrimary ? t.accentFavorite : t.textMinimal,
                  icon: Icon(isPrimary ? Icons.star : Icons.star_border),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              rendered.isEmpty ? outfit.tags : rendered,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.textTertiary, fontSize: t.fontSize(9)),
            ),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: VisionMetrics.space4,
                runSpacing: VisionMetrics.space4,
                children: [
                  for (final ch in chips) AppPill(text: ch, dense: true),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                _miniBtn(
                  context,
                  l.charsWear.toUpperCase(),
                  onWear,
                  accent: true,
                ),
                const SizedBox(width: VisionMetrics.space4),
                _miniBtn(
                  context,
                  l.charsState.toUpperCase(),
                  onTapState,
                  highlighted: isSelected,
                ),
                const SizedBox(width: VisionMetrics.space4),
                _miniBtn(context, l.mainEdit.toUpperCase(), onEdit),
                const Spacer(),
                IconButton(
                  tooltip: l.charsDeleteOutfitTitle,
                  onPressed: onDelete,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints.tightFor(
                    width: context.hitSize,
                    height: context.hitSize,
                  ),
                  iconSize: VisionMetrics.iconMedium,
                  color: t.accentDanger,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniBtn(
    BuildContext context,
    String label,
    VoidCallback onTap, {
    bool accent = false,
    bool highlighted = false,
  }) {
    final t = context.t;
    final color = accent
        ? t.accent
        : (highlighted ? t.accentEdit : t.textTertiary);
    return InkWell(
      onTap: onTap,
      borderRadius: VisionMetrics.borderRadius4,
      child: Container(
        constraints: BoxConstraints(minHeight: context.hitSize),
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(
          horizontal: touch ? VisionMetrics.space12 : VisionMetrics.space8,
        ),
        decoration: BoxDecoration(
          color: color.withValues(
            alpha: highlighted
                ? VisionMetrics.opacityPressed
                : VisionMetrics.opacityHover,
          ),
          borderRadius: VisionMetrics.borderRadius4,
          border: Border.all(
            color: color.withValues(alpha: VisionMetrics.opacityDisabled),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: t.fontSize(touch ? 10 : 8),
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
