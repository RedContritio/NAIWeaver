import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../../core/services/kv_store.dart';
import '../models/closet_outfit.dart';

/// CRUD for a character's closet — a JSON ARRAY of outfits at
/// `<charactersDir>/{characterId}/closet.json`. Same atomic-write pattern as
/// the preset/style storage; one file holds the whole closet.
class ClosetService {
  final String charactersDir;

  ClosetService({required this.charactersDir});

  String _path(String characterId) =>
      p.join(charactersDir, characterId, 'closet.json');
  String _prefsKey(String characterId) => 'character_closet_$characterId';

  Future<List<ClosetOutfit>> load(String characterId) async {
    try {
      final raw = await KvStore.readString(
        path: _path(characterId),
        prefsKey: _prefsKey(characterId),
      );
      if (raw == null) return [];
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((m) => ClosetOutfit.fromJson(m.cast<String, dynamic>()))
          .toList();
    } catch (e) {
      debugPrint('ClosetService: load failed for $characterId: $e');
      return [];
    }
  }

  Future<void> saveAll(String characterId, List<ClosetOutfit> outfits) async {
    try {
      await KvStore.writeString(
        path: _path(characterId),
        prefsKey: _prefsKey(characterId),
        value: jsonEncode(outfits.map((o) => o.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('ClosetService: save failed for $characterId: $e');
      rethrow;
    }
  }
}
