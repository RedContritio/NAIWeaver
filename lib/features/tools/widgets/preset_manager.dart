import 'dart:typed_data';
import '../../../core/utils/file_picker_helper.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_tokens.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/manager_list_tile.dart';
import '../../../core/widgets/manager_shell.dart';
import '../../../core/widgets/vision_slider.dart';
import '../../../core/widgets/tag_suggestion_overlay.dart';
import '../../../core/services/presets.dart';
import '../../director_ref/models/director_reference.dart';
import '../../director_ref/services/reference_image_processor.dart';
import '../../generation/models/nai_character.dart';
import '../../generation/providers/generation_notifier.dart';
import '../../characters/providers/character_library_notifier.dart';
import '../providers/preset_notifier.dart';

class PresetManager extends StatelessWidget {
  const PresetManager({super.key});

  @override
  Widget build(BuildContext context) {
    final genNotifier = context.watch<GenerationNotifier>();
    final charLib = context.read<CharacterLibraryNotifier>();

    return ChangeNotifierProvider(
      create: (_) => PresetNotifier(
        tagService: genNotifier.tagService,
        wildcardService: genNotifier.wildcardService,
        initialPresets: genNotifier.state.presets,
        presetsFilePath: genNotifier.presetsFilePath,
        onPresetsChanged: () => genNotifier.refreshPresets(),
        characterSuggestionsFor: (q) => charLib.suggestionTags(q),
      ),
      child: const _PresetManagerContent(),
    );
  }
}

class _PresetManagerContent extends StatefulWidget {
  const _PresetManagerContent();

  @override
  State<_PresetManagerContent> createState() => _PresetManagerContentState();
}

class _PresetManagerContentState extends State<_PresetManagerContent> {
  bool _isProcessingRef = false;
  bool _showingEditor = false;

  UnsavedChangesGuard _guard(PresetNotifier notifier) => UnsavedChangesGuard(
    hasChanges: notifier.state.isModified,
    onSave: () => _save(notifier),
    onDiscard: () => _discard(notifier),
  );

  /// Saves the edited preset, asking first when its new name is taken.
  Future<bool> _save(PresetNotifier notifier) async {
    if (notifier.hasNameConflict() && !await _confirmOverwrite(notifier)) {
      return false;
    }
    await notifier.savePreset();
    return true;
  }

  /// Drops pending edits by reloading the stored version, if there is one.
  void _discard(PresetNotifier notifier) {
    final state = notifier.state;
    notifier.selectPreset(
      state.presets.where((p) => p.name == state.originalName).firstOrNull,
    );
  }

  /// Opens the editor on [preset], or on a fresh preset when it is null,
  /// after pending edits on another preset are saved or discarded.
  Future<void> _openEditor(
    PresetNotifier notifier, [
    GenerationPreset? preset,
  ]) async {
    final editing = notifier.state.selectedPreset != null &&
        preset != null &&
        notifier.state.originalName == preset.name;
    if (!editing) {
      if (!await _guard(notifier).resolve(context) || !mounted) return;
      preset == null
          ? notifier.createNewPreset()
          : notifier.selectPreset(preset);
    }
    setState(() => _showingEditor = true);
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PresetNotifier>();
    final t = context.t;
    final l = context.l;
    final selected = notifier.state.selectedPreset;
    final modified = notifier.state.isModified;

    return ManagerMasterDetailShell(
      showDetail: _showingEditor && selected != null,
      masterHeader: ManagerHeader(
        title: l.presetManager,
        subtitle: l.presetManageDesc,
        actions: [
          if (modified)
            ManagerSaveChangesButton(onPressed: () => _save(notifier)),
        ],
      ),
      detailTitle: selected?.name.toUpperCase() ?? '',
      detailActions: [
        if (modified)
          ManagerIconButton(
            key: const ValueKey<String>('preset-mobile-save'),
            icon: Icons.save_outlined,
            tooltip: l.commonSave,
            color: t.textPrimary,
            onPressed: () => _save(notifier),
          ),
      ],
      onCloseDetail: () => setState(() => _showingEditor = false),
      guard: _guard(notifier),
      master: _buildPresetList(context, notifier, t),
      detail: _buildEditor(context, notifier, t),
    );
  }

