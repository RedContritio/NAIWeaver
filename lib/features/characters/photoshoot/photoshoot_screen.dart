import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_tokens.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../gallery/providers/gallery_notifier.dart';
import '../../generation/providers/generation_notifier.dart';
import '../models/closet_outfit.dart';
import '../models/saved_character.dart';
import '../outfit/outfit_renderer.dart';
import '../outfit/widgets/outfit_state_panel.dart';
import '../providers/character_library_notifier.dart';

/// A single-screen photoshoot mode: pick a saved character + outfit, dress them
/// in-place ephemerally, pick style/pose/environment, preview the assembled
/// prompt, and kick the existing image-gen pipeline.
///
/// Working outfit state is session-only — the saved closet is untouched unless
/// the user taps "Save state to outfit".
class PhotoshootScreen extends StatefulWidget {
  final String characterId;
  final String initialOutfitId;

  const PhotoshootScreen({
    super.key,
    required this.characterId,
    required this.initialOutfitId,
  });

  @override
  State<PhotoshootScreen> createState() => _PhotoshootScreenState();
}

class _PhotoshootScreenState extends State<PhotoshootScreen> {
  /// Working copy of the outfit — mutations here do NOT auto-persist. They are
  /// written back to the library only via `_saveStateToOutfit`.
  ClosetOutfit? _workingOutfit;

  String? _selectedOutfitId;

  String? _selectedStyle; // artist-tag bundle id, or null
  final Set<String> _selectedPoseIds = {};
  final Set<String> _selectedEnvIds = {};
  final TextEditingController _customPoseCtrl = TextEditingController();
  final TextEditingController _customEnvCtrl = TextEditingController();

  List<_PresetEntry> _poses = const [];
  List<_PresetEntry> _environments = const [];
  bool _presetsLoaded = false;
  bool _previewExpanded = true;

