import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/gateway/backend_permissions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_tokens.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/color_picker_dialog.dart';
import '../../../core/widgets/confirm_dialog.dart';
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
    final mobile = isMobile(context);

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

    if (mobile) {
      // On mobile: list, then editor pushed.
      if (selected == null) {
        return _buildListPane(context, t, lib, filtered, isMobile: true);
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
          width: 260,
          child: _buildListPane(context, t, lib, filtered, isMobile: false),
        ),
        VerticalDivider(width: 1, color: t.borderMedium),
        Expanded(
          child: selected == null
              ? Center(
                  child: Text(
                    'Select or create a character',
                    style: TextStyle(
                      color: t.textTertiary,
                      fontSize: t.fontSize(12),
                    ),
                  ),
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
      showAppSnackBar(context, 'Character generated'.toUpperCase());
    } else if (notifier.lastError != null) {
      showErrorSnackBar(context, notifier.lastError!);
    }
  }

  Widget _buildListPane(
    BuildContext context,
    VisionTokens t,
    CharacterLibraryNotifier lib,
    List<SavedCharacter> filtered, {
    required bool isMobile,
  }) {
    final rowVerticalPad = isMobile ? 14.0 : 10.0;
    final rowHorizontalPad = isMobile ? 14.0 : 12.0;
    return Container(
      color: t.surfaceMid,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
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
                      hintText: 'Search…',
                      hintStyle: TextStyle(
                        color: t.textMinimal,
                        fontSize: t.fontSize(10),
                      ),
                      isDense: true,
                      prefixIcon: Icon(
                        Icons.search,
                        size: 16,
                        color: t.textMinimal,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: t.borderSubtle),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Builder(
                  builder: (ctx) {
                    final canGen =
                        ctx.watch<CharacterGenNotifier>().hasService &&
                        hasBackendPermission(
                          ctx,
                          BackendPermission.textGenerate,
                        );
                    return IconButton(
                      tooltip: canGen
                          ? 'Generate a character'
                          : 'Requires text generation (set an API key first)',
                      icon: Icon(
                        Icons.auto_awesome,
                        color: canGen ? t.accent : t.textMinimal,
                        size: 18,
                      ),
                      onPressed: canGen ? () => _generateCharacter(ctx) : null,
                    );
                  },
                ),
                IconButton(
                  tooltip: 'New character',
                  icon: Icon(Icons.add, color: t.accent, size: 20),
                  onPressed: () async {
                    final c = await lib.createCharacter('New Character');
                    setState(() => _selectedId = c.id);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No characters yet',
                      style: TextStyle(
                        color: t.textMinimal,
                        fontSize: t.fontSize(10),
                      ),
                    ),
                  )
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
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            c.name.isEmpty
                                                ? '(unnamed)'
                                                : c.name,
                                            style: TextStyle(
                                              color: isSel
                                                  ? t.textPrimary
                                                  : t.textSecondary,
                                              fontSize: t.fontSize(
                                                isMobile ? 13 : 12,
                                              ),
                                              fontWeight: isSel
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (outfitCount > 0) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 5,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: t.background.withValues(
                                                alpha: 0.4,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              '$outfitCount',
                                              style: TextStyle(
                                                color: t.textMinimal,
                                                fontSize: t.fontSize(8),
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
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
                                            const SizedBox(width: 6),
                                            Container(
                                              width: 6,
                                              height: 6,
                                              decoration: BoxDecoration(
                                                color: t.accentDanger,
                                                borderRadius:
                                                    BorderRadius.circular(3),
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

  void _applyToPrompt(String tags, bool dishevelled) {
    if (tags.trim().isEmpty) return;
    final gen = context.read<GenerationNotifier>();
    final ctrl = gen.promptController;
    final text = ctrl.text;
    final sel = ctrl.selection;
    final pos = sel.isValid ? sel.baseOffset : text.length;
    final before = text.substring(0, pos);
    final after = text.substring(pos);
    final needComma =
        before.trim().isNotEmpty && !before.trimRight().endsWith(',');
    final insert =
        '${needComma ? ', ' : ''}$tags${dishevelled ? ', nsfw' : ''}, ';
    final newBefore = before + insert;
    ctrl.value = TextEditingValue(
      text: newBefore + after,
      selection: TextSelection.collapsed(offset: newBefore.length),
    );
    showAppSnackBar(context, 'Added to prompt'.toUpperCase());
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (widget.onBack != null)
                IconButton(
                  icon: Icon(
                    Icons.arrow_back,
                    size: 18,
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
                    hintText: 'Character name',
                    hintStyle: TextStyle(color: t.textMinimal),
                  ),
                  onSubmitted: (_) => _save(lib),
                ),
              ),
              IconButton(
                tooltip: 'Photoshoot',
                icon: Icon(
                  Icons.photo_camera_outlined,
                  size: 18,
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
                tooltip: 'Save',
                icon: Icon(Icons.save_outlined, size: 18, color: t.accent),
                onPressed: () => _save(lib),
              ),
              IconButton(
                tooltip: 'Delete character',
                icon: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: t.accentDanger,
                ),
                onPressed: () async {
                  final ok = await showConfirmDialog(
                    context,
                    title: 'Delete character',
                    message: 'Delete "${c.name}" and its wardrobe?',
                    confirmLabel: 'Delete',
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
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'GENDER',
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
                              g.isEmpty ? '(unspecified)' : g,
                              style: TextStyle(fontSize: t.fontSize(11)),
                            ),
                          ),
                      ],
                    ),
                    const Spacer(),
                    ..._themeSwatches(t, c, lib),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'IDENTITY TAGS — no clothing here',
                  style: TextStyle(
                    color: t.textTertiary,
                    fontSize: t.fontSize(8),
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                TagTextField(
                  controller: _base,
                  label: 'base — 1girl/1boy, ethnicity, age, permanent marks',
                  minLines: 1,
                  maxLines: 3,
                ),
                const SizedBox(height: 10),
                TagTextField(
                  controller: _face,
                  label: 'face — eye colour/shape, brows, nose, lips',
                  minLines: 1,
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                TagTextField(
                  controller: _hair,
                  label: 'hair — colour, length, style, texture',
                  minLines: 1,
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                TagTextField(
                  controller: _body,
                  label: 'body — build, proportions, chest',
                  minLines: 1,
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                TagTextField(
                  controller: _negativeTags,
                  label:
                      'negative — injected into the UC when this character is used',
                  minLines: 1,
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                _expander(
                  t,
                  'NSFW sub-buckets (optional)',
                  _showNsfw,
                  () => setState(() => _showNsfw = !_showNsfw),
                ),
                if (_showNsfw) ...[
                  const SizedBox(height: 8),
                  TagTextField(
                    controller: _nsfwTop,
                    label: 'nsfw top',
                    minLines: 1,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  TagTextField(
                    controller: _nsfwBottom,
                    label: 'nsfw bottom',
                    minLines: 1,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  TagTextField(
                    controller: _nsfwAlways,
                    label: 'nsfw always',
                    minLines: 1,
                    maxLines: 2,
                  ),
                ],
                const SizedBox(height: 10),
                _expander(
                  t,
                  'Style identity & description (optional)',
                  _showStyle,
                  () => setState(() => _showStyle = !_showStyle),
                ),
                if (_showStyle) ...[
                  const SizedBox(height: 8),
                  TagTextField(
                    controller: _artist,
                    label: 'artist tag',
                    minLines: 1,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 8),
                  TagTextField(
                    controller: _stylePrefix,
                    label: 'style prefix',
                    minLines: 1,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 8),
                  _plainField(
                    t,
                    'character description (natural language; not used by NAI image gen)',
                    _description,
                    maxLines: 3,
                  ),
                ],
                const SizedBox(height: 10),
                _expander(
                  t,
                  'Personality / soul (optional)',
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
                  _plainField(
                    t,
                    'soul — long-form personality doc (not used by image gen)',
                    _soul,
                    maxLines: 14,
                  ),
                ],
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: t.surfaceMid,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: t.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'COMBINED TAGS (preview — body + primary outfit)',
                        style: TextStyle(
                          color: t.textTertiary,
                          fontSize: t.fontSize(8),
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        combined.isEmpty ? '(empty)' : combined,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: t.fontSize(11),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _WardrobeSection(
                  characterId: c.id,
                  selectedOutfitId: _selectedOutfitId,
                  onSelectOutfit: (id) =>
                      setState(() => _selectedOutfitId = id),
                  onApplyToPrompt: _applyToPrompt,
                ),
                if (selectedOutfit != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: t.surfaceMid,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: t.borderSubtle),
                    ),
                    child: OutfitStatePanel(
                      key: ValueKey('state_${selectedOutfit.id}'),
                      outfit: selectedOutfit,
                      onChanged: (updated) => lib.updateOutfit(c.id, updated),
                      onApplyToPrompt: _applyToPrompt,
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
    Widget swatch(String label, String? hex, void Function(String?) set) {
      final col = hex != null ? _parseHex(hex) : null;
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Tooltip(
          message: label,
          child: InkWell(
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
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: col ?? Colors.transparent,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: t.borderMedium),
              ),
              child: col == null
                  ? Icon(Icons.add, size: 12, color: t.textMinimal)
                  : null,
            ),
          ),
        ),
      );
    }

    return [
      Text(
        'TINT',
        style: TextStyle(
          color: t.textTertiary,
          fontSize: t.fontSize(8),
          letterSpacing: 1.5,
        ),
      ),
      swatch(
        'accent',
        c.themeAccent,
        (h) => lib.updateCharacter(c.copyWith(themeAccent: h)),
      ),
      swatch(
        'accent 2',
        c.themeAccentSecondary,
        (h) => lib.updateCharacter(c.copyWith(themeAccentSecondary: h)),
      ),
      swatch(
        'bg',
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              open ? Icons.expand_less : Icons.expand_more,
              size: 16,
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
  final void Function(String tags, bool dishevelled) onApplyToPrompt;

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
  bool _generating = false;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final lib = context.watch<CharacterLibraryNotifier>();
    final closet = lib.closetFor(widget.characterId);
    final c = lib.characterById(widget.characterId);
    final textGen = context.watch<TextGenNotifier>();
    final hasTextGen =
        textGen.hasService &&
        hasBackendPermission(context, BackendPermission.textGenerate);
    final mobile = isMobile(context);

    final generateButton = Tooltip(
      message: hasTextGen
          ? 'Generate outfits with text generation'
          : 'Requires text generation (set an API key in Text Gen settings)',
      child: TextButton.icon(
        onPressed: (!hasTextGen || _generating)
            ? null
            : () => _generate(context, lib, c),
        icon: _generating
            ? SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: t.accent,
                ),
              )
            : Icon(
                Icons.auto_awesome,
                size: 14,
                color: hasTextGen ? t.accent : t.textMinimal,
              ),
        label: Text(
          _generating ? 'GENERATING…' : '✨ GENERATE OUTFITS',
          style: TextStyle(fontSize: t.fontSize(9), letterSpacing: 1),
        ),
      ),
    );
    final newOutfitButton = TextButton.icon(
      onPressed: () => _newOutfit(context, lib),
      icon: Icon(Icons.add, size: 14, color: t.accent),
      label: Text(
        'NEW OUTFIT',
        style: TextStyle(fontSize: t.fontSize(9), letterSpacing: 1),
      ),
    );
    final title = Text(
      'WARDROBE',
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
        // On mobile the title + both action buttons overflow a single row and
        // truncate the labels, so let the buttons wrap onto their own line.
        if (mobile)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            spacing: 6,
            runSpacing: 4,
            children: [
              title,
              Wrap(spacing: 6, children: [generateButton, newOutfitButton]),
            ],
          )
        else
          Row(
            children: [
              title,
              const Spacer(),
              generateButton,
              const SizedBox(width: 6),
              newOutfitButton,
            ],
          ),
        const SizedBox(height: 8),
        if (closet.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No outfits yet — add one or generate a set.',
              style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(10)),
            ),
          )
        else if (mobile)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final o in closet) ...[
                _OutfitCard(
                  outfit: o,
                  isPrimary: c?.primaryOutfitId == o.id,
                  isSelected: widget.selectedOutfitId == o.id,
                  mobile: true,
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
                const SizedBox(height: 8),
              ],
            ],
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final o in closet)
                _OutfitCard(
                  outfit: o,
                  isPrimary: c?.primaryOutfitId == o.id,
                  isSelected: widget.selectedOutfitId == o.id,
                  mobile: false,
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
    widget.onApplyToPrompt(combined, r.isDishevelled);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    CharacterLibraryNotifier lib,
    ClosetOutfit o,
  ) async {
    final t = context.t;
    final ok = await showConfirmDialog(
      context,
      title: 'Delete outfit',
      message: 'Delete "${o.name}"?',
      confirmLabel: 'Delete',
      confirmColor: t.accentDanger,
    );
    if (ok == true) {
      if (widget.selectedOutfitId == o.id) widget.onSelectOutfit(null);
      await lib.deleteOutfit(widget.characterId, o.id);
    }
  }

  void _newOutfit(BuildContext context, CharacterLibraryNotifier lib) {
    final draft = ClosetOutfit.create(name: 'New Outfit');
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
    if (c == null) return;
    final textGen = context.read<TextGenNotifier>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    void snack(String msg, {Color? color}) {
      if (messenger == null) return;
      messenger.showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: color),
      );
    }

    final params = await WardrobeGenerateDialog.show(context);
    if (params == null) return;
    final service = textGen.service;
    if (service == null) {
      snack('TEXT GENERATION NOT CONFIGURED', color: Colors.orange);
      return;
    }
    setState(() => _generating = true);
    try {
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
      if (outfits.isEmpty) {
        snack('NO OUTFITS RETURNED', color: Colors.orange);
        return;
      }
      // Auto-assign primary if exactly one came back flagged.
      await lib.addOutfits(c.id, outfits.map((p) => p.outfit).toList());
      final primaryCandidates = outfits.where((p) => p.isPrimary).toList();
      if (primaryCandidates.length == 1 && c.primaryOutfitId == null) {
        await lib.setPrimaryOutfit(c.id, primaryCandidates.first.outfit.id);
      }
      snack('ADDED ${outfits.length} OUTFIT(S)');
    } catch (e) {
      snack('Generation failed: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }
}

class _OutfitCard extends StatelessWidget {
  final ClosetOutfit outfit;
  final bool isPrimary;
  final bool isSelected;
  final bool mobile;
  final VoidCallback onTapState;
  final VoidCallback onWear;
  final VoidCallback onEdit;
  final VoidCallback onSetPrimary;
  final VoidCallback onDelete;

  const _OutfitCard({
    required this.outfit,
    required this.isPrimary,
    required this.isSelected,
    required this.mobile,
    required this.onTapState,
    required this.onWear,
    required this.onEdit,
    required this.onSetPrimary,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
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
      width: mobile ? null : 240,
      decoration: BoxDecoration(
        color: t.surfaceMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSelected ? t.accent : t.borderSubtle,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
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
                InkWell(
                  onTap: onSetPrimary,
                  child: Icon(
                    isPrimary ? Icons.star : Icons.star_border,
                    size: 16,
                    color: isPrimary ? t.accentFavorite : t.textMinimal,
                  ),
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
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final ch in chips)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: t.background.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        ch,
                        style: TextStyle(
                          color: t.textMinimal,
                          fontSize: t.fontSize(7.5),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                _miniBtn(t, 'WEAR', onWear, accent: true),
                const SizedBox(width: 4),
                _miniBtn(t, 'STATE', onTapState, highlighted: isSelected),
                const SizedBox(width: 4),
                _miniBtn(t, 'EDIT', onEdit),
                const Spacer(),
                InkWell(
                  onTap: onDelete,
                  child: Padding(
                    padding: EdgeInsets.all(mobile ? 6 : 2),
                    child: Icon(
                      Icons.delete_outline,
                      size: mobile ? 18 : 14,
                      color: t.accentDanger,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniBtn(
    VisionTokens t,
    String label,
    VoidCallback onTap, {
    bool accent = false,
    bool highlighted = false,
  }) {
    final color = accent
        ? t.accent
        : (highlighted ? t.accentEdit : t.textTertiary);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: mobile ? 10 : 6,
          vertical: mobile ? 8 : 3,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: highlighted ? 0.2 : 0.1),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: t.fontSize(mobile ? 10 : 8),
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
