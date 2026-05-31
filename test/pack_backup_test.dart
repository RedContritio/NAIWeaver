import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/pack_service.dart';
import 'package:naiweaver/core/theme/app_theme_config.dart';
import 'package:naiweaver/features/gallery/models/gallery_album.dart';
import 'package:naiweaver/features/generation/models/character_preset.dart';

void main() {
  group('PackService portable-backup round-trip', () {
    test('preserves character presets', () {
      final originals = [
        CharacterPreset(id: 'c1', name: 'Hero', prompt: '1boy, armor', uc: 'blurry'),
        CharacterPreset(id: 'c2', name: 'Mage', prompt: '1girl, robe', uc: ''),
      ];

      final bytes = PackService.exportPack(name: 'test', characterPresets: originals);
      final imported = PackService.importPack(bytes);

      expect(imported.characterPresets.length, 2);
      expect(imported.manifest.characterPresetCount, 2);
      final sorted = [...imported.characterPresets]..sort((a, b) => a.id.compareTo(b.id));
      expect(sorted[0].id, 'c1');
      expect(sorted[0].name, 'Hero');
      expect(sorted[0].prompt, '1boy, armor');
      expect(sorted[0].uc, 'blurry');
    });

    test('preserves user themes (color + scale fields survive)', () {
      final theme = const AppThemeConfig(
        id: 'user_123',
        name: 'Neon',
        isBuiltIn: false,
        accent: Color(0xFF00FFAA),
        fontScale: 1.15,
      );

      final bytes = PackService.exportPack(name: 'test', userThemes: [theme]);
      final imported = PackService.importPack(bytes);

      expect(imported.userThemes.length, 1);
      expect(imported.manifest.userThemeCount, 1);
      final round = imported.userThemes.single;
      expect(round.id, 'user_123');
      expect(round.name, 'Neon');
      expect(round.accent, const Color(0xFF00FFAA));
      expect(round.fontScale, closeTo(1.15, 1e-9));
    });

    test('preserves gallery albums including membership', () {
      final album = GalleryAlbum(
        id: 'a1',
        name: 'Favorites',
        imageBasenames: {'img_001.png', 'img_002.png'},
      );

      final bytes = PackService.exportPack(name: 'test', galleryAlbums: [album]);
      final imported = PackService.importPack(bytes);

      expect(imported.galleryAlbums.length, 1);
      expect(imported.manifest.galleryAlbumCount, 1);
      final round = imported.galleryAlbums.single;
      expect(round.id, 'a1');
      expect(round.name, 'Favorites');
      expect(round.imageBasenames, {'img_001.png', 'img_002.png'});
    });

    test('preserves settings blob and sets hasSettings', () {
      final settings = <String, Object>{
        'furry_mode': true,
        'gallery_grid_columns': 4,
        'jukebox_volume': 0.4,
        'app_locale': 'ja',
        'settings_section_order': ['characters', 'presets'],
      };

      final bytes = PackService.exportPack(name: 'test', settings: settings);
      final imported = PackService.importPack(bytes);

      expect(imported.manifest.hasSettings, isTrue);
      expect(imported.settings['furry_mode'], true);
      expect(imported.settings['gallery_grid_columns'], 4);
      expect(imported.settings['jukebox_volume'], 0.4);
      expect(imported.settings['app_locale'], 'ja');
      expect(imported.settings['settings_section_order'], ['characters', 'presets']);
    });

    test('empty settings omits the file and leaves hasSettings false', () {
      final bytes = PackService.exportPack(name: 'test', presets: const []);
      final imported = PackService.importPack(bytes);

      expect(imported.manifest.hasSettings, isFalse);
      expect(imported.settings, isEmpty);
    });

    test('backward-compat: an old pack with none of the new categories imports cleanly', () {
      // A pack exported before the backup feature existed has no character_presets/,
      // themes/, gallery_albums/, or settings.json. Simulate by exporting with only
      // the original categories.
      final bytes = PackService.exportPack(name: 'legacy');
      final imported = PackService.importPack(bytes);

      expect(imported.characterPresets, isEmpty);
      expect(imported.userThemes, isEmpty);
      expect(imported.galleryAlbums, isEmpty);
      expect(imported.settings, isEmpty);
      expect(imported.manifest.characterPresetCount, 0);
      expect(imported.manifest.userThemeCount, 0);
      expect(imported.manifest.galleryAlbumCount, 0);
      expect(imported.manifest.hasSettings, isFalse);
    });
  });
}
