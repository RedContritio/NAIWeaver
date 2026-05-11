import 'package:flutter/foundation.dart';
import '../../../core/services/tag_service.dart';
import '../models/closet_outfit.dart';
import '../models/saved_character.dart';
import '../outfit/outfit_classifier.dart';
import '../outfit/outfit_renderer.dart';
import '../services/character_library_service.dart';
import '../services/closet_service.dart';

/// One autocomplete entry derived from a saved character (a bare `[Name]` or
/// `[Name (Outfit)]`), carrying the pre-expanded tag string to insert.
class CharacterSuggestion {
  /// Display label, e.g. "Yuki" or "Yuki (Rainy Day Chic)".
  final String label;

  /// The text inserted at the cursor when picked (body tags + outfit tags run
  /// through concealment, comma-joined; `nsfw` appended if dishevelled).
  final String expansion;

  /// For ranking — the character's name lowercased.
  final String nameKey;

  const CharacterSuggestion({
    required this.label,
    required this.expansion,
    required this.nameKey,
  });
}

/// Owns the saved-character library + each character's closet. The UI and the
/// tag-autocomplete path both depend on this notifier so they react to changes.
class CharacterLibraryNotifier extends ChangeNotifier {
  final CharacterLibraryService _service;
  final ClosetService _closetService;

  CharacterLibraryNotifier({
    required CharacterLibraryService service,
    required ClosetService closetService,
  })  : _service = service,
        _closetService = closetService;

  List<SavedCharacter> _characters = [];
  final Map<String, List<ClosetOutfit>> _closets = {};
  bool _loaded = false;

  List<SavedCharacter> get characters => List.unmodifiable(_characters);
  bool get isLoaded => _loaded;

