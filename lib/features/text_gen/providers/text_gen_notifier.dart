import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/services/text_gen_service.dart';

/// Owns the state of the Text Gen panel.
///
/// Follows the app's standard `ChangeNotifier` pattern. The concrete
/// [TextGenService] is injected via [updateService] (pushed by
/// `GenerationNotifier` when the API key loads/changes), so the panel works the
/// moment a `pst-` token is present.
class TextGenNotifier extends ChangeNotifier {
  TextGenService? _service;

  String _input = '';
  String _model = kDefaultTextModel;
  TextGenParams _params = TextGenParams.glmDefault();
  String _stopStringsRaw = '';
  String _activePresetName = TextGenParams.presetNames.first;

  String _output = '';
  bool _isGenerating = false;
  String? _lastError;

  final List<TextGenHistoryEntry> _history = [];
  static const int _maxHistory = 20;

  StreamSubscription<String>? _sub;

  // — Getters —
  String get input => _input;
  String get model => _model;
  TextGenParams get params => _params;
  String get stopStringsRaw => _stopStringsRaw;
  String get activePresetName => _activePresetName;
  String get output => _output;
  bool get isGenerating => _isGenerating;
  String? get lastError => _lastError;
  List<TextGenHistoryEntry> get history => List.unmodifiable(_history);
  bool get hasService => _service != null;
  bool get hasOutput => _output.isNotEmpty;

  /// Parsed stop strings (newline-separated in the UI; blanks dropped).
  List<String> get stopStrings => _stopStringsRaw
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  void updateService(TextGenService? service) {
    _service = service;
  }

  // — Setters —
  void setInput(String value) {
    _input = value;
    // No notify: the TextField owns the source of truth while typing.
  }

  void setModel(String value) {
    _model = value.trim().isEmpty ? kDefaultTextModel : value.trim();
    notifyListeners();
  }

  void setStopStrings(String value) {
    _stopStringsRaw = value;
  }

  void setTemperature(double v) =>
      _updateParams(_params.copyWith(temperature: v));
  void setMaxLength(int v) =>
      _updateParams(_params.copyWith(maxLength: v.clamp(1, 100000)));
  void setTopP(double v) => _updateParams(_params.copyWith(topP: v));
  void setTopK(int v) => _updateParams(_params.copyWith(topK: v.clamp(0, 1000)));
  void setRepetitionPenalty(double v) =>
      _updateParams(_params.copyWith(repetitionPenalty: v));
  void setPhraseRepPen(String v) =>
      _updateParams(_params.copyWith(phraseRepPen: v));
  void setGenerateUntilSentence(bool v) =>
      _updateParams(_params.copyWith(generateUntilSentence: v));

  void _updateParams(TextGenParams next) {
    _params = next;
    notifyListeners();
  }

  /// Replaces [params] with a named preset (see [TextGenParams.presetNames]).
  void loadPreset(String name) {
    _activePresetName = name;
    _params = TextGenParams.byPresetName(name);
    notifyListeners();
  }

  void clearOutput() {
    _output = '';
    _lastError = null;
    notifyListeners();
  }

  /// Moves the current output onto the end of the input — the manual version of
  /// chunked continuation. Output is then cleared.
  void appendOutputToInput() {
    if (_output.isEmpty) return;
    _input = '$_input$_output';
    _output = '';
    notifyListeners();
  }

  Future<void> generate() async {
    if (_isGenerating) return;
    final service = _service;
    if (service == null) {
      _lastError = 'NovelAI token not set — add it in Settings.';
      notifyListeners();
      return;
    }
    if (_input.trim().isEmpty) {
      _lastError = 'Enter some text to continue from.';
      notifyListeners();
      return;
    }

    _isGenerating = true;
    _lastError = null;
    _output = '';
    notifyListeners();

    final req = TextGenRequest(
      input: _input,
      model: _model,
      params: _params,
      stopStrings: stopStrings.isEmpty ? null : stopStrings,
    );

    final completer = Completer<void>();
    final capturedInput = _input;
    final capturedParams = _params;
    final capturedModel = _model;

    _sub = service.generateStream(req).listen(
      (chunk) {
        _output += chunk;
        notifyListeners();
      },
      onError: (Object e, StackTrace st) {
        _lastError = e is TextGenException ? e.message : e.toString();
        _finishGeneration();
        if (!completer.isCompleted) completer.complete();
      },
      onDone: () {
        if (_output.isNotEmpty) {
          _history.insert(
            0,
            TextGenHistoryEntry(
              input: capturedInput,
              output: _output,
              params: capturedParams,
              model: capturedModel,
              timestamp: DateTime.now(),
            ),
          );
          if (_history.length > _maxHistory) {
            _history.removeRange(_maxHistory, _history.length);
          }
        }
        _finishGeneration();
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    await completer.future;
  }

  /// Cancels the in-flight stream. Any partial output is retained.
  void cancel() {
    _sub?.cancel();
    _sub = null;
    if (_isGenerating) {
      _isGenerating = false;
      notifyListeners();
    }
  }

  void _finishGeneration() {
    _sub?.cancel();
    _sub = null;
    _isGenerating = false;
    notifyListeners();
  }

  void restoreFromHistory(TextGenHistoryEntry entry) {
    _input = entry.input;
    _model = entry.model;
    _params = entry.params;
    _output = entry.output;
    _activePresetName = TextGenParams.presetNames.first;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
