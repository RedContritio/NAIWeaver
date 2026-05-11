import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../../core/services/kv_store.dart';
import '../models/saved_character.dart';

/// CRUD for [SavedCharacter] JSON files — one file per character at
/// `<charactersDir>/{id}.json`. Mirrors the PresetStorage/StyleStorage pattern
/// (atomic-ish writes via [KvStore]) but with a file-per-thing layout.
///
/// On native we enumerate the directory; on web (no filesystem) we keep an
/// index file `<charactersDir>/_index.json` listing the ids.
class CharacterLibraryService {
  final String charactersDir;

  CharacterLibraryService({required this.charactersDir});

  String _filePath(String id) => p.join(charactersDir, '$id.json');
  String get _indexPath => p.join(charactersDir, '_index.json');
  static const String _indexPrefsKey = 'characters_index';
  String _prefsKeyFor(String id) => 'character_$id';

  Future<List<String>> _listIds() async {
    if (kIsWeb) {
      try {
        final raw = await KvStore.readString(
          path: _indexPath,
          prefsKey: _indexPrefsKey,
        );
        if (raw == null) return [];
        final list = (jsonDecode(raw) as List).whereType<String>().toList();
        return list;
      } catch (e) {
        debugPrint('CharacterLibraryService: index read failed: $e');
        return [];
      }
    }
    try {
      final dir = Directory(charactersDir);
      if (!await dir.exists()) return [];
      return dir
          .listSync()
          .whereType<File>()
          .where((f) => p.extension(f.path) == '.json' &&
              p.basenameWithoutExtension(f.path) != '_index')
          .map((f) => p.basenameWithoutExtension(f.path))
          .toList();
    } catch (e) {
      debugPrint('CharacterLibraryService: list failed: $e');
      return [];
    }
  }

  Future<void> _writeIndex(Iterable<String> ids) async {
    if (!kIsWeb) return; // native uses the directory listing
    try {
      await KvStore.writeString(
        path: _indexPath,
        prefsKey: _indexPrefsKey,
        value: jsonEncode(ids.toList()),
      );
    } catch (e) {
      debugPrint('CharacterLibraryService: index write failed: $e');
    }
  }

  /// Load all saved characters, sorted by name (case-insensitive).
  Future<List<SavedCharacter>> loadAll() async {
    final ids = await _listIds();
    final out = <SavedCharacter>[];
    for (final id in ids) {
      try {
        final raw = await KvStore.readString(
          path: _filePath(id),
          prefsKey: _prefsKeyFor(id),
        );
        if (raw == null) continue;
        final json = jsonDecode(raw) as Map<String, dynamic>;
        out.add(SavedCharacter.fromJson(json));
      } catch (e) {
        debugPrint('CharacterLibraryService: failed to load $id: $e');
      }
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  Future<void> save(SavedCharacter character) async {
    try {
      await KvStore.writeString(
        path: _filePath(character.id),
        prefsKey: _prefsKeyFor(character.id),
        value: jsonEncode(character.toJson()),
      );
      if (kIsWeb) {
        final ids = (await _listIds()).toSet()..add(character.id);
        await _writeIndex(ids);
      }
    } catch (e) {
      debugPrint('CharacterLibraryService: save failed: $e');
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    try {
      await KvStore.remove(path: _filePath(id), prefsKey: _prefsKeyFor(id));
      if (kIsWeb) {
        final ids = (await _listIds()).toSet()..remove(id);
        await _writeIndex(ids);
      } else {
        // Also remove the character's closet directory.
        try {
          final closetDir = Directory(p.join(charactersDir, id));
          if (await closetDir.exists()) {
            await closetDir.delete(recursive: true);
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('CharacterLibraryService: delete failed: $e');
      rethrow;
    }
  }
}
