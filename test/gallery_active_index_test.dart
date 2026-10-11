import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/features/gallery/providers/gallery_notifier.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a saved result is found by basename, not assumed at index 0', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
    final dir = await Directory.systemTemp.createTemp('c3_gallery_');
    addTearDown(() => dir.delete(recursive: true));
    final png = File('assets/logo.png').readAsBytesSync();
    for (final name in ['a.png', 'd.png']) {
      File(p.join(dir.path, name)).writeAsBytesSync(png);
    }

    final gallery = GalleryNotifier(outputDir: dir.path, prefs: prefs);
    await gallery.refresh();

    final saved = File(p.join(dir.path, 'NAI_UP_a_120000.png'))
      ..writeAsBytesSync(png);
    gallery.addFile(saved, DateTime.now());

    // Name-descending order puts the new image last, not at index 0.
    gallery.setSortMode(GallerySortMode.nameDesc);
    expect(gallery.activeItems.first.basename, 'd.png');
    expect(gallery.activeIndexOf('NAI_UP_a_120000.png'), 2);

    // Only favorites shown: the new image is hidden, not "the first one".
    gallery.toggleFavorite(
      gallery.items.firstWhere((i) => i.basename == 'a.png'),
    );
    gallery.showFavoritesOnly = true;
    expect(gallery.activeIndexOf('NAI_UP_a_120000.png'), isNull);
    expect(gallery.activeIndexOf('a.png'), 0);
  });
}
