import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:naiweaver/core/services/reference_library_service.dart';
import 'package:naiweaver/features/director_ref/models/director_reference.dart';
import 'package:naiweaver/features/director_ref/providers/director_ref_notifier.dart';
import 'package:naiweaver/features/vibe_transfer/models/vibe_transfer.dart';
import 'package:naiweaver/features/vibe_transfer/providers/vibe_transfer_notifier.dart';

import 'test_harness.dart';

Uint8List _png() =>
    Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 6)));

DirectorReference _ref(String id, {double strength = 0.6}) => DirectorReference(
  id: id,
  originalImageBytes: Uint8List(0),
  processedBase64: 'img_$id',
  strength: strength,
);

VibeTransfer _vibe(String id) => VibeTransfer(
  id: id,
  originalImageBytes: Uint8List(0),
  processedPreview: Uint8List(0),
  vibeVectorBase64: 'vec_$id',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DirectorRefNotifier ids', () {
    test('a reference added after setReferences never reuses an id', () async {
      final notifier = DirectorRefNotifier();
      // Snapshot after ref_0 was deleted: the old counter (list length = 2)
      // would hand out ref_2 again.
      await notifier.setReferences([_ref('ref_1'), _ref('ref_2')]);

      final id = await notifier.addReference(_png());

      expect(id, isNotNull);
      final ids = notifier.references.map((r) => r.id).toList();
      expect(ids.toSet(), hasLength(3));

      // Removing the new reference must not touch the restored ones.
      notifier.removeReference(id!);
      expect(notifier.references.map((r) => r.id), ['ref_1', 'ref_2']);
    });

    test('duplicate ids inside a restored list are made unique', () async {
      final notifier = DirectorRefNotifier();
      await notifier.setReferences([
        _ref('ref_0'),
        _ref('ref_0', strength: 0.9),
      ]);

      final ids = notifier.references.map((r) => r.id).toList();
      expect(ids.toSet(), hasLength(2));

      notifier.updateStrength(ids.last, 0.3);
      expect(notifier.references.first.strength, 0.6);
      expect(notifier.references.last.strength, 0.3);
    });
  });

  group('DirectorRefNotifier.addFromSaved', () {
    SavedDirectorRef saved(Uint8List bytes) => SavedDirectorRef(
      name: 'hero',
      savedAt: DateTime(2026),
      reference: DirectorReference(
        id: 'ref_0',
        originalImageBytes: bytes,
        processedBase64: '',
        type: DirectorReferenceType.style,
        strength: 0.25,
        fidelity: 0.15,
      ),
    );

    test('applies the saved values to the new reference only', () async {
      final prefs = await testPreferences();
      final notifier = DirectorRefNotifier()
        ..setDefaults(strength: 0.9, fidelity: 0.7, prefs: prefs);
      await notifier.setReferences([_ref('ref_0')]);

      final id = await notifier.addFromSaved(saved(_png()));

      final added = notifier.references.singleWhere((r) => r.id == id);
      expect(added.type, DirectorReferenceType.style);
      expect(added.strength, 0.25);
      expect(added.fidelity, 0.15);
      // The existing (last before the add) reference is untouched.
      expect(notifier.references.first.strength, 0.6);
      expect(notifier.references.first.type, DirectorReferenceType.character);
      // Global defaults for later additions are not polluted.
      expect(notifier.defaultStrength, 0.9);
      expect(notifier.defaultFidelity, 0.7);
      expect(prefs.refLastStrength, 1.0);
      expect(prefs.refLastFidelity, 0.8);
    });

    test('a failed load changes nothing', () async {
      final notifier = DirectorRefNotifier()
        ..setDefaults(strength: 0.9, fidelity: 0.7);
      await notifier.setReferences([_ref('ref_0'), _ref('ref_1')]);
      final before = notifier.references;

      final id = await notifier.addFromSaved(
        saved(Uint8List.fromList([1, 2, 3])),
      );

      expect(id, isNull);
      expect(notifier.references, same(before));
      expect(notifier.references.last.strength, 0.6);
      expect(notifier.references.last.type, DirectorReferenceType.character);
      expect(notifier.defaultStrength, 0.9);
      expect(notifier.defaultFidelity, 0.7);
      expect(notifier.isProcessing, isFalse);
    });
  });

  group('VibeTransferNotifier ids', () {
    SavedVibeTransfer saved() => SavedVibeTransfer(
      name: 'mood',
      savedAt: DateTime(2026),
      vibe: VibeTransfer(
        id: 'vibe_0',
        originalImageBytes: Uint8List(0),
        processedPreview: Uint8List(0),
        vibeVectorBase64: 'vec',
        strength: 0.4,
        infoExtracted: 0.7,
      ),
    );

    test('loading the same saved vibe twice gives two independent vibes', () {
      final notifier = VibeTransferNotifier();
      final first = notifier.addFromSaved(saved());
      final second = notifier.addFromSaved(saved());

      expect(first, isNot(second));
      expect(notifier.vibes.map((v) => v.strength), [0.4, 0.4]);
      expect(notifier.vibes.first.infoExtracted, 0.7);

      notifier.updateStrength(second, 0.9);
      notifier.toggleEnabled(second);
      expect(notifier.vibes.first.strength, 0.4);
      expect(notifier.vibes.first.enabled, isTrue);

      notifier.removeVibe(second);
      expect(notifier.vibes.map((v) => v.id), [first]);
    });

    test('a vibe added after setVibes never reuses an id', () {
      final notifier = VibeTransferNotifier();
      notifier.setVibes([_vibe('vibe_1'), _vibe('vibe_2'), _vibe('vibe_2')]);

      expect(notifier.vibes.map((v) => v.id).toSet(), hasLength(3));
      final id = notifier.addFromSaved(saved());
      expect(notifier.vibes.map((v) => v.id).toSet(), hasLength(4));
      expect(['vibe_1', 'vibe_2'], isNot(contains(id)));
    });
  });
}
