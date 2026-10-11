import 'package:flutter/foundation.dart';
import '../../../core/gateway/backend_permissions.dart';
import '../../../core/services/preferences_service.dart';
import '../../../core/services/reference_library_service.dart';
import '../models/director_reference.dart';
import '../services/reference_image_processor.dart';
import 'reference_id_allocator.dart';

class DirectorRefNotifier extends ChangeNotifier {
  List<DirectorReference> _references = [];
  bool _isProcessing = false;
  final _ids = ReferenceIdAllocator('ref_');

  /// Defaults for newly added references — initially 1.0 / 0.8 but updated
  /// whenever the user adjusts a reference, so subsequent additions inherit
  /// the last-applied values.
  double _defaultStrength = 1.0;
  double _defaultFidelity = 0.8;
  PreferencesService? _prefs;
  PaidImageAccess _access = PaidImageAccess.allowed;

  List<DirectorReference> get references => _references;
  bool get isProcessing => _isProcessing;
  double get defaultStrength => _defaultStrength;
  double get defaultFidelity => _defaultFidelity;

  /// Whether the account can currently send references. Without access the
  /// references stay in the list, marked paused, and are not sent.
  PaidImageAccess get access => _access;

  /// Enabled by the user and sent: the user's own switch combined with the
  /// account's current access.
  bool isSent(DirectorReference ref) =>
      ref.enabled && _access == PaidImageAccess.allowed;

  /// References the user enabled that are held back for lack of access.
  int get pausedCount => _access == PaidImageAccess.allowed
      ? 0
      : _references.where((r) => r.enabled).length;

  int get sentCount => _references.where(isSent).length;

  void updateAccess(PaidImageAccess access) {
    if (_access == access) return;
    _access = access;
    notifyListeners();
  }

  /// Initialize last-applied defaults (typically called from PreferencesService
  /// at app startup).
  void setDefaults({
    double? strength,
    double? fidelity,
    PreferencesService? prefs,
  }) {
    if (strength != null) _defaultStrength = strength;
    if (fidelity != null) _defaultFidelity = fidelity;
    if (prefs != null) _prefs = prefs;
  }

  /// Adds a picked image with the last-applied strength and fidelity.
  /// Returns the new reference's id, or null when the image could not be
  /// processed (nothing is added then).
  Future<String?> addReference(Uint8List imageBytes) => _add(imageBytes);

  /// Adds a library entry as a new reference with the entry's own type,
  /// strength and fidelity. The saved values apply to this reference only:
  /// the defaults for later additions are left untouched. Returns the new
  /// id, or null (and leaves the list unchanged) when processing fails.
  Future<String?> addFromSaved(SavedDirectorRef saved) {
    final ref = saved.reference;
    return _add(
      ref.originalImageBytes,
      type: ref.type,
      strength: ref.strength,
      fidelity: ref.fidelity,
    );
  }

  Future<String?> _add(
    Uint8List imageBytes, {
    DirectorReferenceType type = DirectorReferenceType.character,
    double? strength,
    double? fidelity,
  }) async {
    _isProcessing = true;
    notifyListeners();

    try {
      final (_, base64) = await ReferenceImageProcessor.processImage(
        imageBytes,
      );
      final ref = DirectorReference(
        id: _ids.next(),
        originalImageBytes: imageBytes,
        processedBase64: base64,
        type: type,
        strength: strength ?? _defaultStrength,
        fidelity: fidelity ?? _defaultFidelity,
      );
      _references = [..._references, ref];
      return ref.id;
    } catch (e) {
      debugPrint('DirectorRefNotifier: Failed to process image: $e');
      return null;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  void removeReference(String id) {
    _references = _references.where((r) => r.id != id).toList();
    notifyListeners();
  }

  void updateType(String id, DirectorReferenceType type) {
    _references = _references.map((r) {
      if (r.id == id) return r.copyWith(type: type);
      return r;
    }).toList();
    notifyListeners();
  }

  void updateStrength(String id, double strength) {
    _references = _references.map((r) {
      if (r.id == id) return r.copyWith(strength: strength);
      return r;
    }).toList();
    _defaultStrength = strength;
    _prefs?.setRefLastStrength(strength);
    notifyListeners();
  }

  void updateFidelity(String id, double fidelity) {
    _references = _references.map((r) {
      if (r.id == id) return r.copyWith(fidelity: fidelity);
      return r;
    }).toList();
    _defaultFidelity = fidelity;
    _prefs?.setRefLastFidelity(fidelity);
    notifyListeners();
  }

  /// Toggles whether a reference is included in generation. The processed
  /// image data is retained, so re-enabling does not re-process the image.
  void toggleEnabled(String id) {
    _references = _references.map((r) {
      if (r.id == id) return r.copyWith(enabled: !r.enabled);
      return r;
    }).toList();
    notifyListeners();
  }

  /// Replaces all references wholesale (used when applying a preset).
  /// Re-processes each reference to derive processedBase64 from originalImageBytes.
  Future<void> setReferences(List<DirectorReference> refs) async {
    _isProcessing = true;
    notifyListeners();

    try {
      final processed = <DirectorReference>[];
      for (final ref in refs) {
        if (ref.processedBase64.isNotEmpty) {
          processed.add(ref);
        } else {
          final (_, base64) = await ReferenceImageProcessor.processImage(
            ref.originalImageBytes,
          );
          processed.add(ref.copyWith(processedBase64: base64));
        }
      }
      _references = _ids.adopt(
        processed,
        idOf: (r) => r.id,
        withId: (r, id) => r.copyWith(id: id),
      );
    } catch (e) {
      debugPrint('DirectorRefNotifier: Failed to set references: $e');
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  void clearAll() {
    _references = [];
    notifyListeners();
  }

  /// Assembles the 5 parallel arrays for API injection from the references
  /// that are [isSent]. Returns null if there are none.
  DirectorRefPayload? buildPayload() {
    final active = _references.where(isSent).toList();
    if (active.isEmpty) return null;

    final images = <String>[];
    final descriptions = <Map<String, dynamic>>[];
    final strengths = <double>[];
    final secondaryStrengths = <double>[];
    final infoExtracted = <double>[];

    for (final ref in active) {
      images.add(ref.processedBase64);
      descriptions.add({
        'caption': {'base_caption': ref.type.apiCaption, 'char_captions': []},
        'legacy_uc': false,
      });
      strengths.add(ref.strength);
      // Fidelity inversion: API value = 1.0 - UI fidelity
      secondaryStrengths.add(1.0 - ref.fidelity);
      infoExtracted.add(1.0);
    }

    return DirectorRefPayload(
      images: images,
      descriptions: descriptions,
      strengths: strengths,
      secondaryStrengths: secondaryStrengths,
      infoExtracted: infoExtracted,
    );
  }
}