  SavedCharacter? characterById(String id) {
    for (final c in _characters) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Returns the (possibly empty) closet for [characterId]. Loads lazily and
  /// caches; callers that need a guaranteed-fresh load should call
  /// [loadCloset].
  List<ClosetOutfit> closetFor(String characterId) =>
      List.unmodifiable(_closets[characterId] ?? const <ClosetOutfit>[]);

  Future<void> loadAll() async {
    _characters = await _service.loadAll();
    _closets.clear();
    for (final c in _characters) {
      _closets[c.id] = await _closetService.load(c.id);
    }
    _loaded = true;
    notifyListeners();
  }

  Future<List<ClosetOutfit>> loadCloset(String characterId) async {
    final list = await _closetService.load(characterId);
    _closets[characterId] = list;
    notifyListeners();
    return list;
  }

  Future<SavedCharacter> createCharacter(String name) async {
    final c = SavedCharacter.create(name: name.trim().isEmpty ? 'New Character' : name.trim());
    await _service.save(c);
    _characters = [..._characters, c]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _closets[c.id] = [];
    notifyListeners();
    return c;
  }

  Future<void> updateCharacter(SavedCharacter updated) async {
    final c = updated.copyWith(updatedAt: DateTime.now());
    await _service.save(c);
    _characters = [
      for (final existing in _characters) if (existing.id == c.id) c else existing
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
  }

  Future<void> deleteCharacter(String id) async {
    await _service.delete(id);
    _characters = _characters.where((c) => c.id != id).toList();
    _closets.remove(id);
    notifyListeners();
  }

  // -- Closet mutations -----------------------------------------------------

  Future<void> _persistCloset(String characterId) async {
    await _closetService.saveAll(characterId, _closets[characterId] ?? const <ClosetOutfit>[]);
  }

  Future<ClosetOutfit> addOutfit(String characterId, ClosetOutfit outfit) async {
    final list = [...(_closets[characterId] ?? const <ClosetOutfit>[]), outfit];
    _closets[characterId] = list;
    await _persistCloset(characterId);
    notifyListeners();
    return outfit;
  }

  Future<void> addOutfits(String characterId, List<ClosetOutfit> outfits) async {
    final list = [...(_closets[characterId] ?? const <ClosetOutfit>[]), ...outfits];
    _closets[characterId] = list;
    await _persistCloset(characterId);
    notifyListeners();
  }

  Future<void> updateOutfit(String characterId, ClosetOutfit outfit) async {
    final list = [
      for (final o in (_closets[characterId] ?? const <ClosetOutfit>[])) if (o.id == outfit.id) outfit else o
    ];
    _closets[characterId] = list;
    await _persistCloset(characterId);
    notifyListeners();
  }

  Future<void> deleteOutfit(String characterId, String outfitId) async {
    _closets[characterId] =
        (_closets[characterId] ?? const <ClosetOutfit>[]).where((o) => o.id != outfitId).toList();
    // If we just removed the primary, clear the pointer on the character.
    final c = characterById(characterId);
    if (c != null && c.primaryOutfitId == outfitId) {
      await updateCharacter(c.copyWith(primaryOutfitId: null));
    }
    await _persistCloset(characterId);
    notifyListeners();
  }

  Future<void> setPrimaryOutfit(String characterId, String? outfitId) async {
    final c = characterById(characterId);
    if (c == null) return;
    await updateCharacter(c.copyWith(primaryOutfitId: outfitId));
  }

  /// Returns the outfit considered "primary" for autocomplete: the explicitly
  /// flagged one, else the first in the closet, else null.
  ClosetOutfit? primaryOutfitFor(String characterId) {
    final list = _closets[characterId] ?? const <ClosetOutfit>[];
    if (list.isEmpty) return null;
    final c = characterById(characterId);
    if (c?.primaryOutfitId != null) {
      for (final o in list) {
        if (o.id == c!.primaryOutfitId) return o;
      }
    }
    return list.first;
  }

  // -- Autocomplete -------------------------------------------------------

  /// Expands a character + optional outfit into the tag string to insert.
  /// Uses the outfit's persisted `items` state if present (so an in-progress
  /// outfit-state shows through), otherwise [applyConcealment] on the flat tags.
  String expansionFor(SavedCharacter c, ClosetOutfit? outfit) {
    final body = c.derivedBodyTags;
    String outfitTags = '';
    bool dishevelled = false;
    if (outfit != null) {
      final items = outfit.items;
      if (items != null && items.isNotEmpty) {
        final r = renderItemsToTags(items.cast<String, dynamic>());
        outfitTags = r.tags;
        dishevelled = r.isDishevelled;
      } else if (outfit.tags.trim().isNotEmpty) {
        final r = applyConcealment(outfit.tags);
        outfitTags = r.tags;
        dishevelled = r.isDishevelled;
      }
    }
    final parts = <String>[
      if (c.stylePrefix.trim().isNotEmpty) c.stylePrefix.trim(),
      if (body.isNotEmpty) body,
      if (outfitTags.trim().isNotEmpty) outfitTags.trim(),
      if (c.artistTag.trim().isNotEmpty) c.artistTag.trim(),
      if (dishevelled) 'nsfw',
    ];
    return parts.join(', ');
  }

  /// All autocomplete entries whose character name (or name+outfit) contains
  /// [query] (case-insensitive). Returns both a bare `[Name]` entry (→ primary
  /// outfit) and one entry per closet outfit.
  List<CharacterSuggestion> matchingSuggestions(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = <CharacterSuggestion>[];
    for (final c in _characters) {
      final nameKey = c.name.toLowerCase();
      final closet = _closets[c.id] ?? const <ClosetOutfit>[];
      final nameMatches = nameKey.contains(q);
      // Bare [Name] → primary outfit.
      if (nameMatches) {
        final primary = primaryOutfitFor(c.id);
        out.add(CharacterSuggestion(
          label: c.name,
          expansion: expansionFor(c, primary),
          nameKey: nameKey,
        ));
      }
      // One entry per outfit.
      for (final o in closet) {
        final outfitLabel = '${c.name} (${o.name})';
        if (nameMatches || outfitLabel.toLowerCase().contains(q)) {
          out.add(CharacterSuggestion(
            label: outfitLabel,
            expansion: expansionFor(c, o),
            nameKey: nameKey,
          ));
        }
      }
    }
    return out;
  }

  /// Convenience for the tag-autocomplete path: matching saved-character
  /// entries as [DanbooruTag]s (`typeName == 'saved_character'`, `expansion`
  /// set), capped at [limit].
  List<DanbooruTag> suggestionTags(String query, {int limit = 8}) {
    return matchingSuggestions(query)
        .take(limit)
        .map((s) => DanbooruTag(
              tag: s.label,
              count: 0,
              typeName: 'saved_character',
              expansion: s.expansion,
            ))
        .toList();
  }

  /// Re-classifies an outfit's tags into a fresh intact items state and
  /// persists it. Returns the updated outfit.
  Future<ClosetOutfit> reparseOutfit(String characterId, ClosetOutfit outfit) async {
    final items = classifyOutfitTags(outfit.tags);
    final updated = outfit.copyWith(items: items.isEmpty ? null : items, fresh: false);
    await updateOutfit(characterId, updated);
    return updated;
  }
}