  Widget _buildPresetList(BuildContext context, PresetNotifier notifier, VisionTokens t) {
    final l = context.l;
    final state = notifier.state;
    return ColoredBox(
      color: t.surfaceMid,
      child: Column(
        children: [
          ManagerListHeader(
            title: l.presetList,
            actions: [
              ManagerIconButton(
                icon: Icons.add,
                tooltip: l.presetNew,
                color: t.secondaryText,
                onPressed: () => _openEditor(notifier),
              ),
            ],
          ),
          Divider(height: 1, color: t.textMinimal),
          Expanded(
            child: ListView.builder(
              itemCount: state.presets.length,
              itemBuilder: (context, index) {
                final preset = state.presets[index];
                final isSelected = state.selectedPreset?.name == preset.name;
                final hasExtras = preset.characters.isNotEmpty ||
                    preset.interactions.isNotEmpty ||
                    preset.directorReferences.isNotEmpty;

                return ManagerListTile(
                  title: preset.name.toUpperCase(),
                  subtitle: !hasExtras
                      ? null
                      : preset.directorReferences.isNotEmpty
                          ? l.presetCharsRefsInfo(preset.characters.length, preset.interactions.length, preset.directorReferences.length)
                          : l.presetCharsInfo(preset.characters.length, preset.interactions.length),
                  selected: isSelected,
                  leading: Icon(
                    Icons.tune,
                    size: 12,
                    color: isSelected ? t.textPrimary : t.secondaryText,
                  ),
                  onTap: () => _openEditor(notifier, preset),
                  menuActions: [
                    ManagerListAction(
                      label: l.commonDuplicate,
                      icon: Icons.copy,
                      onSelected: () => notifier.duplicatePreset(preset),
                    ),
                    ManagerListAction(
                      label: l.commonDelete,
                      icon: Icons.delete_outline,
                      destructive: true,
                      onSelected: () => _showDeleteConfirm(context, notifier, preset, t),
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

  Widget _buildEditor(BuildContext context, PresetNotifier notifier, VisionTokens t) {
    final l = context.l;
    final state = notifier.state;
    if (state.selectedPreset == null) {
      return Center(
        child: Text(
          l.presetSelectToEdit,
          style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(9), letterSpacing: 2),
        ),
      );
    }

    return Column(
      children: [
        if (state.tagSuggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: TagSuggestionOverlay(
              suggestions: state.tagSuggestions,
              onTagSelected: notifier.applyTagSuggestion,
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle(l.presetIdentity, t),
                _buildTextField(
                  controller: notifier.nameController,
                  label: l.presetName,
                  onChanged: (val) => notifier.updateCurrentPreset(name: val),
                  t: t,
                ),
                const SizedBox(height: 24),
                _buildSectionTitle(l.presetPrompts, t),
                Focus(
                  onFocusChange: (hasFocus) {
                    if (!hasFocus) {
                      Future.delayed(const Duration(milliseconds: 200), () {
                        notifier.clearTagSuggestions();
                      });
                    }
                  },
                  child: _buildTextField(
                    controller: notifier.promptController,
                    label: l.presetPrompt,
                    maxLines: 4,
                    onChanged: (val) {
                      notifier.handleTagSuggestions(val, notifier.promptController.selection);
                      notifier.updateCurrentPreset(prompt: val);
                    },
                    t: t,
                  ),
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: notifier.negativePromptController,
                  label: l.presetNegativePrompt,
                  maxLines: 3,
                  onChanged: (val) => notifier.updateCurrentPreset(negativePrompt: val),
                  t: t,
                ),
                const SizedBox(height: 24),
                _buildSectionTitle(l.presetGenSettings, t),
                _buildSettingsGrid(context, notifier, t),
                const SizedBox(height: 24),
                _buildSectionTitle(l.presetCharsAndInteractions, t),
                _buildCharacterSection(context, notifier, t),
                const SizedBox(height: 24),
                _buildSectionTitle(l.presetReferences, t),
                _buildReferenceSection(context, notifier, t),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, VisionTokens t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title,
        style: TextStyle(color: t.textTertiary, fontSize: t.fontSize(8), letterSpacing: 2, fontWeight: FontWeight.bold),
      ),
    );
  }

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
        Text(label, style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(8), letterSpacing: 1)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLines: maxLines,
          onChanged: onChanged,
          style: TextStyle(color: t.textSecondary, fontSize: t.fontSize(13), height: 1.5),
          decoration: InputDecoration(
            filled: true,
            fillColor: t.borderSubtle,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsGrid(BuildContext context, PresetNotifier notifier, VisionTokens t) {
    final l = context.l;
    final preset = notifier.state.selectedPreset!;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSlider(
                label: l.presetWidth,
                value: preset.width,
                min: 64,
                max: 2048,
                divisions: 31,
                onChanged: (v) => notifier.updateCurrentPreset(width: v),
                t: t,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSlider(
                label: l.presetHeight,
                value: preset.height,
                min: 64,
                max: 2048,
                divisions: 31,
                onChanged: (v) => notifier.updateCurrentPreset(height: v),
                t: t,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildSlider(
                label: l.presetScale,
                value: preset.scale,
                min: 1.0,
                max: 30.0,
                divisions: 290,
                onChanged: (v) => notifier.updateCurrentPreset(scale: v),
                t: t,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSlider(
                label: l.presetSteps,
                value: preset.steps,
                min: 1,
                max: 50,
                divisions: 49,
                onChanged: (v) => notifier.updateCurrentPreset(steps: v),
                t: t,
                warnAbove: 28,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildDropdown(
                label: l.presetSampler,
                value: preset.sampler,
                items: ["k_euler_ancestral", "k_euler", "k_dpmpp_2s_ancestral", "k_dpmpp_2m", "k_dpmpp_sde"],
                onChanged: (v) => notifier.updateCurrentPreset(sampler: v),
                t: t,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 24,
          runSpacing: 8,
          children: [
            _buildToggle(label: "SMEA", value: preset.smea, onChanged: (v) => notifier.updateCurrentPreset(smea: v), t: t),
            _buildToggle(label: "SMEA DYN", value: preset.smeaDyn, onChanged: (v) => notifier.updateCurrentPreset(smeaDyn: v), t: t),
            _buildToggle(label: "DECRISPER", value: preset.decrisper, onChanged: (v) => notifier.updateCurrentPreset(decrisper: v), t: t),
          ],
        ),
      ],
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required Function(double) onChanged,
    required VisionTokens t,
    double? warnAbove,
  }) {
    final isWarning = warnAbove != null && value > warnAbove;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(8), letterSpacing: 1)),
            Text(value.toInt().toString(), style: TextStyle(color: isWarning ? t.accentDanger : t.textSecondary, fontSize: t.fontSize(9), fontWeight: FontWeight.bold)),
          ],
        ),
        VisionSlider(
          value: value,
          onChanged: onChanged,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: isWarning ? t.accentDanger.withValues(alpha: 0.4) : t.textPrimary.withValues(alpha: 0.2),
          inactiveColor: t.borderSubtle,
          thumbColor: isWarning ? t.accentDanger : t.textPrimary,
          thumbRadius: 6,
          overlayRadius: 12,
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required Function(String?) onChanged,
    required VisionTokens t,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(8), letterSpacing: 1)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: t.borderSubtle,
            borderRadius: BorderRadius.circular(4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: t.surfaceHigh,
              style: TextStyle(color: t.textSecondary, fontSize: t.fontSize(11)),
              onChanged: onChanged,
              items: items.map((String item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(item.toUpperCase()),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToggle({required String label, required bool value, required Function(bool) onChanged, required VisionTokens t}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.scale(
          scale: 0.6,
          child: SizedBox(
            height: 24,
            width: 32,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: t.textPrimary,
              activeTrackColor: t.textDisabled,
              inactiveThumbColor: t.textMinimal,
              inactiveTrackColor: t.borderSubtle,
            ),
          ),
        ),
        const SizedBox(width: 2),
        Text(label, style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(8), letterSpacing: 1)),
      ],
    );
  }

  Widget _buildCharacterSection(BuildContext context, PresetNotifier notifier, VisionTokens t) {
    final l = context.l;
    final preset = notifier.state.selectedPreset!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (preset.characters.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            decoration: BoxDecoration(
              color: t.borderSubtle,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: t.borderSubtle),
            ),
            child: Text(
              l.presetNoChars,
              style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(8), letterSpacing: 1),
              textAlign: TextAlign.center,
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: preset.characters.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final char = preset.characters[index];
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.borderSubtle,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l.presetCharacterN(index + 1),
                          style: TextStyle(color: t.textTertiary, fontSize: t.fontSize(8), fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, size: 12, color: t.textDisabled),
                          onPressed: () {
                            final updated = List<NaiCharacter>.from(preset.characters)..removeAt(index);
                            // Also cleanup interactions
                            final updatedInts = preset.interactions
                                .map((i) {
                              var sources = i.sourceCharacterIndices.where((s) => s != index).toList();
                              var targets = i.targetCharacterIndices.where((t) => t != index).toList();
                              sources = sources.map((s) => s > index ? s - 1 : s).toList();
                              targets = targets.map((t) => t > index ? t - 1 : t).toList();
                              return i.copyWith(sourceCharacterIndices: sources, targetCharacterIndices: targets);
                            }).where((i) {
                              if (i.type == InteractionType.mutual) return i.sourceCharacterIndices.isNotEmpty;
                              return i.sourceCharacterIndices.isNotEmpty && i.targetCharacterIndices.isNotEmpty;
                            }).toList();
                            notifier.updateCurrentPreset(characters: updated, interactions: updatedInts);
                          },
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildMiniTextField(
                      label: l.presetPrompt,
                      initialValue: char.prompt,
                      onChanged: (val) {
                        final updated = List<NaiCharacter>.from(preset.characters);
                        updated[index] = NaiCharacter(prompt: val, uc: char.uc, center: char.center);
                        notifier.updateCurrentPreset(characters: updated);
                      },
                      t: t,
                    ),
                    const SizedBox(height: 8),
                    _buildMiniTextField(
                      label: "UC",
                      initialValue: char.uc,
                      onChanged: (val) {
                        final updated = List<NaiCharacter>.from(preset.characters);
                        updated[index] = NaiCharacter(prompt: char.prompt, uc: val, center: char.center);
                        notifier.updateCurrentPreset(characters: updated);
                      },
                      t: t,
                    ),
                  ],
                ),
              );
            },
          ),
        const SizedBox(height: 16),
        if (preset.interactions.isNotEmpty) ...[
          Text(l.presetInteractions, style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(8), letterSpacing: 1)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: preset.interactions.map((interaction) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: t.borderSubtle,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: t.textMinimal),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      interaction.type == InteractionType.mutual
                          ? "${interaction.sourceCharacterIndices.map((i) => i + 1).join(' \u2194 ')}: ${interaction.actionName.toUpperCase()}"
                          : "${interaction.sourceCharacterIndices.map((i) => i + 1).join(',')} -> ${interaction.targetCharacterIndices.map((i) => i + 1).join(',')}: ${interaction.actionName.toUpperCase()}",
                      style: TextStyle(color: t.textSecondary, fontSize: t.fontSize(8)),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () {
                        final updated = List<NaiInteraction>.from(preset.interactions)..remove(interaction);
                        notifier.updateCurrentPreset(interactions: updated);
                      },
                      child: Icon(Icons.close, size: 10, color: t.textDisabled),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildReferenceSection(BuildContext context, PresetNotifier notifier, VisionTokens t) {
    final l = context.l;
    final preset = notifier.state.selectedPreset!;
    final refs = preset.directorReferences;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (refs.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            decoration: BoxDecoration(
              color: t.borderSubtle,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: t.borderSubtle),
            ),
            child: Text(
              l.presetNoRefs,
              style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(8), letterSpacing: 1),
              textAlign: TextAlign.center,
            ),
          )
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: refs.asMap().entries.map((entry) {
              final index = entry.key;
              final ref = entry.value;
              return Container(
                width: 140,
                decoration: BoxDecoration(
                  color: t.borderSubtle,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: t.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Thumbnail
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          child: Image.memory(
                            ref.originalImageBytes,
                            width: 140,
                            height: 100,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                        ),
                        // Type badge
                        Positioned(
                          top: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: t.background.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              ref.type.label,
                              style: TextStyle(color: t.textSecondary, fontSize: t.fontSize(7), letterSpacing: 0.5),
                            ),
                          ),
                        ),
                        // Remove button
                        Positioned(
                          top: 2,
                          right: 2,
                          child: InkWell(
                            onTap: () {
                              final updated = List<DirectorReference>.from(refs)..removeAt(index);
                              notifier.updateCurrentPreset(directorReferences: updated);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: t.background.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: Icon(Icons.close, size: 10, color: t.textSecondary),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Info labels
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "STR ${ref.strength.toStringAsFixed(1)}",
                            style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(7), letterSpacing: 0.5),
                          ),
                          Text(
                            "FID ${ref.fidelity.toStringAsFixed(1)}",
                            style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(7), letterSpacing: 0.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _isProcessingRef ? null : () => _addReference(notifier),
          icon: _isProcessingRef
              ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1, color: t.textDisabled))
              : Icon(Icons.add_photo_alternate_outlined, size: 14, color: t.textDisabled),
          label: Text(
            _isProcessingRef ? l.presetProcessing : l.presetAddReference,
            style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(8), letterSpacing: 1),
          ),
          style: TextButton.styleFrom(
            backgroundColor: t.borderSubtle,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ],
    );
  }

  Future<void> _addReference(PresetNotifier notifier) async {
    final result = await pickImageFiles(withData: true);
    if (result == null || result.files.single.bytes == null) return;

    setState(() => _isProcessingRef = true);
    try {
      final bytes = result.files.single.bytes!;
      final (_, base64) = await ReferenceImageProcessor.processImage(bytes);
      final ref = DirectorReference(
        id: 'ref_preset_${DateTime.now().millisecondsSinceEpoch}',
        originalImageBytes: Uint8List.fromList(bytes),
        processedBase64: base64,
      );
      final currentRefs = notifier.state.selectedPreset?.directorReferences ?? [];
      notifier.updateCurrentPreset(
        directorReferences: List<DirectorReference>.from(currentRefs)..add(ref),
      );
    } catch (e) {
      debugPrint('Failed to process reference image: $e');
    } finally {
      setState(() => _isProcessingRef = false);
    }
  }

  Widget _buildMiniTextField({required String label, required String initialValue, required Function(String) onChanged, required VisionTokens t}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(7), letterSpacing: 1)),
        const SizedBox(height: 2),
        TextField(
          controller: TextEditingController(text: initialValue)..selection = TextSelection.collapsed(offset: initialValue.length),
          onChanged: onChanged,
          style: TextStyle(color: t.textSecondary, fontSize: t.fontSize(10)),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Colors.black26,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(2), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
        ),
      ],
    );
  }

  Future<void> _showDeleteConfirm(BuildContext context, PresetNotifier notifier, GenerationPreset preset, VisionTokens t) async {
    final l = context.l;
    final confirm = await showConfirmDialog(
      context,
      title: l.presetDeleteTitle,
      message: l.presetDeleteConfirm(preset.name),
      confirmLabel: l.commonDelete,
      confirmColor: t.accentDanger,
    );
    if (confirm == true) {
      notifier.deletePreset(preset);
    }
  }

  Future<bool> _confirmOverwrite(PresetNotifier notifier) async {
    final l = context.l;
    final confirm = await showConfirmDialog(
      context,
      title: l.presetOverwriteTitle,
      message: l.presetOverwriteConfirm(notifier.nameController.text),
      confirmLabel: l.commonOverwrite,
      confirmColor: context.tRead.textPrimary,
    );
    return confirm == true;
  }
}
