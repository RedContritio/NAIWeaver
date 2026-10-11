import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/gateway/backend_permissions.dart';
import '../../../core/services/novel_ai_service.dart';
import '../../../core/services/reference_library_service.dart';
import '../../director_ref/providers/reference_id_allocator.dart';
import '../../director_ref/services/reference_image_processor.dart';
import '../models/vibe_transfer.dart';

class VibeTransferNotifier extends ChangeNotifier {
  List<VibeTransfer> _vibes = [];
  bool _isProcessing = false;
  final _ids = ReferenceIdAllocator('vibe_');
  NovelAIService? _service;
  bool _useCurated = false;
  PaidImageAccess _access = PaidImageAccess.allowed;

  List<VibeTransfer> get vibes => _vibes;
  bool get isProcessing => _isProcessing;

  /// Whether the account can currently send vibes (encoding a new one needs
  /// its own permission). Without access the vibes stay in the list, marked
  /// paused, and are not sent.
  PaidImageAccess get access => _access;

  /// Enabled by the user and sent: the user's own switch combined with the
  /// account's current access.
  bool isSent(VibeTransfer vibe) =>
      vibe.enabled && _access == PaidImageAccess.allowed;

  /// Enabled by the user but held back for lack of access.
  bool isPaused(VibeTransfer vibe) =>
      vibe.enabled && _access != PaidImageAccess.allowed;

  /// Vibes the user enabled that are held back for lack of access.
  int get pausedCount => _access == PaidImageAccess.allowed
      ? 0
      : _vibes.where((v) => v.enabled).length;

  int get sentCount => _vibes.where(isSent).length;

  void updateAccess(PaidImageAccess access) {
    if (_access == access) return;
    _access = access;
    notifyListeners();
  }

  void updateService(NovelAIService service) {
    _service = service;
  }

  void updateUseCurated(bool value) {
    _useCurated = value;
  }

  /// Encodes [imageBytes] into a vibe and returns its id. Encoding failures
  /// (missing credentials, gateway errors, network) are rethrown so the
  /// caller can explain them; nothing is added then.
  Future<String> addVibe(Uint8List imageBytes) async {
    if (_service == null) {
      throw UnauthorizedException('API key not configured');
    }

    _isProcessing = true;
    notifyListeners();

    try {
      final (preview, b64) = await ReferenceImageProcessor.processVibeImage(
        imageBytes,
      );

      final vibeVectorBytes = await _service!.encodeVibeImage(
        imageBase64: b64,
        informationExtracted: 1.0,
        useCurated: _useCurated,
      );
      final vibeVectorB64 = base64Encode(vibeVectorBytes);

      final vibe = VibeTransfer(
        id: _ids.next(),
        originalImageBytes: imageBytes,
        processedPreview: preview,
        vibeVectorBase64: vibeVectorB64,
      );
      _vibes = [..._vibes, vibe];
      return vibe.id;
    } catch (e) {
      debugPrint('VibeTransferNotifier: Failed to process vibe: $e');
      rethrow;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Adds a library entry as a new vibe. Its vector is already encoded, so
  /// no API call is made. The entry gets a fresh id, so loading the same
  /// saved vibe twice yields two independent vibes. Returns the new id.
  String addFromSaved(SavedVibeTransfer saved) {
    final source = saved.vibe;
    final vibe = VibeTransfer(
      id: _ids.next(),
      originalImageBytes: source.originalImageBytes,
      processedPreview: source.processedPreview,
      vibeVectorBase64: source.vibeVectorBase64,
      strength: source.strength,
      infoExtracted: source.infoExtracted,
    );
    _vibes = [..._vibes, vibe];
    notifyListeners();
    return vibe.id;
  }

  void removeVibe(String id) {
    _vibes = _vibes.where((v) => v.id != id).toList();
    notifyListeners();
  }

  void updateStrength(String id, double strength) {
    _vibes = _vibes.map((v) {
      if (v.id == id) return v.copyWith(strength: strength);
      return v;
    }).toList();
    notifyListeners();
  }

  void updateInfoExtracted(String id, double infoExtracted) {
    _vibes = _vibes.map((v) {
      if (v.id == id) return v.copyWith(infoExtracted: infoExtracted);
      return v;
    }).toList();
    notifyListeners();
  }

  /// Toggles whether a vibe is included in generation. The encoded vector is
  /// retained, so re-enabling never triggers another encode round-trip.
  void toggleEnabled(String id) {
    _vibes = _vibes.map((v) {
      if (v.id == id) return v.copyWith(enabled: !v.enabled);
      return v;
    }).toList();
    notifyListeners();
  }

  /// Replaces all vibes wholesale (used when applying a preset or snapshot).
  void setVibes(List<VibeTransfer> vibes) {
    _vibes = _ids.adopt(
      vibes,
      idOf: (v) => v.id,
      withId: (v, id) => v.copyWith(id: id),
    );
    notifyListeners();
  }

  void clearAll() {
    _vibes = [];
    notifyListeners();
  }

  /// The payload of the vibes that are [isSent]; null if there are none.
  VibeTransferPayload? buildPayload() {
    final active = _vibes.where(isSent).toList();
    if (active.isEmpty) return null;

    final vectors = <String>[];
    final strengths = <double>[];
    final infoExtracted = <double>[];

    for (final vibe in active) {
      vectors.add(vibe.vibeVectorBase64);
      strengths.add(vibe.strength);
      infoExtracted.add(vibe.infoExtracted);
    }

    return VibeTransferPayload(
      vibeVectors: vectors,
      strengths: strengths,
      infoExtracted: infoExtracted,
    );
  }
}
