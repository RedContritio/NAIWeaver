import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/reference_library_service.dart';
import 'package:naiweaver/features/vibe_transfer/models/vibe_transfer.dart';

SavedVibeTransfer _saved(String name) => SavedVibeTransfer(
  name: name,
  savedAt: DateTime(2026),
  vibe: VibeTransfer(
    id: 'vibe_0',
    originalImageBytes: Uint8List.fromList([1, 2, 3]),
    processedPreview: Uint8List(0),
    vibeVectorBase64: 'vec',
  ),
);

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('naiweaver_library'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('update saves and returns the new library', () async {
    final path = '${dir.path}/reference_library.json';

    final saved = await ReferenceLibraryService.update(
      path,
      (library) => library.vibeTransfers = [...library.vibeTransfers, _saved('a')],
    );

    expect(saved?.vibeTransfers.map((v) => v.name), ['a']);
    final reloaded = await ReferenceLibraryService.load(path);
    expect(reloaded.vibeTransfers.single.name, 'a');
  });

  test('a write that cannot be stored reports failure', () async {
    // The parent "directory" is a file, so the library cannot be written.
    final blocker = File('${dir.path}/blocker')..writeAsStringSync('x');
    final path = '${blocker.path}/reference_library.json';

    expect(await ReferenceLibraryService.save(path, ReferenceLibrary()), isFalse);
    expect(
      await ReferenceLibraryService.update(path, (library) {
        library.vibeTransfers = [_saved('lost')];
      }),
      isNull,
    );
  });

  test('an unreadable library is never overwritten by an update', () async {
    final file = File('${dir.path}/reference_library.json')
      ..writeAsStringSync('{not json');

    final result = await ReferenceLibraryService.update(
      file.path,
      (library) => library.vibeTransfers = [_saved('a')],
    );

    expect(result, isNull);
    expect(file.readAsStringSync(), '{not json');
  });
}
