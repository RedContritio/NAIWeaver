import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/features/generation/models/nai_character.dart';
import 'package:naiweaver/features/tools/cascade/models/cascade_beat.dart';
import 'package:naiweaver/features/tools/cascade/services/cascade_stitching_service.dart';

void main() {
  group('BeatCharacterSlot action tags', () {
    test('round-trips multiple action tags through JSON', () {
      final slot = BeatCharacterSlot(
        position: NaiCoordinate(x: 0.25, y: 0.5),
        actionTags: const ['source#hugging', 'target#kissing'],
        positivePrompt: 'smiling',
        negativePrompt: 'blurry',
      );

      final restored = BeatCharacterSlot.fromJson(slot.toJson());

      expect(restored.actionTags, ['source#hugging', 'target#kissing']);
      expect(restored.positivePrompt, 'smiling');
      expect(restored.negativePrompt, 'blurry');
      expect(restored.position.x, 0.25);
    });

    test('migrates legacy single actionTag string into a one-element list', () {
      final legacyJson = {
        'position': {'x': 0.5, 'y': 0.5},
        'actionTag': 'source#hugging',
        'positivePrompt': '',
        'negativePrompt': '',
      };

      final slot = BeatCharacterSlot.fromJson(legacyJson);

      expect(slot.actionTags, ['source#hugging']);
    });

    test('legacy empty/absent actionTag yields no tags', () {
      final emptyTag = BeatCharacterSlot.fromJson({
        'position': {'x': 0.5, 'y': 0.5},
        'actionTag': '',
      });
      final absentTag = BeatCharacterSlot.fromJson({
        'position': {'x': 0.5, 'y': 0.5},
      });

      expect(emptyTag.actionTags, isEmpty);
      expect(absentTag.actionTags, isEmpty);
    });
  });

  group('CascadeStitchingService multi-tag rendering', () {
    test('prepends every action tag before appearance and positive prompt', () {
      final beat = CascadeBeat(
        characterSlots: [
          BeatCharacterSlot(
            position: NaiCoordinate(x: 0.5, y: 0.5),
            actionTags: const ['source#hugging', 'target#kissing'],
            positivePrompt: 'smiling',
          ),
        ],
        environmentTags: 'bedroom',
      );

      final request = CascadeStitchingService.render(
        beat: beat,
        appearances: const ['1girl, blue hair'],
      );

      expect(request.characters.single.prompt,
          'source#hugging, target#kissing, 1girl, blue hair, smiling');
    });

    test('renders cleanly with no action tags', () {
      final beat = CascadeBeat(
        characterSlots: [
          BeatCharacterSlot(position: NaiCoordinate(x: 0.5, y: 0.5)),
        ],
        environmentTags: 'park',
      );

      final request = CascadeStitchingService.render(
        beat: beat,
        appearances: const ['1boy'],
      );

      expect(request.characters.single.prompt, '1boy');
    });
  });
}
