import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_metrics.dart';
import '../providers/generation_notifier.dart';
import '../models/nai_character.dart';
import 'character_chip.dart';
import 'character_editor_sheet.dart';
import 'action_interaction_sheet.dart';
import 'chip_actions.dart';

class CharacterShelf extends StatelessWidget {
  const CharacterShelf({super.key});

  void _openEditor(
    BuildContext context,
    GenerationNotifier notifier,
    int index,
    NaiCharacter character,
  ) {
    showSelfPaddedSheet(
      context: context,
      builder: (context) => CharacterEditorSheet(
        index: index,
        character: character,
        onSave: (updated) => notifier.updateCharacter(index, updated),
        onDelete: () => notifier.removeCharacter(index),
      ),
    );
  }

  void _openInteractionEditor(
    BuildContext context,
    GenerationNotifier notifier,
    int index1,
    int index2,
  ) {
    // Find existing interaction involving these two characters
    final existing = notifier.state.interactions
        .cast<NaiInteraction?>()
        .firstWhere(
          (i) =>
              i != null &&
              ((i.sourceCharacterIndices.contains(index1) &&
                      i.targetCharacterIndices.contains(index2)) ||
                  (i.sourceCharacterIndices.contains(index2) &&
                      i.targetCharacterIndices.contains(index1)) ||
                  (i.type == InteractionType.mutual &&
                      i.sourceCharacterIndices.contains(index1) &&
                      i.sourceCharacterIndices.contains(index2))),
          orElse: () => null,
        );

    showSelfPaddedSheet(
      context: context,
      builder: (context) => ActionInteractionSheet(
        sourceIndices: existing?.sourceCharacterIndices ?? [index1],
        targetIndices: existing?.targetCharacterIndices ?? [index2],
        initialType: existing?.type ?? InteractionType.sourceTarget,
        characters: notifier.state.characters,
        initialInteraction: existing,
        onSave: (updated) =>
            notifier.updateInteraction(updated, replacing: existing),
        onDelete: () {
          if (existing != null) notifier.removeInteraction(existing);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Selector<
      GenerationNotifier,
      (List<NaiCharacter>, List<NaiInteraction>, bool)
    >(
      selector: (_, n) =>
          (n.state.characters, n.state.interactions, n.state.autoPositioning),
      builder: (context, data, _) {
        final notifier = context.read<GenerationNotifier>();
        final characters = data.$1;
        final interactions = data.$2;
        final autoPositioning = data.$3;

        // Total items: [autoChip] + char1, link1-2, char2, link2-3, ..., charN, [addButton]
        final hasAutoChip = characters.isNotEmpty;
        int itemCount = characters.isNotEmpty ? (characters.length * 2) - 1 : 0;
        if (hasAutoChip) itemCount += 1; // AUTO chip
        if (characters.length < 6) {
          itemCount += 1; // Add character button
        }

        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: Container(
            height: context.hitSize,
            margin: const EdgeInsets.symmetric(vertical: VisionMetrics.space4),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: itemCount,
              itemBuilder: (context, index) {
                // AUTO chip is the first item when characters exist
                if (hasAutoChip && index == 0) {
                  return _AutoPositionChip(
                    isActive: autoPositioning,
                    onTap: () => notifier.setAutoPositioning(!autoPositioning),
                  );
                }

                // Adjust index for the AUTO chip offset
                final adjustedIndex = hasAutoChip ? index - 1 : index;

                // Check if it's the "Add Character" button
                if (characters.length < 6 && index == itemCount - 1) {
                  return _AddCharacterButton(onTap: notifier.addCharacter);
                }

                // Even indices are character chips (0, 2, 4...)
                // Odd indices are link buttons (1, 3, 5...)
                if (adjustedIndex.isEven) {
                  final charIndex = adjustedIndex ~/ 2;
                  return CharacterChip(
                    index: charIndex,
                    character: characters[charIndex],
                    onTap: () => _openEditor(
                      context,
                      notifier,
                      charIndex,
                      characters[charIndex],
                    ),
                    onLongPress: () {
                      final name = characters[charIndex].name.isNotEmpty
                          ? characters[charIndex].name
                          : context.l.charEditorCharacterN(charIndex + 1);
                      showChipActions(
                        context,
                        title: name,
                        onDelete: () => notifier.removeCharacter(charIndex),
                        deleteMessage: context.l.charEditorDeleteConfirm(name),
                      );
                    },
                  );
                } else {
                  final charIndex1 = adjustedIndex ~/ 2;
                  final charIndex2 = charIndex1 + 1;
                  final hasInteraction = interactions.any(
                    (i) =>
                        (i.sourceCharacterIndices.contains(charIndex1) &&
                            i.targetCharacterIndices.contains(charIndex2)) ||
                        (i.sourceCharacterIndices.contains(charIndex2) &&
                            i.targetCharacterIndices.contains(charIndex1)) ||
                        (i.type == InteractionType.mutual &&
                            i.sourceCharacterIndices.contains(charIndex1) &&
                            i.sourceCharacterIndices.contains(charIndex2)),
                  );

                  return _LinkButton(
                    isActive: hasInteraction,
                    onTap: () => _openInteractionEditor(
                      context,
                      notifier,
                      charIndex1,
                      charIndex2,
                    ),
                  );
                }
              },
            ),
          ),
        );
      },
    );
  }
}

class _LinkButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;

  const _LinkButton({required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: context.hitSize / 2,
        height: context.hitSize,
        child: Center(
          child: Icon(
            Icons.link,
            size: VisionMetrics.iconMedium,
            color: isActive ? t.accentSuccess : t.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _AutoPositionChip extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;

  const _AutoPositionChip({required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.only(right: VisionMetrics.space8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VisionMetrics.radius4),
        child: Container(
          height: context.hitSize,
          padding: const EdgeInsets.symmetric(horizontal: VisionMetrics.space8),
          decoration: BoxDecoration(
            color: isActive ? t.accentCharacter : t.borderSubtle,
            borderRadius: BorderRadius.circular(VisionMetrics.radius4),
            border: Border.all(
              color: isActive ? t.accentCharacter : t.textMinimal,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            'AUTO',
            style: TextStyle(
              color: isActive ? t.background : t.textDisabled,
              fontSize: t.fontSize(9),
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _AddCharacterButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddCharacterButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VisionMetrics.space4),
      child: Tooltip(
        message: context.l.charEditorAddCharacter,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(VisionMetrics.radius4),
          child: Container(
            width: context.hitSize,
            decoration: BoxDecoration(
              color: t.textMinimal,
              borderRadius: BorderRadius.circular(VisionMetrics.radius4),
              border: Border.all(color: t.textMinimal),
            ),
            child: Icon(
              Icons.add,
              size: VisionMetrics.iconMedium,
              color: t.textDisabled,
            ),
          ),
        ),
      ),
    );
  }
}
