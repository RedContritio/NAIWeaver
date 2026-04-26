import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/pack_service.dart';
import 'package:naiweaver/core/services/reference_library_service.dart';
import 'package:naiweaver/features/director_ref/models/director_reference.dart';
import 'package:naiweaver/features/vibe_transfer/models/vibe_transfer.dart';

SavedDirectorRef _makeSavedRef(String name, List<int> imgBytes) {
  return SavedDirectorRef(
    name: name,
    reference: DirectorReference(
      id: 'r_$name',
      originalImageBytes: Uint8List.fromList(imgBytes),
      processedBase64: '',
      type: DirectorReferenceType.style,
      strength: 0.42,
      fidelity: 0.71,
    ),
    savedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
  );
}

SavedVibeTransfer _makeSavedVibe(String name, List<int> imgBytes) {
  return SavedVibeTransfer(
    name: name,
    vibe: VibeTransfer(
      id: 'v_$name',
      originalImageBytes: Uint8List.fromList(imgBytes),
      processedPreview: Uint8List.fromList(imgBytes),
      vibeVectorBase64: 'AAAA',
      strength: 0.33,
      infoExtracted: 0.88,
    ),
    savedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
  );
}

void main() {
  group('PackService saved refs/vibes round-trip', () {
    test('exportPack + importPack preserves saved refs', () {
      final originals = [
        _makeSavedRef('moody_lighting', [1, 2, 3, 4]),
        _makeSavedRef('cinematic', [9, 9, 9]),
      ];

      final bytes = PackService.exportPack(
        name: 'test',
        savedRefs: originals,
      );
      final imported = PackService.importPack(bytes);

      expect(imported.savedRefs.length, 2);
      // Order isn't guaranteed by archive iteration; sort by name to compare.
      final sorted = [...imported.savedRefs]
        ..sort((a, b) => a.name.compareTo(b.name));
      expect(sorted[0].name, 'cinematic');
      expect(sorted[0].reference.strength, closeTo(0.42, 1e-9));
      expect(sorted[0].reference.fidelity, closeTo(0.71, 1e-9));
      expect(sorted[0].reference.type, DirectorReferenceType.style);
      expect(sorted[1].name, 'moody_lighting');
      expect(sorted[1].reference.originalImageBytes, [1, 2, 3, 4]);

      // Manifest counts
      expect(imported.manifest.savedRefCount, 2);
    });

    test('exportPack + importPack preserves saved vibes', () {
      final originals = [_makeSavedVibe('warm_pop', [7, 8, 9])];

      final bytes = PackService.exportPack(
        name: 'test',
        savedVibes: originals,
      );
      final imported = PackService.importPack(bytes);

      expect(imported.savedVibes.length, 1);
      final round = imported.savedVibes.single;
      expect(round.name, 'warm_pop');
      expect(round.vibe.strength, closeTo(0.33, 1e-9));
      expect(round.vibe.infoExtracted, closeTo(0.88, 1e-9));
      expect(round.vibe.vibeVectorBase64, 'AAAA');
      expect(imported.manifest.savedVibeCount, 1);
    });

    test('empty saved categories produce zero counts', () {
      final bytes = PackService.exportPack(name: 'empty');
      final imported = PackService.importPack(bytes);
      expect(imported.savedRefs, isEmpty);
      expect(imported.savedVibes, isEmpty);
      expect(imported.manifest.savedRefCount, 0);
      expect(imported.manifest.savedVibeCount, 0);
    });
  });
}
