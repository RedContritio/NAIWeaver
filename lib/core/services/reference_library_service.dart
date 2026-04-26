import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../features/director_ref/models/director_reference.dart';
import '../../features/vibe_transfer/models/vibe_transfer.dart';
import 'kv_store.dart';

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

class ReferenceLibraryService {
  static const String _prefsKey = 'saved_reference_library';

  static Future<ReferenceLibrary> load(String filePath) async {
    try {
      final raw = await KvStore.readString(
        path: filePath,
        prefsKey: _prefsKey,
      );
      if (raw == null) return ReferenceLibrary();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return ReferenceLibrary.fromJson(json);
    } catch (e) {
      debugPrint('ReferenceLibraryService: load error: $e');
      return ReferenceLibrary();
    }
  }

  static Future<void> save(String filePath, ReferenceLibrary library) async {
    try {
      await KvStore.writeString(
        path: filePath,
        prefsKey: _prefsKey,
        value: jsonEncode(library.toJson()),
      );
    } catch (e) {
      debugPrint('ReferenceLibraryService: save error: $e');
    }
  }
}
