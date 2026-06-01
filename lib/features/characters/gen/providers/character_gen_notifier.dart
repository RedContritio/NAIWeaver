import 'package:flutter/foundation.dart';

import '../../../../core/services/text_gen_service.dart';
import '../../../text_gen/providers/text_gen_notifier.dart';
import '../../providers/character_library_notifier.dart';
import '../character_gen_data.dart';
import '../character_gen_service.dart';

/// Drives the "Generate Character" flow: holds the in-flight progress, exposes
/// [generate]/[cancel], and on success persists the new [SavedCharacter] +
/// closet via [CharacterLibraryNotifier] (so it shows up in the list and tag
/// autocomplete immediately).
///
/// The concrete [TextGenService] is read off the injected [TextGenNotifier]
/// (which `GenerationNotifier` keeps updated as the API key changes), so
/// generation only works once a `pst-` token is present — same gating as the
/// rest of the text-gen surface.
class CharacterGenNotifier extends ChangeNotifier {
  final CharacterLibraryNotifier _library;
  TextGenNotifier _textGen;

  CharacterGenNotifier({
    required CharacterLibraryNotifier library,
    required TextGenNotifier textGen,
  })  : _library = library,
        _textGen = textGen;

  /// Re-bound by the ProxyProvider when the TextGenNotifier instance changes.
  void updateTextGen(TextGenNotifier textGen) {
    _textGen = textGen;
  }

  bool get hasService => _textGen.hasService;

  bool _isGenerating = false;
  bool get isGenerating => _isGenerating;

  CharacterGenProgress? _progress;
  CharacterGenProgress? get progress => _progress;

  String? _lastError;
  String? get lastError => _lastError;

  /// The id of the character produced by the last successful run (so the UI can
  /// select it). Cleared at the start of each run.
  String? _lastGeneratedId;
  String? get lastGeneratedId => _lastGeneratedId;

  CharacterGenCancelToken? _cancelToken;

  /// Runs the pipeline. Returns the new character's id on success, or null if
  /// it failed or was cancelled (check [lastError]).
  Future<String?> generate(CharacterGenForm form) async {
    if (_isGenerating) return null;
    final service = _textGen.service;
    if (service == null) {
      _lastError = 'NovelAI token not set — add it in Settings.';
      notifyListeners();
      return null;
    }

    _isGenerating = true;
    _lastError = null;
    _lastGeneratedId = null;
    _progress = const CharacterGenProgress(CharacterGenStep.preparing);
    final token = CharacterGenCancelToken();
    _cancelToken = token;
    notifyListeners();

    try {
      final gen = CharacterGenService(
        service,
        model: _textGen.model,
        maxTokens: _textGen.params.maxLength,
      );
      final result = await gen.generate(
        form,
        cancelToken: token,
        onProgress: (p) {
          _progress = p;
          notifyListeners();
        },
      );

      // Persist: the character first, then its closet (so the library notifier
      // has the character before the closet is attached).
      await _library.importGeneratedCharacter(result.character, result.closet);
      _lastGeneratedId = result.character.id;
      return result.character.id;
    } on CharacterGenCancelled {
      _lastError = null; // cancellation isn't an error
      return null;
    } on TextGenException catch (e) {
      _lastError = e.message;
      return null;
    } catch (e) {
      _lastError = e.toString();
      return null;
    } finally {
      _isGenerating = false;
      _progress = null;
      _cancelToken = null;
      notifyListeners();
    }
  }

  /// Aborts an in-flight generation. Nothing is written to disk until the very
  /// end of the pipeline, so this leaves no half-written files.
  void cancel() {
    _cancelToken?.cancel();
  }

  /// Default form, used to seed the dialog.
  CharacterGenForm defaultForm() => CharacterGenForm(
        vibe: kCustomCharacterVibe,
        era: CharacterEraCatalogue.cachedOrFallback.firstWhere(
          (e) => e.isModern,
          orElse: () => CharacterEraCatalogue.cachedOrFallback.last,
        ),
      );
}
