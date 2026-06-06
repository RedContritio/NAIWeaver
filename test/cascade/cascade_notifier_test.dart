import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:naiweaver/features/generation/models/nai_character.dart';
import 'package:naiweaver/features/tools/cascade/models/cascade_beat.dart';
import 'package:naiweaver/features/tools/cascade/models/prompt_cascade.dart';
import 'package:naiweaver/features/tools/cascade/providers/cascade_notifier.dart';

/// A distinct 1-byte preview per beat so we can assert which beat each preview
/// ends up attached to after a structural change.
Uint8List _preview(int tag) => Uint8List.fromList([tag]);

CascadeBeat _beat() => CascadeBeat(
      characterSlots: [BeatCharacterSlot(position: NaiCoordinate(x: 2, y: 2))],
      environmentTags: '',
    );

PromptCascade _cascade(int beatCount) => PromptCascade(
      name: 'test',
      characterCount: 1,
      beats: List.generate(beatCount, (_) => _beat()),
    );

/// Seeds a notifier with [beatCount] beats and a preview+caption on each,
/// tagged by index so re-association is observable.
CascadeNotifier _seeded(int beatCount) {
  final n = CascadeNotifier();
  n.setActiveCascade(_cascade(beatCount));
  for (var i = 0; i < beatCount; i++) {
    n.setBeatPreview(i, _preview(i));
    n.setBeatCaption(i, 'caption-$i');
  }
  return n;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('CascadeNotifier cast-time map remapping', () {
    test('removeBeat drops the removed beat and shifts later entries down', () {
      final n = _seeded(4); // beats 0,1,2,3 each with preview/caption tagged by index
      n.removeBeat(1);

      final s = n.state;
      expect(s.activeCascade!.beats.length, 3);
      // Old beat 0 unchanged; old beats 2,3 slide into slots 1,2.
      expect(s.beatPreviews[0], _preview(0));
      expect(s.beatPreviews[1], _preview(2));
      expect(s.beatPreviews[2], _preview(3));
      expect(s.beatPreviews.containsKey(3), isFalse);
      expect(s.beatCaptions[0], 'caption-0');
      expect(s.beatCaptions[1], 'caption-2');
      expect(s.beatCaptions[2], 'caption-3');
      expect(s.beatCaptions.containsKey(3), isFalse);
    });

    test('cloneBeat shifts later entries up and leaves the new slot empty', () {
      final n = _seeded(3); // beats 0,1,2
      n.cloneBeat(0); // insert clone at index 1

      final s = n.state;
      expect(s.activeCascade!.beats.length, 4);
      // Slot 0 keeps its preview; slot 1 (the clone) is un-generated; old 1,2
      // move to slots 2,3.
      expect(s.beatPreviews[0], _preview(0));
      expect(s.beatPreviews.containsKey(1), isFalse);
      expect(s.beatPreviews[2], _preview(1));
      expect(s.beatPreviews[3], _preview(2));
      expect(s.beatCaptions[0], 'caption-0');
      expect(s.beatCaptions.containsKey(1), isFalse);
      expect(s.beatCaptions[2], 'caption-1');
      expect(s.beatCaptions[3], 'caption-2');
    });

    test('reorderBeats carries each beat\'s preview to its new position', () {
      final n = _seeded(3); // beats 0,1,2
      // Move beat 0 to the end (ReorderableListView convention: newIndex past end).
      n.reorderBeats(0, 3);

      final s = n.state;
      // Resulting beat order is [1, 2, 0]; previews must follow.
      expect(s.beatPreviews[0], _preview(1));
      expect(s.beatPreviews[1], _preview(2));
      expect(s.beatPreviews[2], _preview(0));
      expect(s.beatCaptions[0], 'caption-1');
      expect(s.beatCaptions[1], 'caption-2');
      expect(s.beatCaptions[2], 'caption-0');
    });
  });

  group('CascadeNotifier.applySceneToAllBeats', () {
    test('copies the scene tags onto every beat', () {
      final n = CascadeNotifier();
      n.setActiveCascade(_cascade(3));
      n.applySceneToAllBeats('hugging, wide shot');

      for (final beat in n.state.activeCascade!.beats) {
        expect(beat.sceneTags, 'hugging, wide shot');
      }
    });
  });
}
