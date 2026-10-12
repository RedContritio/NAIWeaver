import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../features/director_ref/models/director_reference.dart';
import '../../features/vibe_transfer/models/vibe_transfer.dart';
import 'reference_library_store_web.dart'
    if (dart.library.io) 'reference_library_store_io.dart'
    as store;

class SavedDirectorRef {
  final String name;
  final DirectorReference reference;
  final DateTime savedAt;

  SavedDirectorRef({
    required this.name,
    required this.reference,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'reference': reference.toJson(),
        'savedAt': savedAt.toIso8601String(),
      };

  factory SavedDirectorRef.fromJson(Map<String, dynamic> json) =>
      SavedDirectorRef(
        name: json['name'] as String,
        reference:
            DirectorReference.fromJson(json['reference'] as Map<String, dynamic>),
        savedAt: DateTime.parse(json['savedAt'] as String),
      );
}

class SavedVibeTransfer {
  final String name;
  final VibeTransfer vibe;
  final DateTime savedAt;

  SavedVibeTransfer({
    required this.name,
    required this.vibe,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'vibe': vibe.toJson(),
        'savedAt': savedAt.toIso8601String(),
      };

  factory SavedVibeTransfer.fromJson(Map<String, dynamic> json) =>
      SavedVibeTransfer(
        name: json['name'] as String,
        vibe: VibeTransfer.fromJson(json['vibe'] as Map<String, dynamic>),
        savedAt: DateTime.parse(json['savedAt'] as String),
      );
}

class ReferenceLibrary {
  List<SavedDirectorRef> directorRefs;
  List<SavedVibeTransfer> vibeTransfers;

  ReferenceLibrary({
    List<SavedDirectorRef>? directorRefs,
    List<SavedVibeTransfer>? vibeTransfers,
  })  : directorRefs = directorRefs ?? [],
        vibeTransfers = vibeTransfers ?? [];

  Map<String, dynamic> toJson() => {
        'directorRefs': directorRefs.map((r) => r.toJson()).toList(),
        'vibeTransfers': vibeTransfers.map((v) => v.toJson()).toList(),
      };

  factory ReferenceLibrary.fromJson(Map<String, dynamic> json) =>
      ReferenceLibrary(
        directorRefs: (json['directorRefs'] as List<dynamic>?)
                ?.map((r) => SavedDirectorRef.fromJson(r as Map<String, dynamic>))
                .toList() ??
            [],
        vibeTransfers: (json['vibeTransfers'] as List<dynamic>?)
                ?.map((v) => SavedVibeTransfer.fromJson(v as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

/// One of the two lists kept in a [ReferenceLibrary], so library UI can be
/// written once for both kinds of entry.
class ReferenceLibrarySlot<T> {
  const ReferenceLibrarySlot._(this.read, this.write);

  final List<T> Function(ReferenceLibrary library) read;
  final void Function(ReferenceLibrary library, List<T> entries) write;

  static final directorRefs = ReferenceLibrarySlot<SavedDirectorRef>._(
    (library) => library.directorRefs,
    (library, entries) => library.directorRefs = entries,
  );

  static final vibeTransfers = ReferenceLibrarySlot<SavedVibeTransfer>._(
    (library) => library.vibeTransfers,
    (library, entries) => library.vibeTransfers = entries,
  );
}

class ReferenceLibraryService {
  /// Web builds before IndexedDB kept the library under this
  /// SharedPreferences key; it is still read as a fallback and dropped after
  /// the first successful save.
  static const String _legacyPrefsKey = 'saved_reference_library';

  static Future<ReferenceLibrary> _read(String filePath) async {
    final raw = await store.readLibrary(filePath, _legacyPrefsKey);
    if (raw == null) return ReferenceLibrary();
    return ReferenceLibrary.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Loads the library for display; an unreadable library shows as empty.
  static Future<ReferenceLibrary> load(String filePath) async {
    try {
      return await _read(filePath);
    } catch (e) {
      debugPrint('ReferenceLibraryService: load error: $e');
      return ReferenceLibrary();
    }
  }

  /// Writes [library]; returns false when it could not be stored (e.g. the
  /// storage quota is exhausted), so callers never report a lost save as
  /// saved.
  static Future<bool> save(String filePath, ReferenceLibrary library) async {
    try {
      await store.writeLibrary(
        filePath,
        _legacyPrefsKey,
        jsonEncode(library.toJson()),
      );
      return true;
    } catch (e) {
      debugPrint('ReferenceLibraryService: save error: $e');
      return false;
    }
  }

  /// Loads the stored library, applies [change] and saves it. Returns the
  /// saved library, or null when it could not be read or written; an
  /// unreadable library is never overwritten.
  static Future<ReferenceLibrary?> update(
    String filePath,
    void Function(ReferenceLibrary library) change,
  ) async {
    final ReferenceLibrary library;
    try {
      library = await _read(filePath);
    } catch (e) {
      debugPrint('ReferenceLibraryService: update read error: $e');
      return null;
    }
    change(library);
    return await save(filePath, library) ? library : null;
  }
}
