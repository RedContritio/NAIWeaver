import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// One wiki entry — a description (markdown) plus the tag's "other names"
/// (Japanese / aliases shown in the detail UI).
@immutable
class WikiEntry {
  final String tag;
  final String description;
  final List<String> otherNames;

  const WikiEntry({
    required this.tag,
    required this.description,
    this.otherNames = const [],
  });
}

/// Lazy-loaded lookup service for Danbooru wiki descriptions.
///
/// The asset (`Tags/wiki-descriptions.json`) is ~14 MB and ~25k entries.
/// We deliberately do NOT load it at app startup — only on first tag-detail
/// open, on a background isolate via [compute] so the UI never jank.
///
/// Source: https://huggingface.co/datasets/isek-ai/danbooru-wiki-2024
/// License: CC-BY-SA-4.0 (see Tags/LICENSE-WIKI.txt)
class WikiService {
  static const String _assetPath = 'Tags/wiki-descriptions.json';

  Map<String, WikiEntry>? _byTag;
  Future<void>? _loadFuture;

  bool get isLoaded => _byTag != null;

  /// Triggers loading if not already in flight. Safe to call repeatedly.
  Future<void> ensureLoaded() {
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    try {
      final raw = await rootBundle.loadString(_assetPath);
      _byTag = await compute(_parse, raw);
      debugPrint('Loaded ${_byTag!.length} wiki entries');
    } catch (e) {
      debugPrint('Wiki asset load failed: $e');
      _byTag = const {};
    }
  }

  /// Returns the entry for [tag] (case-insensitive, spaces preserved).
  /// Returns null if not loaded yet OR if the tag has no wiki entry.
  WikiEntry? lookup(String tag) {
    final map = _byTag;
    if (map == null) return null;
    return map[tag.toLowerCase().trim()];
  }
}

Map<String, WikiEntry> _parse(String jsonString) {
  final List<dynamic> decoded = jsonDecode(jsonString);
  final out = <String, WikiEntry>{};
  for (final item in decoded) {
    final m = item as Map<String, dynamic>;
    final t = (m['t'] as String).toLowerCase();
    out[t] = WikiEntry(
      tag: m['t'] as String,
      description: m['d'] as String? ?? '',
      otherNames: (m['n'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList(growable: false) ??
          const [],
    );
  }
  return out;
}