  @override
  void initState() {
    super.initState();
    _selectedOutfitId = widget.initialOutfitId;
    _loadPresets();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_workingOutfit == null && _selectedOutfitId != null) {
      final lib = context.read<CharacterLibraryNotifier>();
      _workingOutfit = lib
          .closetFor(widget.characterId)
          .where((o) => o.id == _selectedOutfitId)
          .firstOrNull;
    }
  }

  @override
  void dispose() {
    _customPoseCtrl.dispose();
    _customEnvCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPresets() async {
    try {
      final posesJson = await rootBundle.loadString('assets/photoshoot/poses.json');
      final envsJson = await rootBundle.loadString('assets/photoshoot/environments.json');
      final poses = (jsonDecode(posesJson) as List)
          .cast<Map<String, dynamic>>()
          .map(_PresetEntry.fromJson)
          .toList();
      final envs = (jsonDecode(envsJson) as List)
          .cast<Map<String, dynamic>>()
          .map(_PresetEntry.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _poses = poses;
        _environments = envs;
        _presetsLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _presetsLoaded = true);
    }
  }

  void _selectOutfit(ClosetOutfit outfit) {
    setState(() {
      _selectedOutfitId = outfit.id;
      _workingOutfit = outfit;
    });
  }

  Future<void> _saveStateToOutfit() async {
    final outfit = _workingOutfit;
    if (outfit == null) return;
    final lib = context.read<CharacterLibraryNotifier>();
    await lib.updateOutfit(widget.characterId, outfit);
    if (!mounted) return;
    showAppSnackBar(context, 'OUTFIT STATE SAVED');
  }

  String _assembledPrompt(SavedCharacter character, ClosetOutfit? outfit) {
    final parts = <String>[];

    final styleTags = _styleTagsFor(_selectedStyle, character);
    if (styleTags.isNotEmpty) parts.add(styleTags);

    final body = character.derivedBodyTags;
    if (body.isNotEmpty) parts.add(body);

    bool dishevelled = false;
    if (outfit != null) {
      final items = outfit.items;
      if (items != null && items.isNotEmpty) {
        final r = renderItemsToTags(items.cast<String, dynamic>());
        if (r.tags.isNotEmpty) parts.add(r.tags);
        dishevelled = r.isDishevelled;
      } else if (outfit.tags.trim().isNotEmpty) {
        final r = applyConcealment(outfit.tags);
        if (r.tags.isNotEmpty) parts.add(r.tags);
        dishevelled = r.isDishevelled;
      }
    }

    final poseTags = _collectPresetTags(_poses, _selectedPoseIds, _customPoseCtrl.text);
    if (poseTags.isNotEmpty) parts.add(poseTags);

    final envTags = _collectPresetTags(_environments, _selectedEnvIds, _customEnvCtrl.text);
    if (envTags.isNotEmpty) parts.add(envTags);

    if (dishevelled) parts.add('nsfw');
    return parts.join(', ');
  }

  String _styleTagsFor(String? id, SavedCharacter character) {
    if (id == null) return '';
    if (id == 'character') return character.artistTag.trim();
    final found = _kStyleBundles.firstWhere(
      (b) => b.id == id,
      orElse: () => const _StyleBundle(id: '', label: '', tags: ''),
    );
    return found.tags;
  }

  String _collectPresetTags(
      List<_PresetEntry> presets, Set<String> selected, String custom) {
    final picks = <String>[];
    for (final p in presets) {
      if (selected.contains(p.id)) picks.add(p.tags);
    }
    final c = custom.trim();
    if (c.isNotEmpty) picks.add(c);
    return picks.join(', ');
  }

  Future<void> _generate(String prompt) async {
    if (prompt.isEmpty) return;
    final gen = context.read<GenerationNotifier>();
    gen.promptController.text = prompt;
    try {
      await gen.generate();
      if (!mounted) return;
      showAppSnackBar(context, 'GENERATED');
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, 'GENERATION FAILED: $e');
    }
  }

  void _sendToMainPrompt(String prompt) {
    if (prompt.isEmpty) return;
    final gen = context.read<GenerationNotifier>();
    gen.promptController.text = prompt;
    Navigator.of(context).pop();
    showAppSnackBar(context, 'SENT TO MAIN PROMPT');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final lib = context.watch<CharacterLibraryNotifier>();
    final character = lib.characterById(widget.characterId);
    if (character == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Photoshoot')),
        body: const Center(child: Text('Character not found')),
      );
    }
    final closet = lib.closetFor(widget.characterId);
    final outfit = _workingOutfit ??
        closet.where((o) => o.id == _selectedOutfitId).firstOrNull ??
        (closet.isNotEmpty ? closet.first : null);
    final assembled = _assembledPrompt(character, outfit);

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        backgroundColor: t.surfaceHigh,
        iconTheme: IconThemeData(color: t.textSecondary),
        title: Text(
          'PHOTOSHOOT',
          style: TextStyle(
              color: t.textSecondary,
              fontSize: t.fontSize(13),
              letterSpacing: 2,
              fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerPickers(t, character, closet, outfit),
              const SizedBox(height: 12),
              if (outfit != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: t.surfaceMid,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: t.borderSubtle),
                  ),
                  child: OutfitStatePanel(
                    key: ValueKey('photoshoot_state_${outfit.id}'),
                    outfit: outfit,
                    persistent: false,
                    onChanged: (updated) =>
                        setState(() => _workingOutfit = updated),
                    // Apply-to-prompt routes through the assembled prompt path
                    // instead of writing into the controller directly — keeps
                    // the photoshoot prompt self-contained.
                    onApplyToPrompt: (_, _) {},
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _saveStateToOutfit,
                    icon: Icon(Icons.save_outlined, size: 14, color: t.accent),
                    label: Text('SAVE STATE TO OUTFIT',
                        style: TextStyle(
                            color: t.accent,
                            fontSize: t.fontSize(9),
                            letterSpacing: 1)),
                  ),
                ),
              ] else
                _emptyHint(t, 'No outfit to dress — add one from the character editor.'),
              const SizedBox(height: 12),
              _stylePicker(t, character),
              const SizedBox(height: 12),
              _presetSection(
                t,
                title: 'POSE',
                presets: _poses,
                selected: _selectedPoseIds,
                customCtrl: _customPoseCtrl,
                hint: 'custom pose tags…',
              ),
              const SizedBox(height: 12),
              _presetSection(
                t,
                title: 'ENVIRONMENT',
                presets: _environments,
                selected: _selectedEnvIds,
                customCtrl: _customEnvCtrl,
                hint: 'custom environment tags…',
              ),
              const SizedBox(height: 14),
              _assembledPreview(t, assembled),
              const SizedBox(height: 14),
              _actionsRow(t, assembled),
              const SizedBox(height: 16),
              _outputStrip(t),
            ],
          ),
        ),
      ),
    );
  }

  // -- Pieces ---------------------------------------------------------------

  Widget _headerPickers(VisionTokens t, SavedCharacter character,
      List<ClosetOutfit> closet, ClosetOutfit? outfit) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surfaceHigh,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CHARACTER',
              style: TextStyle(
                  color: t.textTertiary,
                  fontSize: t.fontSize(8),
                  letterSpacing: 1.5)),
          const SizedBox(height: 2),
          Text(character.name,
              style: TextStyle(
                  color: t.textPrimary,
                  fontSize: t.fontSize(16),
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('OUTFIT',
              style: TextStyle(
                  color: t.textTertiary,
                  fontSize: t.fontSize(8),
                  letterSpacing: 1.5)),
          const SizedBox(height: 4),
          InkWell(
            onTap: closet.isEmpty ? null : () => _pickOutfit(closet, outfit),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: t.surfaceMid,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: t.borderSubtle),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(outfit?.name ?? '(no outfit)',
                        style: TextStyle(
                            color: outfit == null ? t.textMinimal : t.textPrimary,
                            fontSize: t.fontSize(12))),
                  ),
                  if (closet.length > 1)
                    Icon(Icons.expand_more, size: 18, color: t.textTertiary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickOutfit(List<ClosetOutfit> closet, ClosetOutfit? current) async {
    final t = context.tRead;
    final chosen = await showModalBottomSheet<ClosetOutfit>(
      context: context,
      backgroundColor: t.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Text('OUTFIT',
                    style: TextStyle(
                        color: t.textTertiary,
                        fontSize: t.fontSize(9),
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold)),
              ),
              for (final o in closet)
                InkWell(
                  onTap: () => Navigator.of(ctx).pop(o),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: t.borderSubtle)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(o.name,
                              style: TextStyle(
                                  color: t.textPrimary,
                                  fontSize: t.fontSize(13),
                                  fontWeight: o.id == current?.id
                                      ? FontWeight.bold
                                      : FontWeight.normal)),
                        ),
                        if (o.id == current?.id)
                          Icon(Icons.check, size: 18, color: t.accent),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (chosen != null && chosen.id != current?.id) _selectOutfit(chosen);
  }

  Widget _stylePicker(VisionTokens t, SavedCharacter character) {
    final hasCharacterArtist = character.artistTag.trim().isNotEmpty;
    final bundles = <_StyleBundle>[
      if (hasCharacterArtist)
        _StyleBundle(
            id: 'character',
            label: 'Character default',
            tags: character.artistTag.trim()),
      ..._kStyleBundles,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('STYLE',
            style: TextStyle(
                color: t.textTertiary,
                fontSize: t.fontSize(8),
                letterSpacing: 1.5,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _chip(t, 'none', selected: _selectedStyle == null,
                onTap: () => setState(() => _selectedStyle = null)),
            for (final b in bundles)
              _chip(t, b.label,
                  selected: _selectedStyle == b.id,
                  onTap: () => setState(() => _selectedStyle = b.id)),
          ],
        ),
      ],
    );
  }

  Widget _presetSection(
    VisionTokens t, {
    required String title,
    required List<_PresetEntry> presets,
    required Set<String> selected,
    required TextEditingController customCtrl,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title,
                style: TextStyle(
                    color: t.textTertiary,
                    fontSize: t.fontSize(8),
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            if (!_presetsLoaded)
              SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: t.accent)),
          ],
        ),
        const SizedBox(height: 6),
        if (presets.isEmpty && _presetsLoaded)
          Text('No presets available',
              style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(9)))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in presets)
                _chip(t, p.label,
                    selected: selected.contains(p.id),
                    onTap: () => setState(() {
                          if (selected.contains(p.id)) {
                            selected.remove(p.id);
                          } else {
                            selected.add(p.id);
                          }
                        })),
            ],
          ),
        const SizedBox(height: 8),
        TextField(
          controller: customCtrl,
          style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(12)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: t.textMinimal, fontSize: t.fontSize(11)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: t.borderSubtle),
                borderRadius: BorderRadius.circular(4)),
            focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: t.accent),
                borderRadius: BorderRadius.circular(4)),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _chip(VisionTokens t, String label,
      {required bool selected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? t.accent.withValues(alpha: 0.25) : t.surfaceMid,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? t.accent : t.borderSubtle,
              width: selected ? 1.5 : 1),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? t.accent : t.textSecondary,
                fontSize: t.fontSize(10),
                fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  Widget _assembledPreview(VisionTokens t, String assembled) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: t.surfaceMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _previewExpanded = !_previewExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Row(
                children: [
                  Icon(_previewExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 16, color: t.textTertiary),
                  const SizedBox(width: 4),
                  Text('ASSEMBLED PROMPT',
                      style: TextStyle(
                          color: t.textTertiary,
                          fontSize: t.fontSize(8),
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          if (_previewExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: SelectableText(
                assembled.isEmpty ? '(empty)' : assembled,
                style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(11)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _actionsRow(VisionTokens t, String assembled) {
    final canGen = assembled.isNotEmpty;
    final gen = context.watch<GenerationNotifier>();
    final loading = gen.state.isLoading;
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: (canGen && !loading) ? () => _generate(assembled) : null,
            icon: loading
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: t.accent),
                  )
                : const Icon(Icons.auto_awesome, size: 16),
            label: Text(loading ? 'GENERATING…' : 'GENERATE',
                style: TextStyle(fontSize: t.fontSize(11), letterSpacing: 1)),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.accent,
              foregroundColor: t.surfaceHigh,
              elevation: 0,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: canGen ? () => _sendToMainPrompt(assembled) : null,
            icon: Icon(Icons.exit_to_app, size: 14, color: t.accent),
            label: Text('SEND',
                style: TextStyle(
                    color: t.accent,
                    fontSize: t.fontSize(10),
                    letterSpacing: 1)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: t.accent),
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
      ],
    );
  }

  Widget _outputStrip(VisionTokens t) {
    final gallery = context.watch<GalleryNotifier>();
    final recent = gallery.items.take(8).toList();
    if (recent.isEmpty) {
      return _emptyHint(t, 'Generated images will appear here.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('RECENT',
            style: TextStyle(
                color: t.textTertiary,
                fontSize: t.fontSize(8),
                letterSpacing: 1.5,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: recent.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final f = recent[i].file;
              return ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.file(
                  f,
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 96,
                    height: 96,
                    color: t.surfaceMid,
                    child: Icon(Icons.broken_image, color: t.textMinimal),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _emptyHint(VisionTokens t, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(text,
          style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(10))),
    );
  }
}

class _PresetEntry {
  final String id;
  final String label;
  final String tags;

  const _PresetEntry({required this.id, required this.label, required this.tags});

  factory _PresetEntry.fromJson(Map<String, dynamic> json) {
    return _PresetEntry(
      id: json['id'] as String,
      label: json['label'] as String,
      tags: json['tags'] as String,
    );
  }
}

class _StyleBundle {
  final String id;
  final String label;
  final String tags;
  const _StyleBundle({required this.id, required this.label, required this.tags});
}

/// A small set of curated artist-tag bundles. Intentionally short; users pick
/// or override per-character via the artistTag field.
const List<_StyleBundle> _kStyleBundles = [
  _StyleBundle(id: 'anime', label: 'Anime', tags: 'anime coloring'),
  _StyleBundle(id: 'painterly', label: 'Painterly', tags: 'painterly, soft brush'),
  _StyleBundle(id: 'photoreal', label: 'Photoreal', tags: 'realistic, photorealistic'),
  _StyleBundle(id: 'sketch', label: 'Sketch', tags: 'sketch, pencil drawing'),
  _StyleBundle(id: 'watercolor', label: 'Watercolour', tags: 'watercolor (medium), traditional media'),
  _StyleBundle(id: 'ink', label: 'Ink', tags: 'ink (medium), monochrome'),
];
