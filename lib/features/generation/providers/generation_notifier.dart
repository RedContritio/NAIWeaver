import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../core/gateway/backend_error_messages.dart';
import '../../../core/gateway/backend_exception.dart';
import '../../../core/gateway/backend_gateway.dart';
import '../../../core/gateway/backend_permissions.dart';
import '../../../core/gateway/backend_rules.dart';
import '../../../core/gateway/image_quote.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/l10n/locale_notifier.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/utils/filename_pattern.dart';
import '../../../core/utils/nai_filename.dart';
import '../../../core/utils/unique_file_path.dart';
import '../../../core/utils/web_download.dart';
import '../../../core/services/saf_export_service.dart';
import '../../../core/services/preferences_service.dart';
import '../../../core/services/backend_client.dart';
import '../../../core/services/novel_ai_service.dart';
import '../../../core/services/backend_history_api.dart';
import '../../../core/services/nai_text_service.dart';
import '../../../core/services/wildcard_processor.dart';
import '../../../core/services/presets.dart';
import '../../../core/services/tag_service.dart';
import '../../../core/utils/image_utils.dart';
import '../../../core/services/wildcard_service.dart';
import '../../../core/utils/tag_suggestion_helper.dart';
import '../../../core/widgets/syntax_highlight_controller.dart';
import '../../../core/services/styles.dart';
import '../../gallery/providers/gallery_notifier.dart';
import '../../tools/providers/tag_library_notifier.dart';
import '../models/nai_character.dart';
import '../models/character_preset.dart';
import '../models/generation_quote.dart';
import '../../tools/cascade/services/cascade_stitching_service.dart';
import '../../tools/img2img/services/img2img_request_builder.dart';
import '../../director_ref/models/director_reference.dart';
import '../../director_ref/providers/director_ref_notifier.dart';
import '../../vibe_transfer/models/vibe_transfer.dart';
import '../../vibe_transfer/providers/vibe_transfer_notifier.dart';
import '../../tools/director_tools/providers/director_tools_notifier.dart';
import '../../tools/enhance/providers/enhance_notifier.dart';
import '../../text_gen/providers/text_gen_notifier.dart';
import '../../characters/providers/character_library_notifier.dart';
import 'package:dio/dio.dart';
import '../services/metadata_import_service.dart';
import '../services/session_snapshot_service.dart';
import '../services/character_manager.dart';
import '../services/preset_service.dart';

/// Outcome of applying a tag suggestion, so the UI can react (e.g. show a
/// "character limit reached" toast). Only [characterLimitReached] needs UI
/// feedback; the others are silent successes.
enum ApplyTagResult {
  /// Inserted into the active text field (ordinary tag, or a saved character
  /// while the insert-target preference is 'main').
  insertedIntoPrompt,

  /// A saved character was added as a new character card.
  addedCharacterCard,

  /// A saved character could not be added because the editor is already at the
  /// 6-character maximum. Nothing was inserted.
  characterLimitReached,
}

enum GenerationErrorTone { general, greenPoints, redPoints }

enum GenerationTaskProgress { queued, generating, failed, rejected, cancelled }

class GenerationError {
  final String message;
  final GenerationErrorTone tone;
  final bool suggestRandomSeed;

  const GenerationError(
    this.message, [
    this.tone = GenerationErrorTone.general,
    this.suggestRandomSeed = false,
  ]);
}

class GeneratedImageItem {
  final String id;
  final Uint8List? bytes;
  final Map<String, dynamic>? metadata;
  final int batchIndex;
  final int batchCount;
  final int? seed;
  final bool isLoading;
  final GenerationTaskProgress progress;
  final bool duplicateImageDetected;
  final bool saved;
  final String? savedBasename;
  final String? errorMessage;

  const GeneratedImageItem({
    required this.id,
    required this.batchIndex,
    required this.batchCount,
    this.bytes,
    this.metadata,
    this.seed,
    this.isLoading = false,
    this.progress = GenerationTaskProgress.queued,
    this.duplicateImageDetected = false,
    this.saved = false,
    this.savedBasename,
    this.errorMessage,
  });

  bool get isComplete => bytes != null;
  bool get isTerminal =>
      isComplete ||
      progress == GenerationTaskProgress.failed ||
      progress == GenerationTaskProgress.rejected ||
      progress == GenerationTaskProgress.cancelled;

  GeneratedImageItem copyWith({
    Uint8List? bytes,
    Map<String, dynamic>? metadata,
    int? seed,
    bool? isLoading,
    GenerationTaskProgress? progress,
    bool? duplicateImageDetected,
    bool? saved,
    String? savedBasename,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return GeneratedImageItem(
      id: id,
      batchIndex: batchIndex,
      batchCount: batchCount,
      bytes: bytes ?? this.bytes,
      metadata: metadata ?? this.metadata,
      seed: seed ?? this.seed,
      isLoading: isLoading ?? this.isLoading,
      progress: progress ?? this.progress,
      duplicateImageDetected:
          duplicateImageDetected ?? this.duplicateImageDetected,
      saved: saved ?? this.saved,
      savedBasename: savedBasename ?? this.savedBasename,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
    );
  }
}

class GenerationState {
  final Uint8List? generatedImage;
  final List<GeneratedImageItem> generatedImages;
  final String? selectedGeneratedImageId;
  final bool autoFollowLatestImage;
  final bool isLoading;
  final bool isDragging;
  final bool isSettingsExpanded;
  final List<GenerationPreset> presets;
  final List<PromptStyle> styles;
  final List<DanbooruTag> tagSuggestions;
  final String currentTagQuery;

  // Generation Settings
  final double width;
  final double height;
  final double scale;
  final double steps;
  final String sampler;
  final bool smea;
  final bool smeaDyn;
  final bool decrisper;
  final bool randomizeSeed;
  final int batchCount;
  final List<String> activeStyleNames;
  final bool isStyleEnabled;
  final String apiKey;
  final bool autoSaveImages;
  final bool hasAuthError;
  final List<NaiCharacter> characters;
  final List<NaiInteraction> interactions;
  final bool showDirectorRefShelf;
  final bool showVibeTransferShelf;
  final bool brightTheme;
  final bool autoPositioning;
  final bool showEditButton;
  final bool showBgRemovalButton;
  final bool showUpscaleButton;
  final bool showEnhanceButton;
  final bool showDirectorToolsButton;
  final bool furryMode;
  final bool useCurated;
  final String? errorMessage;
  final GenerationErrorTone errorTone;
  final bool errorSuggestRandomSeed;
  final int? anlas;
  final String characterEditorMode;
  final List<CharacterPreset> characterPresets;
  final bool duplicateImageDetected;

  GenerationState({
    this.generatedImage,
    this.generatedImages = const [],
    this.selectedGeneratedImageId,
    this.autoFollowLatestImage = true,
    this.isLoading = false,
    this.isDragging = false,
    this.isSettingsExpanded = false,
    this.presets = const [],
    this.styles = const [],
    this.tagSuggestions = const [],
    this.currentTagQuery = "",
    this.width = 832,
    this.height = 1216,
    this.scale = 5.0,
    this.steps = 28,
    this.sampler = "k_euler_ancestral",
    this.smea = false,
    this.smeaDyn = false,
    this.decrisper = false,
    this.randomizeSeed = true,
    this.batchCount = 1,
    this.activeStyleNames = const [],
    this.isStyleEnabled = true,
    this.apiKey = '',
    this.autoSaveImages = true,
    this.hasAuthError = false,
    this.characters = const [],
    this.interactions = const [],
    this.showDirectorRefShelf = true,
    this.showVibeTransferShelf = true,
    this.brightTheme = true,
    this.autoPositioning = false,
    this.showEditButton = true,
    this.showBgRemovalButton = true,
    this.showUpscaleButton = true,
    this.showEnhanceButton = false,
    this.showDirectorToolsButton = false,
    this.furryMode = false,
    this.useCurated = false,
    this.errorMessage,
    this.errorTone = GenerationErrorTone.general,
    this.errorSuggestRandomSeed = false,
    this.anlas,
    this.characterEditorMode = 'expanded',
    this.characterPresets = const [],
    this.duplicateImageDetected = false,
  });

  GenerationState copyWith({
    Uint8List? generatedImage,
    bool clearGeneratedImage = false,
    List<GeneratedImageItem>? generatedImages,
    String? selectedGeneratedImageId,
    bool clearSelectedGeneratedImageId = false,
    bool? autoFollowLatestImage,
    bool? isLoading,
    bool? isDragging,
    bool? isSettingsExpanded,
    List<GenerationPreset>? presets,
    List<PromptStyle>? styles,
    List<DanbooruTag>? tagSuggestions,
    String? currentTagQuery,
    double? width,
    double? height,
    double? scale,
    double? steps,
    String? sampler,
    bool? smea,
    bool? smeaDyn,
    bool? decrisper,
    bool? randomizeSeed,
    int? batchCount,
    List<String>? activeStyleNames,
    bool? isStyleEnabled,
    String? apiKey,
    bool? autoSaveImages,
    bool? hasAuthError,
    List<NaiCharacter>? characters,
    List<NaiInteraction>? interactions,
    bool? showDirectorRefShelf,
    bool? showVibeTransferShelf,
    bool? brightTheme,
    bool? autoPositioning,
    bool? showEditButton,
    bool? showBgRemovalButton,
    bool? showUpscaleButton,
    bool? showEnhanceButton,
    bool? showDirectorToolsButton,
    bool? furryMode,
    bool? useCurated,
    String? errorMessage,
    GenerationErrorTone? errorTone,
    bool? errorSuggestRandomSeed,
    bool clearErrorMessage = false,
    int? anlas,
    bool clearAnlas = false,
    String? characterEditorMode,
    List<CharacterPreset>? characterPresets,
    bool? duplicateImageDetected,
  }) {
    return GenerationState(
      generatedImage: clearGeneratedImage
          ? null
          : generatedImage ?? this.generatedImage,
      generatedImages: generatedImages ?? this.generatedImages,
      selectedGeneratedImageId: clearSelectedGeneratedImageId
          ? null
          : selectedGeneratedImageId ?? this.selectedGeneratedImageId,
      autoFollowLatestImage:
          autoFollowLatestImage ?? this.autoFollowLatestImage,
      isLoading: isLoading ?? this.isLoading,
      isDragging: isDragging ?? this.isDragging,
      isSettingsExpanded: isSettingsExpanded ?? this.isSettingsExpanded,
      presets: presets ?? this.presets,
      styles: styles ?? this.styles,
      tagSuggestions: tagSuggestions ?? this.tagSuggestions,
      currentTagQuery: currentTagQuery ?? this.currentTagQuery,
      width: width ?? this.width,
      height: height ?? this.height,
      scale: scale ?? this.scale,
      steps: steps ?? this.steps,
      sampler: sampler ?? this.sampler,
      smea: smea ?? this.smea,
      smeaDyn: smeaDyn ?? this.smeaDyn,
      decrisper: decrisper ?? this.decrisper,
      randomizeSeed: randomizeSeed ?? this.randomizeSeed,
      batchCount: batchCount ?? this.batchCount,
      activeStyleNames: activeStyleNames ?? this.activeStyleNames,
      isStyleEnabled: isStyleEnabled ?? this.isStyleEnabled,
      apiKey: apiKey ?? this.apiKey,
      autoSaveImages: autoSaveImages ?? this.autoSaveImages,
      hasAuthError: hasAuthError ?? this.hasAuthError,
      characters: characters ?? this.characters,
      interactions: interactions ?? this.interactions,
      showDirectorRefShelf: showDirectorRefShelf ?? this.showDirectorRefShelf,
      showVibeTransferShelf:
          showVibeTransferShelf ?? this.showVibeTransferShelf,
      brightTheme: brightTheme ?? this.brightTheme,
      autoPositioning: autoPositioning ?? this.autoPositioning,
      showEditButton: showEditButton ?? this.showEditButton,
      showBgRemovalButton: showBgRemovalButton ?? this.showBgRemovalButton,
      showUpscaleButton: showUpscaleButton ?? this.showUpscaleButton,
      showEnhanceButton: showEnhanceButton ?? this.showEnhanceButton,
      showDirectorToolsButton:
          showDirectorToolsButton ?? this.showDirectorToolsButton,
      furryMode: furryMode ?? this.furryMode,
      useCurated: useCurated ?? this.useCurated,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      errorTone: clearErrorMessage
          ? GenerationErrorTone.general
          : (errorTone ?? this.errorTone),
      errorSuggestRandomSeed: clearErrorMessage
          ? false
          : (errorSuggestRandomSeed ?? this.errorSuggestRandomSeed),
      anlas: clearAnlas ? null : (anlas ?? this.anlas),
      characterEditorMode: characterEditorMode ?? this.characterEditorMode,
      characterPresets: characterPresets ?? this.characterPresets,
      duplicateImageDetected:
          duplicateImageDetected ?? this.duplicateImageDetected,
    );
  }
}

class GenerationNotifier extends ChangeNotifier {
  static const String _qualityStyleName = 'Quality (NAI Default)';
  static const String _legacyLightStyleName = 'Light - NAI';

  GenerationState _state = GenerationState();
  GenerationState get state => _state;

  late NovelAIService _service;
  final NovelAIService Function(String apiKey) _serviceFactory;
  final BackendHistoryApi _historyApi;
  ImageRules? _rules;
  GenerationAccess _access = GenerationAccess.unrestricted;
  int? _backendUserId;
  int? _restoringWorkspaceForUserId;
  NovelAIService get service => _service;
  late final WildcardProcessor _wildcardProcessor;
  final TagService _tagService;
  final WildcardService _wildcardService;
  final PreferencesService _prefs;
  String _outputDir;
  GalleryNotifier? _galleryNotifier;
  DirectorRefNotifier? _directorRefNotifier;
  VibeTransferNotifier? _vibeTransferNotifier;
  DirectorToolsNotifier? _directorToolsNotifier;
  EnhanceNotifier? _enhanceNotifier;
  TextGenNotifier? _textGenNotifier;
  CharacterLibraryNotifier? _characterLibrary;
  NaiTextService _textService = NaiTextService('');

  // Extracted services
  final MetadataImportService _metadataImportService = MetadataImportService();
  late final SessionSnapshotService _sessionService;
  late final CharacterManager _characterManager;
  late final PresetFileService _presetService;

  TagService get tagService => _tagService;
  WildcardService get wildcardService => _wildcardService;
  String get presetsFilePath => _presetService.presetsFilePath;
  String get stylesFilePath => _presetService.stylesFilePath;

  Map<String, dynamic>? _lastMetadata;
  bool _imageSaved = false;
  bool get imageSaved => _imageSaved;
  String? _lastSavedBasename;
  String? get lastSavedBasename => _lastSavedBasename;
  Uint8List? _previousImageBytes;

  /// Filenames already triggered as web downloads this session. Web has no
  /// filesystem to probe for collisions like [uniqueFilePath] does, so we track
  /// emitted names here and apply the same `_(2)`, `_(3)`, … suffix convention
  /// when [_buildFileName] yields a name we've handed out before.
  final Set<String> _webDownloadedNames = {};

  Timer? _tagDebounce;
  Timer? _sessionSaveDebounce;
  bool _sessionReady = false;
  bool _metadataImportedBeforeSessionReady = false;
  final SyntaxHighlightController promptController =
      SyntaxHighlightController();
  final SyntaxHighlightController negativePromptController =
      SyntaxHighlightController(text: "");

  static const String defaultNegativePrompt =
      "lowres, {bad}, error, fewer, extra, missing, worst quality, jpeg artifacts, bad quality, watermark, unfinished, displeasing, chromatic aberration, signature, extra digits, artistic error, username, scan, [abstract]";
  final TextEditingController seedController = TextEditingController();

  GenerationNotifier({
    required PreferencesService preferences,
    required TagService tagService,
    required WildcardService wildcardService,
    required String outputDir,
    required String presetsFilePath,
    required String stylesFilePath,
    GalleryNotifier? galleryNotifier,
    CharacterLibraryNotifier? characterLibrary,
    NovelAIService Function(String apiKey)? serviceFactory,
    BackendHistoryApi? historyApi,
  }) : _prefs = preferences,
       _tagService = tagService,
       _wildcardService = wildcardService,
       _outputDir = outputDir,
       _galleryNotifier = galleryNotifier,
       _characterLibrary = characterLibrary,
       _serviceFactory = serviceFactory ?? NovelAIService.new,
       _historyApi = historyApi ?? BackendHistoryApi() {
    _service = _serviceFactory('');
    _wildcardProcessor = WildcardProcessor(
      wildcardDir: wildcardService.wildcardDir,
      wildcardService: _wildcardService,
    );
    _presetService = PresetFileService(
      presetsFilePath: presetsFilePath,
      stylesFilePath: stylesFilePath,
    );
    _sessionService = SessionSnapshotService(
      sessionFilePath: p.join(
        p.dirname(presetsFilePath),
        'session_snapshot.json',
      ),
    );
    _characterManager = CharacterManager(prefs: _prefs);
    negativePromptController.text = "";
    _loadInitialData();
  }

  void updateGalleryNotifier(GalleryNotifier galleryNotifier) {
    _galleryNotifier = galleryNotifier;
  }

  /// Rebuild the result workspace after a browser reload. Generation tasks are
  /// durable on the gateway; the UI is only a view of those server records.
  void updateBackendUserId(int? userId) {
    if (_backendUserId == userId) return;
    _backendUserId = userId;
    // The workspace belongs to the previous account: another user must never
    // see its images, even when their own history is empty.
    _lastMetadata = null;
    _imageSaved = false;
    _state = _state.copyWith(
      generatedImages: const [],
      clearGeneratedImage: true,
      clearSelectedGeneratedImageId: true,
      autoFollowLatestImage: true,
      isLoading: false,
      clearErrorMessage: true,
      duplicateImageDetected: false,
    );
    notifyListeners();
    if (useBackendGateway && userId != null) {
      unawaited(_restoreGatewayWorkspace(userId));
    }
  }

  Future<void> _restoreGatewayWorkspace(int userId) async {
    if (_restoringWorkspaceForUserId == userId || _state.isLoading) return;
    _restoringWorkspaceForUserId = userId;
    try {
      final currentTask = await _historyApi.fetchCurrentTask();
      var history = currentTask?.items ?? const <ServerHistoryItem>[];
      // Existing sessions predate the cookie; retain the time-window fallback
      // for those users until they submit a new explicit batch.
      if (history.isEmpty) {
        history = await _historyApi.fetchHistory(limit: 20, currentBatch: true);
      }
      if (history.isEmpty) {
        history = await _historyApi.fetchHistory(limit: 20);
      }
      if (_backendUserId != userId || _state.isLoading) return;
      final visible = history.toList(growable: false);
      if (visible.isEmpty) return;
      // A browser batch submits all of its tasks together. Restore that most
      // recent batch only, rather than replacing the workspace with all of a
      // user's old server history.
      final recoverable = currentTask != null
          ? visible
          : (() {
              final latest = visible.first;
              final sameSubmission = !latest.isBatch
                  ? <ServerHistoryItem>[latest]
                  : visible
                        .where((item) => item.batchId == latest.batchId)
                        .toList();
              return sameSubmission.reversed.toList(growable: false);
            })();
      if (recoverable.isEmpty) return;

      final restored = List<GeneratedImageItem>.generate(recoverable.length, (
        index,
      ) {
        final task = recoverable[index];
        return GeneratedImageItem(
          id: task.id,
          batchIndex: index + 1,
          batchCount: recoverable.length,
          seed: task.seed,
          metadata: task.generationMetadata,
          isLoading: task.status == 'queued' || task.status == 'running',
          progress: _progressForGatewayStatus(task.status),
          errorMessage: _itemFailureMessage(task),
        );
      });
      _state = _state.copyWith(
        generatedImages: restored,
        selectedGeneratedImageId: restored.first.id,
        autoFollowLatestImage: true,
        clearGeneratedImage: true,
      );
      notifyListeners();

      for (final task in recoverable.where(
        (item) => item.status == 'success',
      )) {
        unawaited(_restoreGatewayImage(task, userId));
      }
      unawaited(_resumeGatewayTasks(recoverable, userId));
    } catch (error) {
      debugPrint('Could not restore gateway generation workspace: $error');
    } finally {
      if (_restoringWorkspaceForUserId == userId) {
        _restoringWorkspaceForUserId = null;
      }
    }
  }

  Future<void> _restoreGatewayImage(ServerHistoryItem task, int userId) async {
    try {
      final bytes = await _historyApi.fetchImageBytes(task.id);
      _applyRestoredGatewayImage(task, userId, bytes);
    } catch (error) {
      debugPrint('Could not restore gateway image ${task.id}: $error');
      if (_backendUserId != userId) return;
      _state = _state.copyWith(
        generatedImages: _replaceGeneratedImageItem(
          task.id,
          (item) => item.copyWith(
            isLoading: false,
            progress: GenerationTaskProgress.failed,
            errorMessage: _formatError(error).message,
          ),
        ),
      );
      notifyListeners();
    }
  }

  void _applyRestoredGatewayImage(
    ServerHistoryItem task,
    int userId,
    Uint8List bytes,
  ) {
    if (_backendUserId != userId) return;
    final metadata = _historyMetadata(task);
    final existing = _state.generatedImages
        .where((item) => item.id == task.id)
        .firstOrNull;
    if (existing == null) return;
    final completed = existing.copyWith(
      bytes: bytes,
      metadata: metadata,
      seed: task.seed,
      isLoading: false,
    );
    final shouldSelect =
        _state.autoFollowLatestImage || _state.selectedGeneratedImageId == null;
    _state = _state.copyWith(
      generatedImages: _replaceGeneratedImageItem(task.id, (_) => completed),
      selectedGeneratedImageId: shouldSelect ? task.id : null,
      generatedImage: shouldSelect ? bytes : null,
    );
    if (shouldSelect) _lastMetadata = metadata;
    notifyListeners();
  }

  Future<void> _resumeGatewayTask(ServerHistoryItem task, int userId) async {
    try {
      final bytes = await _service.waitForGatewayGeneration(
        task.id,
        onStatus: (status) {
          if (_backendUserId != userId || status != 'running') return;
          _state = _state.copyWith(
            generatedImages: _replaceGeneratedImageItem(
              task.id,
              (item) =>
                  item.copyWith(progress: GenerationTaskProgress.generating),
            ),
          );
          notifyListeners();
        },
      );
      if (_backendUserId != userId) return;
      _applyRestoredGatewayImage(task, userId, bytes);
    } catch (error) {
      debugPrint('Could not resume gateway task ${task.id}: $error');
      if (_backendUserId != userId) return;
      _state = _state.copyWith(
        generatedImages: _replaceGeneratedImageItem(
          task.id,
          (item) => item.copyWith(
            isLoading: false,
            progress: GenerationTaskProgress.failed,
            errorMessage: _formatError(error).message,
          ),
        ),
      );
      notifyListeners();
    }
  }

  Future<void> _resumeGatewayTasks(
    List<ServerHistoryItem> tasks,
    int userId,
  ) async {
    for (final task in tasks) {
      if (task.status != 'queued' && task.status != 'running') continue;
      if (_backendUserId != userId) return;
      await _resumeGatewayTask(task, userId);
    }
  }

  String? _itemFailureMessage(ServerHistoryItem item) =>
      taskItemFailureMessage(_l10n, item.status, item.errorCode);

  Map<String, dynamic> _historyMetadata(ServerHistoryItem task) => {
    ...task.generationMetadata,
    'seed': task.seed,
  };

  static GenerationTaskProgress _progressForGatewayStatus(String status) {
    return switch (status) {
      'running' => GenerationTaskProgress.generating,
      'failed' => GenerationTaskProgress.failed,
      'rejected' => GenerationTaskProgress.rejected,
      'cancelled' => GenerationTaskProgress.cancelled,
      _ => GenerationTaskProgress.queued,
    };
  }

  void updateCharacterLibraryNotifier(CharacterLibraryNotifier notifier) {
    _characterLibrary = notifier;
  }

  void updateDirectorRefNotifier(DirectorRefNotifier notifier) {
    _directorRefNotifier = notifier;
  }

  void updateVibeTransferNotifier(VibeTransferNotifier notifier) {
    _vibeTransferNotifier = notifier;
    notifier.updateService(_service);
    notifier.updateUseCurated(_state.useCurated);
  }

  void updateDirectorToolsNotifier(DirectorToolsNotifier notifier) {
    _directorToolsNotifier = notifier;
    notifier.updateService(_service);
  }

  void updateEnhanceNotifier(EnhanceNotifier notifier) {
    _enhanceNotifier = notifier;
    notifier.updateService(_service);
  }

  void updateTextGenNotifier(TextGenNotifier notifier) {
    _textGenNotifier = notifier;
    notifier.updateService(_textService);
  }

  void setOutputDir(String dir) {
    _outputDir = dir;
  }

  static List<String> _defaultActiveStyleNames(List<PromptStyle> styles) {
    for (final style in styles) {
      if (style.name == _qualityStyleName) return [style.name];
    }
    for (final style in styles) {
      if (style.name.toLowerCase().contains('quality')) return [style.name];
    }
    return styles.isNotEmpty ? [styles.first.name] : <String>[];
  }

  static List<String> _normalizeRestoredStyleNames(
    List<String> activeStyleNames,
    List<PromptStyle> styles,
  ) {
    if (activeStyleNames.length == 1 &&
        activeStyleNames.first == _legacyLightStyleName) {
      return _defaultActiveStyleNames(styles);
    }
    return activeStyleNames;
  }

  Future<void> _loadInitialData() async {
    await _tagService.loadTags();
    await _wildcardService.refresh();
    final presets = await _presetService.loadPresets();
    final styles = await _presetService.loadStyles();

    final initialActiveStyles = _defaultActiveStyleNames(styles);

    final apiKey = useBackendGateway
        ? serverManagedApiKey
        : await _prefs.getApiKey();
    _service = _serviceFactory(apiKey);
    _textService = NaiTextService(apiKey);
    _vibeTransferNotifier?.updateService(_service);
    _directorToolsNotifier?.updateService(_service);
    _enhanceNotifier?.updateService(_service);
    _textGenNotifier?.updateService(_textService);

    _state = _state.copyWith(
      presets: presets,
      styles: styles,
      activeStyleNames: _metadataImportedBeforeSessionReady
          ? null
          : initialActiveStyles,
      apiKey: apiKey,
      autoSaveImages: _prefs.autoSaveImages,
      showDirectorRefShelf: _prefs.showDirectorRefShelf,
      showVibeTransferShelf: _prefs.showVibeTransferShelf,
      brightTheme: _prefs.brightTheme,
      showEditButton: _prefs.showEditButton,
      showBgRemovalButton: _prefs.showBgRemovalButton,
      showUpscaleButton: _prefs.showUpscaleButton,
      showEnhanceButton: _prefs.showEnhanceButton,
      showDirectorToolsButton: _prefs.showDirectorToolsButton,
      furryMode: _prefs.furryMode,
      useCurated: _prefs.useCurated,
      characterEditorMode: _prefs.characterEditorMode,
    );
    loadCharacterPresets();
    notifyListeners();

    await _restoreSessionSnapshot();
    _sessionReady = true;
    if (_metadataImportedBeforeSessionReady) _scheduleSessionSave();

    fetchAnlas();
  }

  Future<void> fetchAnlas() async {
    final balance = await _service.getAnlasBalance();
    _state = _state.copyWith(anlas: balance, clearAnlas: balance == null);
    notifyListeners();
  }

  Future<void> reloadPresetsAndStyles() async {
    final presets = await _presetService.loadPresets();
    final styles = await _presetService.loadStyles();
    _state = _state.copyWith(presets: presets, styles: styles);
    notifyListeners();
  }

  Future<void> updateApiKey(String key) async {
    if (useBackendGateway) {
      _state = _state.copyWith(
        apiKey: serverManagedApiKey,
        hasAuthError: false,
      );
      notifyListeners();
      return;
    }
    await _prefs.setApiKey(key);
    _service = _serviceFactory(key);
    _textService = NaiTextService(key);
    _vibeTransferNotifier?.updateService(_service);
    _directorToolsNotifier?.updateService(_service);
    _enhanceNotifier?.updateService(_service);
    _textGenNotifier?.updateService(_textService);
    _state = _state.copyWith(apiKey: key, hasAuthError: false);
    notifyListeners();
  }

  Future<void> toggleAutoSave(bool value) async {
    await _prefs.setAutoSaveImages(value);
    _state = _state.copyWith(autoSaveImages: value);
    notifyListeners();
  }

  Future<void> toggleBrightTheme() async {
    final newVal = !_state.brightTheme;
    await _prefs.setBrightTheme(newVal);
    _state = _state.copyWith(brightTheme: newVal);
    notifyListeners();
  }

  Future<void> toggleDirectorRefShelf() async {
    final newVal = !_state.showDirectorRefShelf;
    await _prefs.setShowDirectorRefShelf(newVal);
    _state = _state.copyWith(showDirectorRefShelf: newVal);
    notifyListeners();
  }

  Future<void> toggleVibeTransferShelf() async {
    final newVal = !_state.showVibeTransferShelf;
    await _prefs.setShowVibeTransferShelf(newVal);
    _state = _state.copyWith(showVibeTransferShelf: newVal);
    notifyListeners();
  }

  Future<void> toggleShowEditButton() async {
    final newVal = !_state.showEditButton;
    await _prefs.setShowEditButton(newVal);
    _state = _state.copyWith(showEditButton: newVal);
    notifyListeners();
  }

  Future<void> toggleShowBgRemovalButton() async {
    final newVal = !_state.showBgRemovalButton;
    await _prefs.setShowBgRemovalButton(newVal);
    _state = _state.copyWith(showBgRemovalButton: newVal);
    notifyListeners();
  }

  Future<void> toggleShowUpscaleButton() async {
    final newVal = !_state.showUpscaleButton;
    await _prefs.setShowUpscaleButton(newVal);
    _state = _state.copyWith(showUpscaleButton: newVal);
    notifyListeners();
  }

  Future<void> toggleShowEnhanceButton() async {
    final newVal = !_state.showEnhanceButton;
    await _prefs.setShowEnhanceButton(newVal);
    _state = _state.copyWith(showEnhanceButton: newVal);
    notifyListeners();
  }

  Future<void> toggleShowDirectorToolsButton() async {
    final newVal = !_state.showDirectorToolsButton;
    await _prefs.setShowDirectorToolsButton(newVal);
    _state = _state.copyWith(showDirectorToolsButton: newVal);
    notifyListeners();
  }

  void setLoading(bool value) {
    _state = _state.copyWith(isLoading: value);
    notifyListeners();
  }

  void setAutoPositioning(bool value) {
    _state = _state.copyWith(autoPositioning: value);
    notifyListeners();
  }

  void clearError() {
    _state = _state.copyWith(clearErrorMessage: true);
    notifyListeners();
  }

  void clearAuthError() {
    _state = _state.copyWith(hasAuthError: false);
    notifyListeners();
  }

  void clearDuplicateWarning() {
    _state = _state.copyWith(duplicateImageDetected: false);
    notifyListeners();
  }

  void toggleSettings() {
    _state = _state.copyWith(isSettingsExpanded: !_state.isSettingsExpanded);
    notifyListeners();
  }

  void setDragging(bool dragging) {
    _state = _state.copyWith(isDragging: dragging);
    notifyListeners();
  }

  void updateSettings({
    double? width,
    double? height,
    double? steps,
    double? scale,
    String? sampler,
    bool? smea,
    bool? smeaDyn,
    bool? decrisper,
    bool? randomizeSeed,
    int? batchCount,
    List<String>? activeStyleNames,
    bool? isStyleEnabled,
    List<NaiCharacter>? characters,
    bool? furryMode,
    bool? useCurated,
  }) {
    if (furryMode != null) _prefs.setFurryMode(furryMode);
    if (useCurated != null) {
      _prefs.setUseCurated(useCurated);
      _vibeTransferNotifier?.updateUseCurated(useCurated);
    }
    _state = _state.copyWith(
      width: width,
      height: height,
      steps: steps,
      scale: scale,
      sampler: sampler,
      smea: smea,
      smeaDyn: smeaDyn,
      decrisper: decrisper,
      randomizeSeed: randomizeSeed,
      batchCount: batchCount,
      activeStyleNames: activeStyleNames,
      isStyleEnabled: isStyleEnabled,
      characters: characters,
      furryMode: furryMode,
      useCurated: useCurated,
    );
    notifyListeners();
  }

  void addCharacter({String name = '', String prompt = '', String uc = ''}) {
    final result = _characterManager.addCharacter(
      _state.characters,
      name: name,
      prompt: prompt,
      uc: uc,
    );
    if (result == null) return;
    _state = _state.copyWith(characters: result);
    notifyListeners();
  }

  void updateCharacter(int index, NaiCharacter character) {
    final result = _characterManager.updateCharacter(
      _state.characters,
      index,
      character,
    );
    if (result == null) return;
    _state = _state.copyWith(characters: result);
    notifyListeners();
  }

  void removeCharacter(int index) {
    final result = _characterManager.removeCharacter(
      _state.characters,
      _state.interactions,
      index,
    );
    if (result == null) return;
    _state = _state.copyWith(
      characters: result.characters,
      interactions: result.interactions,
    );
    notifyListeners();
  }

  void updateInteraction(
    NaiInteraction interaction, {
    NaiInteraction? replacing,
  }) {
    final updated = _characterManager.updateInteraction(
      _state.interactions,
      interaction,
      replacing: replacing,
    );
    _state = _state.copyWith(interactions: updated);
    notifyListeners();
  }

  void setGeneratedImage(Uint8List? image) {
    _state = _state.copyWith(
      generatedImage: image,
      clearGeneratedImage: image == null,
      generatedImages: const [],
      clearSelectedGeneratedImageId: true,
      autoFollowLatestImage: true,
    );
    notifyListeners();
  }

  void selectGeneratedImage(String id, {bool userInitiated = true}) {
    final selected = _state.generatedImages
        .where((item) => item.id == id)
        .firstOrNull;
    if (selected == null) return;

    _state = _state.copyWith(
      selectedGeneratedImageId: id,
      autoFollowLatestImage: userInitiated
          ? false
          : _state.autoFollowLatestImage,
      generatedImage: selected.bytes,
      clearGeneratedImage: selected.bytes == null,
      duplicateImageDetected: selected.duplicateImageDetected,
    );
    _lastMetadata = selected.metadata;
    _imageSaved = selected.saved;
    _lastSavedBasename = selected.savedBasename;
    notifyListeners();
  }

  List<GeneratedImageItem> _replaceGeneratedImageItem(
    String id,
    GeneratedImageItem Function(GeneratedImageItem item) update,
  ) {
    return _state.generatedImages
        .map((item) => item.id == id ? update(item) : item)
        .toList(growable: false);
  }

  void _markSelectedImageSaved(String basename) {
    final id = _state.selectedGeneratedImageId;
    if (id == null) return;
    _state = _state.copyWith(
      generatedImages: _replaceGeneratedImageItem(
        id,
        (item) => item.copyWith(saved: true, savedBasename: basename),
      ),
    );
  }

  Future<void> saveCurrentImage() async {
    if (_state.generatedImage == null || _lastMetadata == null) return;

    // Web has no filesystem; trigger a browser download of the image (with
    // metadata injected) instead so the SAVE button isn't a silent no-op.
    if (kIsWeb) {
      final baseName = _uniqueWebName(_buildFileName(_lastMetadata!));
      final bytesWithMetadata = await compute(injectMetadata, {
        'bytes': _state.generatedImage!,
        'metadata': _lastMetadata!,
      });
      final ok = downloadBytes(bytesWithMetadata, '$baseName.png');
      if (ok) {
        _webDownloadedNames.add('$baseName.png');
        _imageSaved = true;
        _lastSavedBasename = '$baseName.png';
        _markSelectedImageSaved('$baseName.png');
        notifyListeners();
      }
      return;
    }

    final savedFile = await _saveToDisk(_state.generatedImage!, _lastMetadata!);
    if (savedFile != null) {
      _galleryNotifier?.addFile(savedFile, DateTime.now());
      _imageSaved = true;
      _lastSavedBasename = p.basename(savedFile.path);
      _markSelectedImageSaved(_lastSavedBasename!);
      notifyListeners();

      await _autoExportIfEnabled(_state.generatedImage!, _lastMetadata!);
    }
  }

  /// Ensures image is saved and returns its basename for album assignment.
  Future<String?> ensureSavedAndGetBasename() async {
    if (_lastSavedBasename != null) return _lastSavedBasename;
    if (_state.generatedImage == null || _lastMetadata == null) return null;
    final savedFile = await _saveToDisk(_state.generatedImage!, _lastMetadata!);
    if (savedFile != null) {
      _galleryNotifier?.addFile(savedFile, DateTime.now());
      _imageSaved = true;
      _lastSavedBasename = p.basename(savedFile.path);
      notifyListeners();
      return _lastSavedBasename;
    }
    return null;
  }

  /// Copies the current generated image to the system clipboard.
  /// On desktop, uses super_clipboard for native image copy.
  /// On mobile, uses share_plus to share the image (native clipboard is unreliable).
  Future<void> copyToClipboard(BuildContext context) async {
    if (_state.generatedImage == null) return;

    // Mobile: use share sheet (super_clipboard's native lib is missing on Android)
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        final timestamp = DateFormat(
          'yyyyMMdd_HHmmssSSS',
        ).format(DateTime.now());
        await Share.shareXFiles([
          XFile.fromData(
            _state.generatedImage!,
            mimeType: 'image/png',
            name: 'Gen_$timestamp.png',
          ),
        ]);
      } catch (e) {
        if (context.mounted) {
          showAppSnackBar(
            context,
            'Share failed: $e',
            color: const Color(0xFFF44336),
          );
        }
      }
      return;
    }

    // Desktop: use super_clipboard for native image clipboard
    try {
      final item = DataWriterItem();
      item.add(Formats.png(_state.generatedImage!));
      final clipboard = SystemClipboard.instance;
      if (clipboard != null) {
        await clipboard.write([item]);
        if (context.mounted) {
          showAppSnackBar(
            context,
            'COPIED TO CLIPBOARD',
            color: const Color(0xFF4CAF50),
          );
        }
        return;
      }
    } catch (_) {}
    if (context.mounted) {
      showAppSnackBar(
        context,
        'CLIPBOARD NOT AVAILABLE',
        color: const Color(0xFFF44336),
      );
    }
  }

  /// Exports the current generated image to the custom folder, device gallery, or file dialog.
  Future<void> exportToDevice(BuildContext context) async {
    if (_state.generatedImage == null) return;
    try {
      final fallbackName = _lastMetadata != null
          ? _buildFileName(_lastMetadata!)
          : 'Gen_${DateFormat('yyyyMMdd_HHmmssSSS').format(DateTime.now())}';
      // Custom filename pattern (issue #27); `<digits>` can't count a SAF
      // tree or the device gallery, so it stays at 1 for those targets.
      final exportName = _patternedName(_lastMetadata, fallbackName);

      // If a custom export folder is set, write directly there (any platform)
      final customFolder = _prefs.exportFolderPath;
      if (customFolder.isNotEmpty && !kIsWeb) {
        // For a SAF (SD-card) target, verify we still hold the write grant —
        // the card may have been removed or permission revoked. For a legacy
        // plain filesystem path on Android, scoped storage makes it unreachable.
        // Either way a clear message beats the cryptic PathAccessException
        // users used to see (issue #13).
        final unreachable =
            SafExportService.isStalePlainPath(customFolder) ||
            (SafExportService.isSafUri(customFolder) &&
                !await SafExportService.instance.hasWriteAccess(customFolder));
        if (unreachable) {
          if (context.mounted) {
            showAppSnackBar(
              context,
              'EXPORT FOLDER UNAVAILABLE — RE-PICK IT IN SETTINGS',
              color: const Color(0xFFF44336),
            );
          }
          return;
        }
        if (SafExportService.isSafUri(customFolder)) {
          await _exportToFolder(
            _state.generatedImage!,
            customFolder,
            exportName,
          );
        } else {
          // Plain folders also honor the path pattern's auto-subfolders and
          // per-folder <digits> counting (issue #27).
          final target = await _patternedTarget(
            customFolder,
            _lastMetadata ?? const {},
            fallbackName,
          );
          await _exportToFolder(
            _state.generatedImage!,
            target.dir,
            target.base,
          );
        }
        if (context.mounted) {
          final label = SafExportService.isSafUri(customFolder)
              ? 'SD CARD'
              : p.basename(customFolder).toUpperCase();
          showAppSnackBar(
            context,
            'SAVED TO $label',
            color: const Color(0xFF4CAF50),
          );
        }
        return;
      }

      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await _exportBytesToMobileGallery(_state.generatedImage!, exportName);
        if (context.mounted) {
          showAppSnackBar(
            context,
            context.l.gallerySavedToDevice,
            color: const Color(0xFF4CAF50),
          );
        }
      } else {
        // Desktop: show save file dialog
        final result = await FilePicker.platform.saveFile(
          dialogTitle: 'Export Image',
          fileName: '$exportName.png',
          type: FileType.image,
        );
        if (result == null) return;
        await File(result).writeAsBytes(_state.generatedImage!);
        if (context.mounted) {
          showAppSnackBar(
            context,
            'SAVED TO ${p.basename(result).toUpperCase()}',
            color: const Color(0xFF4CAF50),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          'Export failed: $e',
          color: const Color(0xFFF44336),
        );
      }
    }
  }

  Future<void> _exportBytesToMobileGallery(
    Uint8List bytes,
    String exportName,
  ) async {
    final hasAccess = await Gal.hasAccess();
    if (!hasAccess) {
      final granted = await Gal.requestAccess();
      if (!granted) return;
    }
    final album = _prefs.exportAlbumName;
    await Gal.putImageBytes(bytes, name: exportName, album: album);
  }

  Future<void> _exportToFolder(
    Uint8List bytes,
    String folderPath,
    String fileName,
  ) async {
    // A SAF tree URI (content://…) targets a folder we can only reach through
    // the Storage Access Framework — e.g. a removable SD card (issue #13).
    if (SafExportService.isSafUri(folderPath)) {
      await SafExportService.instance.writePng(folderPath, fileName, bytes);
      return;
    }
    final dir = Directory(folderPath);
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File(await uniqueFilePath(folderPath, fileName, 'png'));
    await file.writeAsBytes(bytes);
  }

  Future<void> _autoExportIfEnabled(
    Uint8List bytes,
    Map<String, dynamic> metadata,
  ) async {
    if (!_prefs.autoExportToDevice) return;
    try {
      final fallbackName = _buildFileName(metadata);

      // Custom folder takes priority on all platforms — but a legacy plain
      // filesystem path is unreachable under Android scoped storage (issue
      // #13), so skip it and fall through to the device gallery rather than
      // throwing a PathAccessException into the catch below (which would
      // silently drop the auto-export).
      final customFolder = _prefs.exportFolderPath;
      if (customFolder.isNotEmpty &&
          !kIsWeb &&
          !SafExportService.isStalePlainPath(customFolder)) {
        if (SafExportService.isSafUri(customFolder)) {
          await _exportToFolder(
            bytes,
            customFolder,
            _patternedName(metadata, fallbackName),
          );
        } else {
          final target = await _patternedTarget(
            customFolder,
            metadata,
            fallbackName,
          );
          await _exportToFolder(bytes, target.dir, target.base);
        }
        return;
      }

      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await _exportBytesToMobileGallery(
          bytes,
          _patternedName(metadata, fallbackName),
        );
      } else if (!kIsWeb) {
        final target = await _patternedTarget(
          _outputDir,
          metadata,
          fallbackName,
        );
        await _exportToFolder(bytes, target.dir, target.base);
      }
    } catch (e) {
      debugPrint('Auto-export failed: $e');
    }
  }

  void removeInteraction(NaiInteraction interaction) {
    final updated = _characterManager.removeInteraction(
      _state.interactions,
      interaction,
    );
    _state = _state.copyWith(interactions: updated);
    notifyListeners();
  }

  // — Character Editor Mode —

  Future<void> setCharacterEditorMode(String mode) async {
    await _prefs.setCharacterEditorMode(mode);
    _state = _state.copyWith(characterEditorMode: mode);
    notifyListeners();
  }

  // — Character Presets —

  void loadCharacterPresets() {
    final presets = _characterManager.loadPresets();
    if (presets.isEmpty) return;
    _state = _state.copyWith(characterPresets: presets);
  }

  Future<void> saveCharacterPreset(CharacterPreset preset) async {
    final updated = List<CharacterPreset>.from(_state.characterPresets)
      ..add(preset);
    _state = _state.copyWith(characterPresets: updated);
    notifyListeners();
    await _characterManager.persistPresets(updated);
  }

  Future<void> deleteCharacterPreset(String id) async {
    final updated = List<CharacterPreset>.from(_state.characterPresets)
      ..removeWhere((p) => p.id == id);
    _state = _state.copyWith(characterPresets: updated);
    notifyListeners();
    await _characterManager.persistPresets(updated);
  }

  /// Merges imported character presets (from a backup pack) into the current
  /// set, keyed by id, and persists. Used by the pack importer.
  Future<void> importCharacterPresets(List<CharacterPreset> incoming) async {
    final merged = List<CharacterPreset>.from(_state.characterPresets);
    for (final preset in incoming) {
      final idx = merged.indexWhere((p) => p.id == preset.id);
      if (idx >= 0) {
        merged[idx] = preset;
      } else {
        merged.add(preset);
      }
    }
    _state = _state.copyWith(characterPresets: merged);
    notifyListeners();
    await _characterManager.persistPresets(merged);
  }

  void applyCharacterPreset(int charIndex, CharacterPreset preset) {
    final result = _characterManager.applyCharacterPreset(
      _state.characters,
      charIndex,
      preset,
    );
    if (result == null) return;
    _state = _state.copyWith(characters: result);
    notifyListeners();
  }

  static ({String? prefix, String? suffix, String? negative}) resolveStyles({
    required bool isStyleEnabled,
    required List<String> activeStyleNames,
    required List<PromptStyle> styles,
    bool furryMode = false,
  }) {
    String? combinedPrefix;
    String? combinedSuffix;
    String? styleNegativeContent;

    if (isStyleEnabled && activeStyleNames.isNotEmpty) {
      final List<String> prefixes = [];
      final List<String> suffixes = [];
      final List<String> negatives = [];

      for (final styleName in activeStyleNames) {
        try {
          final style = styles.firstWhere((s) => s.name == styleName);
          if (style.prefix.isNotEmpty) prefixes.add(style.prefix);
          if (style.suffix.isNotEmpty) suffixes.add(style.suffix);
          if (style.negativeContent.isNotEmpty) {
            negatives.add(style.negativeContent);
          }
        } catch (e) {
          debugPrint('resolveStyles: style "$styleName" not found');
        }
      }

      if (prefixes.isNotEmpty) combinedPrefix = prefixes.join("");
      if (suffixes.isNotEmpty) combinedSuffix = suffixes.join("");
      if (negatives.isNotEmpty) styleNegativeContent = negatives.join("");
    }

    if (furryMode) {
      combinedPrefix = "fur dataset, ${combinedPrefix ?? ''}";
    }

    return (
      prefix: combinedPrefix,
      suffix: combinedSuffix,
      negative: styleNegativeContent,
    );
  }

  void toggleStyle(String name) {
    final current = List<String>.from(_state.activeStyleNames);
    if (current.contains(name)) {
      current.remove(name);
    } else {
      current.add(name);
    }
    _state = _state.copyWith(activeStyleNames: current);
    notifyListeners();
  }

  static int _clampBatchCount(int value, int limit) {
    final max = math.max(1, math.min(limit, 10));
    return math.max(1, math.min(value, max));
  }

  @visibleForTesting
  static List<int> buildBatchSeeds({
    required int count,
    required bool randomize,
    required int fixedSeed,
    math.Random? random,
  }) {
    if (!randomize) {
      return List<int>.generate(
        count,
        (index) => (fixedSeed + index) & 0xFFFFFFFF,
      );
    }
    final source = random ?? math.Random();
    final used = <int>{};
    final seeds = <int>[];
    while (seeds.length < count) {
      final seed = _randomUint32(source);
      if (used.add(seed)) seeds.add(seed);
    }
    return seeds;
  }

  static int _randomUint32(math.Random source) {
    // Two 16-bit draws work consistently on native and web and cover the
    // complete uint32 seed range, including 0xFFFFFFFF.
    return source.nextInt(1 << 16) * (1 << 16) + source.nextInt(1 << 16);
  }

  /// The gateway's image rules and what the account may do, as of the last
  /// `/api/me`.
  void updateGatewayAccess(ImageRules? rules, GenerationAccess access) {
    if (identical(_rules, rules) &&
        _access.canFree == access.canFree &&
        _access.paid == access.paid) {
      return;
    }
    _rules = rules;
    _access = access;
    notifyListeners();
  }

  ImageRules? get imageRules => _rules;

  /// The price of the request that would be sent now, or null when there is
  /// none to show (no gateway, rules not loaded yet).
  GenerationQuote? get quote {
    final rules = _rules;
    if (!_service.viaGateway || rules == null) return null;
    ImageQuote? quote;
    String? invalidField;
    try {
      quote = quoteImageRequest(
        rules,
        previewRequest().body,
        images: _clampBatchCount(_state.batchCount, rules.batchLimit),
      );
    } on InvalidQuoteRequest catch (error) {
      invalidField = error.field;
    }
    return GenerationQuote(
      quote: quote,
      invalidField: invalidField,
      freeOnly: _access.freeOnly,
    );
  }

  /// The request [generate] would build now, with the prompt as typed:
  /// wildcards and aliases are not expanded because they never change what
  /// the request costs.
  ImageGenerationRequest previewRequest() => _buildRequest(
    seed: 0,
    prompts: _composePrompts(
      prompt: promptController.text,
      baseNegative: negativePromptController.text,
    ),
    characters: _state.characters,
    directorRefs: _directorRefNotifier?.buildPayload(),
    vibes: _vibeTransferNotifier?.buildPayload(),
  );

  /// Puts the size, steps and SMEA back inside what a free request allows.
  /// Only the user asks for this; nothing adjusts the settings by itself.
  void adjustToFreeParameters() {
    final rules = _rules;
    if (rules == null) return;
    final isFreeSize = rules.freeSizes.any(
      (size) =>
          size.width == _state.width.toInt() &&
          size.height == _state.height.toInt(),
    );
    final freeSize = isFreeSize || rules.freeSizes.isEmpty
        ? null
        : rules.freeSizes.first;
    updateSettings(
      width: freeSize?.width.toDouble(),
      height: freeSize?.height.toDouble(),
      steps: _state.steps > rules.freeMaxSteps
          ? rules.freeMaxSteps.toDouble()
          : null,
      smea: _state.smea ? false : null,
      smeaDyn: _state.smeaDyn ? false : null,
    );
  }

  /// The prompts of a request: the demo prefixes, the active styles and the
  /// merged negative prompt, from texts that are already expanded.
  _ComposedPrompts _composePrompts({
    required String prompt,
    required String baseNegative,
  }) {
    var finalPrompt = prompt;
    var negative = baseNegative;
    if (_galleryNotifier?.demoMode == true) {
      final demoPos = _prefs.demoPositivePrefix;
      if (demoPos.isNotEmpty) finalPrompt = '$demoPos, $finalPrompt';
      final demoNeg = _prefs.demoNegativePrefix;
      if (demoNeg.isNotEmpty) {
        negative = negative.isEmpty ? demoNeg : '$demoNeg, $negative';
      }
    }
    final styleResult = resolveStyles(
      isStyleEnabled: _state.isStyleEnabled,
      activeStyleNames: _state.activeStyleNames,
      styles: _state.styles,
      furryMode: _state.furryMode,
    );
    final styleNegative = styleResult.negative;
    return _ComposedPrompts(
      prompt: finalPrompt,
      baseNegative: negative,
      negative: styleNegative != null ? '$negative, $styleNegative' : negative,
      prefix: styleResult.prefix,
      suffix: styleResult.suffix,
    );
  }

  /// The one place a generation request is assembled, for the quote that is
  /// shown and for what is submitted. [directorRefs] and [vibes] are the
  /// payloads of the inputs that are actually sent.
  ImageGenerationRequest _buildRequest({
    required int seed,
    required _ComposedPrompts prompts,
    required List<NaiCharacter> characters,
    required DirectorRefPayload? directorRefs,
    required VibeTransferPayload? vibes,
  }) {
    return _service.buildImageGenerationRequest(
      prompt: prompts.prompt,
      negativePrompt: prompts.negative,
      width: _state.width.toInt(),
      height: _state.height.toInt(),
      scale: _state.scale,
      steps: _state.steps.toInt(),
      sampler: _state.sampler,
      smea: _state.smea,
      smeaDyn: _state.smeaDyn,
      decrisper: _state.decrisper,
      seed: seed,
      promptPrefix: prompts.prefix,
      promptSuffix: prompts.suffix,
      characters: characters,
      interactions: _state.interactions,
      useCoords: _state.characters.isNotEmpty ? !_state.autoPositioning : false,
      directorRefImages: directorRefs?.images,
      directorRefDescriptions: directorRefs?.descriptions,
      directorRefStrengths: directorRefs?.strengths,
      directorRefSecondaryStrengths: directorRefs?.secondaryStrengths,
      directorRefInfoExtracted: directorRefs?.infoExtracted,
      vibeTransferImages: vibes?.vibeVectors,
      vibeTransferStrengths: vibes?.strengths,
      vibeTransferInfoExtracted: vibes?.infoExtracted,
      useCurated: _state.useCurated,
    );
  }

  /// Submits [request] with the price computed from the rules. When the
  /// gateway answers with a different price (`quote_changed`, or the free
  /// allowance ran out), the user decides through [confirmQuote]; on yes the
  /// request is sent once more with the gateway's price.
  Future<GatewayGenerationSubmission> _submitGatewayBatch({
    required ImageGenerationRequest request,
    required List<int> seeds,
    required String clientRequestId,
    required QuoteConfirmer? confirmQuote,
  }) async {
    final rules = _rules ?? await _service.loadImageRules();
    final ImageQuote shown;
    try {
      shown = quoteImageRequest(rules, request.body, images: seeds.length);
    } on InvalidQuoteRequest catch (error) {
      throw error.toBackendException();
    }
    try {
      return await _service.submitGatewayGenerationBatch(
        request: request,
        seeds: seeds,
        clientRequestId: clientRequestId,
        expectedQuote: shown.toExpectedQuote(),
      );
    } on BackendException catch (error) {
      final server = _gatewayQuoteOf(error);
      // Red points cannot be offered to an account that cannot pay them.
      if (server == null ||
          confirmQuote == null ||
          (server.mode == QuoteMode.paid && !_access.canPay)) {
        rethrow;
      }
      final confirmed = await confirmQuote(
        QuoteConfirmation(
          shown: shown,
          serverMode: server.mode,
          serverPoints: server.points,
          reasons: server.reasons,
        ),
      );
      if (!confirmed) throw const _QuoteDeclined();
      return _service.submitGatewayGenerationBatch(
        request: request,
        seeds: seeds,
        clientRequestId: newClientRequestId(),
        expectedQuote: {'mode': server.mode, 'points': server.points},
      );
    }
  }

  /// The gateway's own quote carried by a price disagreement, if [error] is
  /// one.
  ({String mode, int points, List<String> reasons})? _gatewayQuoteOf(
    BackendException error,
  ) {
    final raw = error is QuoteChangedException
        ? error.quote
        : error.code == BackendErrorCode.freeAllowanceExhausted
        ? error.details['quote']
        : null;
    if (raw is! Map<String, dynamic>) return null;
    final mode = raw['mode'];
    final points = raw['points'];
    if (mode is! String || points is! num) return null;
    return (
      mode: mode,
      points: points.toInt(),
      reasons: [for (final reason in raw['reasons'] as List? ?? []) '$reason'],
    );
  }

  /// Submits the current prompt and settings. Through the gateway the price
  /// shown to the user is sent along; when the gateway prices the request
  /// differently, [confirmQuote] asks the user whether to go on at the
  /// gateway's price (declining submits nothing).
  Future<void> generate({
    int batchLimit = 1,
    QuoteConfirmer? confirmQuote,
  }) async {
    clearTagSuggestions();

    final batchCount = _clampBatchCount(_state.batchCount, batchLimit);
    final nonceSource = math.Random.secure();
    final batchRunId = [
      DateTime.now().microsecondsSinceEpoch.toRadixString(16),
      _randomUint32(nonceSource).toRadixString(16).padLeft(8, '0'),
      _randomUint32(nonceSource).toRadixString(16).padLeft(8, '0'),
    ].join('-');
    final gatewayBatch = _service.viaGateway;
    var gatewaySubmissionAccepted = false;
    final placeholders = List<GeneratedImageItem>.generate(
      batchCount,
      (index) => GeneratedImageItem(
        id: '$batchRunId-$index',
        batchIndex: index + 1,
        batchCount: batchCount,
        isLoading: true,
      ),
    );
    _state = gatewayBatch
        ? _state.copyWith(
            isLoading: true,
            hasAuthError: false,
            batchCount: batchCount,
            clearErrorMessage: true,
          )
        : _state.copyWith(
            isLoading: true,
            hasAuthError: false,
            batchCount: batchCount,
            generatedImages: placeholders,
            selectedGeneratedImageId: placeholders.first.id,
            autoFollowLatestImage: true,
            clearGeneratedImage: true,
            duplicateImageDetected: false,
            clearErrorMessage: true,
          );
    notifyListeners();

    // Keep screen/CPU awake during generation to prevent network drops
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        WakelockPlus.enable();
      } catch (_) {}
    }

    try {
      final processedPrompt = await _wildcardProcessor.process(
        promptController.text,
      );
      final prompts = _composePrompts(
        prompt: _tagService.resolveAliases(processedPrompt),
        baseNegative: _tagService.resolveAliases(
          await _wildcardProcessor.process(negativePromptController.text),
        ),
      );
      final finalPrompt = prompts.prompt;
      final baseNegative = prompts.baseNegative;
      final fullNegativePrompt = prompts.negative;
      final combinedPrefix = prompts.prefix;
      final combinedSuffix = prompts.suffix;

      final fixedSeed = int.tryParse(seedController.text) ?? 0;

      final dirPayload = _directorRefNotifier?.buildPayload();
      final vibePayload = _vibeTransferNotifier?.buildPayload();

      // Process wildcards in character prompts
      final processedCharacters = await Future.wait(
        _state.characters.map(
          (c) async => c.copyWith(
            prompt: _tagService.resolveAliases(
              await _wildcardProcessor.process(c.prompt),
            ),
            uc: _tagService.resolveAliases(
              await _wildcardProcessor.process(c.uc),
            ),
          ),
        ),
      );

      final seeds = buildBatchSeeds(
        count: batchCount,
        randomize: _state.randomizeSeed,
        fixedSeed: fixedSeed,
      );
      if (_state.randomizeSeed) {
        seedController.text = seeds.last.toString();
      }

      ImageGenerationRequest buildRequest(int seed) => _buildRequest(
        seed: seed,
        prompts: prompts,
        characters: processedCharacters,
        directorRefs: dirPayload,
        vibes: vibePayload,
      );

      Future<void> applyResult(int index, GenerationResult result) async {
        final currentItem = _state.generatedImages.firstWhere(
          (item) => item.batchIndex == index + 1,
        );
        final itemId = currentItem.id;
        final seed = seeds[index];

        // Save active style info in metadata for round-trip restore.
        result.metadata['active_style_names'] =
            (_state.isStyleEnabled && _state.activeStyleNames.isNotEmpty)
            ? _state.activeStyleNames
            : <String>[];
        result.metadata['is_style_enabled'] = _state.isStyleEnabled;
        result.metadata['original_negative_prompt'] = baseNegative;
        if (batchCount > 1) {
          result.metadata['batch_index'] = index + 1;
          result.metadata['batch_count'] = batchCount;
        }

        final isDuplicate =
            _previousImageBytes != null &&
            listEquals(result.imageBytes, _previousImageBytes);
        _previousImageBytes = Uint8List.fromList(result.imageBytes);

        final completedItem = currentItem.copyWith(
          bytes: result.imageBytes,
          metadata: result.metadata,
          seed: seed,
          isLoading: false,
          duplicateImageDetected: isDuplicate,
          saved: false,
          clearErrorMessage: true,
        );
        final shouldSelect =
            _state.autoFollowLatestImage ||
            _state.selectedGeneratedImageId == itemId ||
            _state.selectedGeneratedImageId == null;
        if (shouldSelect) {
          _lastMetadata = result.metadata;
          _imageSaved = false;
          _lastSavedBasename = null;
        }
        _state = _state.copyWith(
          generatedImages: _replaceGeneratedImageItem(
            itemId,
            (_) => completedItem,
          ),
          selectedGeneratedImageId: shouldSelect ? itemId : null,
          generatedImage: shouldSelect ? result.imageBytes : null,
          duplicateImageDetected: isDuplicate,
        );
        notifyListeners();

        if (_state.autoSaveImages) {
          final savedFile = await _saveToDisk(
            result.imageBytes,
            result.metadata,
          );
          if (savedFile != null) {
            _galleryNotifier?.addFile(savedFile, DateTime.now());
            final basename = p.basename(savedFile.path);
            final savedImages = _replaceGeneratedImageItem(
              itemId,
              (item) => item.copyWith(saved: true, savedBasename: basename),
            );
            if (_state.selectedGeneratedImageId == itemId) {
              _imageSaved = true;
              _lastSavedBasename = basename;
            }
            _state = _state.copyWith(generatedImages: savedImages);
            notifyListeners();
            await _autoExportIfEnabled(result.imageBytes, result.metadata);
          }
        }
      }

      if (gatewayBatch) {
        final preparedRequest = buildRequest(seeds.first);
        final submission = await _submitGatewayBatch(
          request: preparedRequest,
          seeds: seeds,
          clientRequestId: batchRunId,
          confirmQuote: confirmQuote,
        );
        final submittedItems = submission.items.toList()
          ..sort((a, b) => a.batchIndex.compareTo(b.batchIndex));
        final acceptedImages = List<GeneratedImageItem>.generate(batchCount, (
          index,
        ) {
          final accepted = submittedItems[index];
          final metadata = Map<String, dynamic>.from(
            buildRequest(seeds[index]).metadata,
          );
          return GeneratedImageItem(
            id: accepted.id,
            batchIndex: index + 1,
            batchCount: batchCount,
            metadata: metadata,
            seed: seeds[index],
            isLoading: true,
            progress: _progressForGatewayStatus(accepted.status),
          );
        });
        _state = _state.copyWith(
          generatedImages: acceptedImages,
          selectedGeneratedImageId: acceptedImages.first.id,
          autoFollowLatestImage: true,
          clearGeneratedImage: true,
          duplicateImageDetected: false,
        );
        gatewaySubmissionAccepted = true;
        notifyListeners();

        var retryDelay = const Duration(seconds: 1);
        var taskFetchFailures = 0;
        final downloadFailures = <String, int>{};
        while (true) {
          ServerGenerationTask task;
          try {
            task = await _historyApi.fetchGenerationTask(submission.taskId);
            retryDelay = const Duration(seconds: 1);
            taskFetchFailures = 0;
          } on BackendException catch (error) {
            if (error.isNotAuthenticated ||
                error.statusCode == 403 ||
                error.statusCode == 404) {
              rethrow;
            }
            taskFetchFailures++;
            if (taskFetchFailures >= 8) rethrow;
            await Future.delayed(retryDelay);
            retryDelay = Duration(
              seconds: (retryDelay.inSeconds * 2).clamp(1, 15),
            );
            continue;
          }

          var changed = false;
          for (final serverItem in task.items) {
            final existing = _state.generatedImages
                .where((item) => item.id == serverItem.id)
                .firstOrNull;
            if (existing == null || existing.isTerminal) continue;
            final progress = _progressForGatewayStatus(serverItem.status);
            final loading =
                serverItem.status == 'queued' || serverItem.status == 'running';
            _state = _state.copyWith(
              generatedImages: _replaceGeneratedImageItem(
                serverItem.id,
                (item) => item.copyWith(
                  progress: progress,
                  isLoading: loading || serverItem.status == 'success',
                  errorMessage: _itemFailureMessage(serverItem),
                ),
              ),
            );
            changed = true;
          }
          if (changed) notifyListeners();

          var successfulDownloadsComplete = true;
          for (final serverItem in task.items.where(
            (item) => item.status == 'success',
          )) {
            final existing = _state.generatedImages
                .where((item) => item.id == serverItem.id)
                .firstOrNull;
            if (existing == null || existing.isTerminal) continue;
            try {
              final bytes = await _historyApi.fetchImageBytes(serverItem.id);
              final index =
                  serverItem.batchIndex ??
                  _state.generatedImages.indexWhere(
                    (item) => item.id == serverItem.id,
                  );
              if (index < 0 || index >= batchCount) continue;
              final metadata = Map<String, dynamic>.from(
                buildRequest(seeds[index]).metadata,
              );
              await applyResult(
                index,
                GenerationResult(imageBytes: bytes, metadata: metadata),
              );
            } on BackendException catch (error) {
              if (error.isNotAuthenticated) rethrow;
              final failures = (downloadFailures[serverItem.id] ?? 0) + 1;
              downloadFailures[serverItem.id] = failures;
              final statusCode = error.statusCode;
              final permanent =
                  statusCode == 403 ||
                  (statusCode == 404 && failures >= 3) ||
                  failures >= 8;
              if (!permanent) {
                successfulDownloadsComplete = false;
                continue;
              }
              _state = _state.copyWith(
                generatedImages: _replaceGeneratedImageItem(
                  serverItem.id,
                  (item) => item.copyWith(
                    isLoading: false,
                    progress: GenerationTaskProgress.failed,
                    errorMessage: _formatError(error).message,
                  ),
                ),
              );
              notifyListeners();
            }
          }

          final statusesTerminal =
              task.items.isNotEmpty &&
              task.items.every(
                (item) =>
                    item.status == 'success' ||
                    item.status == 'failed' ||
                    item.status == 'rejected' ||
                    item.status == 'cancelled',
              );
          if (statusesTerminal && successfulDownloadsComplete) break;
          await Future.delayed(const Duration(seconds: 1));
        }
      } else {
        Object? firstError;
        await Future.wait(
          List<Future<void>>.generate(batchCount, (index) async {
            try {
              final result = await _service.generateImage(
                prompt: finalPrompt,
                negativePrompt: fullNegativePrompt,
                width: _state.width.toInt(),
                height: _state.height.toInt(),
                scale: _state.scale,
                steps: _state.steps.toInt(),
                sampler: _state.sampler,
                smea: _state.smea,
                smeaDyn: _state.smeaDyn,
                decrisper: _state.decrisper,
                seed: seeds[index],
                promptPrefix: combinedPrefix,
                promptSuffix: combinedSuffix,
                characters: processedCharacters,
                interactions: _state.interactions,
                useCoords: _state.characters.isNotEmpty
                    ? !_state.autoPositioning
                    : false,
                directorRefImages: dirPayload?.images,
                directorRefDescriptions: dirPayload?.descriptions,
                directorRefStrengths: dirPayload?.strengths,
                directorRefSecondaryStrengths: dirPayload?.secondaryStrengths,
                directorRefInfoExtracted: dirPayload?.infoExtracted,
                vibeTransferImages: vibePayload?.vibeVectors,
                vibeTransferStrengths: vibePayload?.strengths,
                vibeTransferInfoExtracted: vibePayload?.infoExtracted,
                useCurated: _state.useCurated,
              );
              await applyResult(index, result);
            } catch (error) {
              firstError ??= error;
              _state = _state.copyWith(
                generatedImages: _replaceGeneratedImageItem(
                  placeholders[index].id,
                  (item) => item.copyWith(
                    isLoading: false,
                    progress: GenerationTaskProgress.failed,
                    errorMessage: _formatError(error).message,
                  ),
                ),
              );
              notifyListeners();
            }
          }),
        );
        if (firstError != null) {
          final capturedError = firstError!;
          if (capturedError is UnauthorizedException) throw capturedError;
          final error = _formatError(capturedError);
          _state = _state.copyWith(
            errorMessage: error.message,
            errorTone: error.tone,
            errorSuggestRandomSeed: error.suggestRandomSeed,
          );
        }
      }
    } on UnauthorizedException {
      _state = _state.copyWith(hasAuthError: true);
    } on _QuoteDeclined {
      // The user chose not to pay the gateway's price: nothing was submitted.
    } catch (e) {
      debugPrint("Generation error: $e");
      final error = _formatError(e);
      _state = _state.copyWith(
        errorMessage: error.message,
        errorTone: error.tone,
        errorSuggestRandomSeed: error.suggestRandomSeed,
      );
    } finally {
      final settleWorkspace = !gatewayBatch || gatewaySubmissionAccepted;
      final settledImages = settleWorkspace
          ? _state.generatedImages
                .map(
                  (item) =>
                      item.isLoading ? item.copyWith(isLoading: false) : item,
                )
                .toList(growable: false)
          : _state.generatedImages;
      _state = _state.copyWith(
        isLoading: false,
        generatedImages: settledImages,
      );
      notifyListeners();
      fetchAnlas();
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        try {
          WakelockPlus.disable();
        } catch (_) {}
      }
    }
  }

  /// Generates a NovelAI-style filename from the prompt and seed.
  /// Format: `<prompt> s-<seed>.png`, matching NAI's own convention (issue #28).
  String _buildFileName(
    Map<String, dynamic> metadata, {
    String prefix = 'Gen',
  }) {
    try {
      final prompt = (metadata['prompt'] as String? ?? '').trim();
      final seed = metadata['seed']?.toString() ?? '';
      if (prompt.isNotEmpty && seed.isNotEmpty) {
        return naiFilenameBase(prompt, seed);
      }
    } catch (_) {}
    // Fallback to timestamp
    return '${prefix}_${DateFormat('yyyyMMdd_HHmmssSSS').format(DateTime.now())}';
  }

  /// Name of the default-save album — the album a fresh save lands in — for
  /// the `<album>` pattern token, or '' when none is configured.
  String _defaultSaveAlbumName() {
    final id = _prefs.defaultSaveAlbumId;
    if (id == null || id.isEmpty) return '';
    final albums = _galleryNotifier?.albums;
    if (albums == null) return '';
    for (final album in albums) {
      if (album.id == id) return album.name;
    }
    return '';
  }

  /// Applies the custom filename pattern (issue #27) with [sequence] for
  /// `<digits>` tokens. Returns [fallback] when no pattern is set, when
  /// prompt/seed are unavailable (the same condition under which the
  /// NAI-style default itself applies), or when the pattern expands to
  /// nothing. Used directly for targets whose contents we can't cheaply
  /// count (SAF trees, the device gallery) — there `<digits>` stays at 1.
  String _patternedName(
    Map<String, dynamic>? metadata,
    String fallback, {
    int sequence = 1,
  }) {
    final pattern = _prefs.filenamePattern;
    if (pattern.isEmpty || metadata == null) return fallback;
    final prompt = (metadata['prompt'] as String? ?? '').trim();
    final seed = metadata['seed']?.toString() ?? '';
    if (prompt.isEmpty || seed.isEmpty) return fallback;
    final expanded = expandFilenamePattern(
      pattern,
      FilenamePatternContext(
        prompt: prompt,
        seed: seed,
        savedAt: DateTime.now(),
        albumName: _defaultSaveAlbumName(),
        sequence: sequence,
      ),
    );
    return expanded.isEmpty ? fallback : expanded;
  }

  /// Resolves the destination folder and filename base for a plain-filesystem
  /// save under [baseDir] from the pattern settings (issue #27). The path
  /// pattern can add auto-subfolders; `<digits>` counts the images already in
  /// the final folder, so counters reset per subfolder.
  Future<_SaveTarget> _patternedTarget(
    String baseDir,
    Map<String, dynamic> metadata,
    String fallbackBase,
  ) async {
    final pathPattern = _prefs.savePathPattern;
    final fnPattern = _prefs.filenamePattern;
    final prompt = (metadata['prompt'] as String? ?? '').trim();
    final seed = metadata['seed']?.toString() ?? '';
    if ((pathPattern.isEmpty && fnPattern.isEmpty) ||
        prompt.isEmpty ||
        seed.isEmpty) {
      return _SaveTarget(baseDir, fallbackBase);
    }
    final savedAt = DateTime.now();
    final albumName = _defaultSaveAlbumName();
    var dirPath = baseDir;
    final sub = expandSavePathPattern(
      pathPattern,
      FilenamePatternContext(
        prompt: prompt,
        seed: seed,
        savedAt: savedAt,
        albumName: albumName,
      ),
    );
    if (sub.isNotEmpty) dirPath = p.join(dirPath, sub);
    var base = fallbackBase;
    if (fnPattern.isNotEmpty) {
      // Only pay for a directory listing when the pattern actually counts.
      final seq = fnPattern.contains('<digits')
          ? await nextImageSequence(dirPath)
          : 1;
      final expanded = expandFilenamePattern(
        fnPattern,
        FilenamePatternContext(
          prompt: prompt,
          seed: seed,
          savedAt: savedAt,
          albumName: albumName,
          sequence: seq,
        ),
      );
      if (expanded.isNotEmpty) base = expanded;
    }
    return _SaveTarget(dirPath, base);
  }

  /// Returns [baseName] if it hasn't been downloaded this session, otherwise
  /// appends `_(2)`, `_(3)`, … — the same convention as [uniqueFilePath], but
  /// tracked in memory since web has no filesystem to probe. The returned name
  /// is the bare base (no extension); the caller adds `.png`.
  String _uniqueWebName(String baseName) {
    if (!_webDownloadedNames.contains('$baseName.png')) return baseName;
    var i = 2;
    while (_webDownloadedNames.contains('${baseName}_($i).png')) {
      i++;
    }
    return '${baseName}_($i)';
  }

  Future<File?> _saveToDisk(
    Uint8List bytes,
    Map<String, dynamic> metadata, {
    String prefix = 'Gen',
    String? timestamp,
  }) async {
    // No filesystem on web. Bytes remain in memory; users use the existing
    // download/share path (XFile / share_plus) to get the image off-app.
    if (kIsWeb) return null;
    try {
      // Explicit-timestamp saves (img2img Src/Gen pairs) keep their fixed
      // names and flat location; the pattern settings apply to standard
      // generation saves (issue #27).
      final target = timestamp != null
          ? _SaveTarget(_outputDir, '${prefix}_$timestamp')
          : await _patternedTarget(
              _outputDir,
              metadata,
              _buildFileName(metadata, prefix: prefix),
            );
      final directory = Directory(target.dir);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final filePath = await uniqueFilePath(directory.path, target.base, 'png');

      final bytesWithMetadata = await compute(injectMetadata, {
        'bytes': bytes,
        'metadata': metadata,
      });

      final file = File(filePath);
      await file.writeAsBytes(bytesWithMetadata);
      return file;
    } catch (e) {
      debugPrint("Save error: $e");
      return null;
    }
  }

  void handleTagSuggestions(String text, TextSelection selection) {
    if (_galleryNotifier?.demoMode == true) {
      clearTagSuggestions();
      return;
    }
    _tagDebounce?.cancel();
    _tagDebounce = Timer(const Duration(milliseconds: 150), () {
      final result = TagSuggestionHelper.getSuggestions(
        text: text,
        selection: selection,
        tagService: _tagService,
        supportFavorites: true,
        wildcardService: _wildcardService,
        characterSuggestionsFor: _characterLibrary == null
            ? null
            : (q) => _characterLibrary!.suggestionTags(q),
      );
      _state = _state.copyWith(
        tagSuggestions: result.suggestions,
        currentTagQuery: result.query,
      );
      notifyListeners();
    });
  }

  void clearTagSuggestions() {
    if (_state.tagSuggestions.isEmpty) return;
    _state = _state.copyWith(tagSuggestions: [], currentTagQuery: "");
    notifyListeners();
  }

  ApplyTagResult applyTagSuggestion(DanbooruTag tag) {
    // A saved character picked from the main prompt box can either be added as
    // its own character card (default) or inserted as plain expanded tags into
    // the main prompt, controlled by the insert-target preference.
    if (tag.typeName == 'saved_character' &&
        _prefs.charInsertTarget == 'editor') {
      final result = _addSavedCharacterAsCard(tag);
      // Clear the just-typed query from the prompt regardless of outcome, so the
      // partial name the user typed doesn't linger.
      _clearCurrentQueryWord();
      _state = _state.copyWith(tagSuggestions: [], currentTagQuery: "");
      notifyListeners();
      return result;
    }

    TagSuggestionHelper.applyTag(promptController, tag);
    // A saved character inserted into the GLOBAL prompt routes its negative
    // tags to the GLOBAL negative prompt.
    if (tag.typeName == 'saved_character') {
      TagSuggestionHelper.appendNegatives(
        negativePromptController,
        tag.negativeExpansion,
      );
    }
    _state = _state.copyWith(tagSuggestions: [], currentTagQuery: "");
    notifyListeners();
    return ApplyTagResult.insertedIntoPrompt;
  }

  /// Adds [tag] (a `saved_character` suggestion) as a new character card, with
  /// its expansion as the card prompt and negative expansion as the card UC.
  /// Returns [ApplyTagResult.characterLimitReached] without mutating state when
  /// the editor is already at the 6-character maximum.
  ApplyTagResult _addSavedCharacterAsCard(DanbooruTag tag) {
    if (_state.characters.length >= CharacterManager.maxCharacters) {
      return ApplyTagResult.characterLimitReached;
    }
    final prompt = (tag.expansion != null && tag.expansion!.trim().isNotEmpty)
        ? tag.expansion!.trim()
        : tag.tag;
    addCharacter(
      name: tag.tag,
      prompt: prompt,
      uc: (tag.negativeExpansion ?? '').trim(),
    );
    // Ensure the editor is expanded so the new card is visible.
    if (_state.characterEditorMode != 'expanded') {
      setCharacterEditorMode('expanded');
    }
    return ApplyTagResult.addedCharacterCard;
  }

  /// Removes the partial word the user was typing at the cursor in the main
  /// prompt (the text after the last `,`/`|` delimiter), trimming any trailing
  /// separator left behind. Used when a saved character is routed to the editor
  /// rather than inserted inline.
  void _clearCurrentQueryWord() {
    final text = promptController.text;
    final sel = promptController.selection;
    final cursor = sel.isValid ? sel.baseOffset : text.length;
    final beforeCursor = text.substring(0, cursor);
    final afterCursor = text.substring(cursor);
    final lastDelimiter = beforeCursor.lastIndexOf(RegExp(r'[,|]'));
    final prefix = beforeCursor.substring(0, lastDelimiter + 1).trimRight();
    final newText = (prefix.isEmpty ? '' : '$prefix ') + afterCursor.trimLeft();
    promptController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: prefix.isEmpty ? 0 : prefix.length + 1,
      ),
    );
  }

  /// Parse metadata from a PNG file without applying it to state.
  Future<MetadataImportResult> parseImageMetadata(File file) async {
    return _metadataImportService.parseImageMetadata(
      file,
      smartStyleImport: _prefs.smartStyleImport,
      availableStyles: _state.styles,
    );
  }

  /// Parse metadata from raw image bytes without applying it to state.
  Future<MetadataImportResult> parseImageMetadataBytes(Uint8List bytes) async {
    return _metadataImportService.parseImageMetadataBytes(
      bytes,
      smartStyleImport: _prefs.smartStyleImport,
      availableStyles: _state.styles,
    );
  }

  MetadataImportResult parseHistoryParameters(ServerHistoryItem item) {
    return _metadataImportService.parseGenerationParameters(
      item.generationMetadata,
    );
  }

  /// Apply a parsed metadata result, importing only the selected categories.
  void applyImportedMetadata(
    MetadataImportResult result,
    Set<ImportCategory> categories,
  ) {
    // Startup can still be loading tags/styles while history is open. An
    // explicit import must win over the older saved editor session.
    if (!_sessionReady && categories.isNotEmpty) {
      _metadataImportedBeforeSessionReady = true;
    }
    if (categories.contains(ImportCategory.prompt)) {
      promptController.value = TextEditingValue(
        text: result.prompt,
        selection: TextSelection.collapsed(offset: result.prompt.length),
      );
    }
    if (categories.contains(ImportCategory.negativePrompt)) {
      negativePromptController.value = TextEditingValue(
        text: result.negativePrompt,
        selection: TextSelection.collapsed(
          offset: result.negativePrompt.length,
        ),
      );
    }
    if (categories.contains(ImportCategory.seed) && result.seed != null) {
      seedController.text = result.seed!;
    }

    _state = _state.copyWith(
      width: categories.contains(ImportCategory.settings) ? result.width : null,
      height: categories.contains(ImportCategory.settings)
          ? result.height
          : null,
      scale: categories.contains(ImportCategory.settings) ? result.scale : null,
      steps: categories.contains(ImportCategory.settings) ? result.steps : null,
      sampler: categories.contains(ImportCategory.settings)
          ? result.sampler
          : null,
      smea: categories.contains(ImportCategory.settings) ? result.smea : null,
      smeaDyn: categories.contains(ImportCategory.settings)
          ? result.smeaDyn
          : null,
      decrisper: categories.contains(ImportCategory.settings)
          ? result.decrisper
          : null,
      randomizeSeed: categories.contains(ImportCategory.seed) ? false : null,
      generatedImage: result.imageBytes,
      generatedImages: result.imageBytes != null ? const [] : null,
      clearSelectedGeneratedImageId: result.imageBytes != null,
      autoFollowLatestImage: result.imageBytes != null ? true : null,
      activeStyleNames: categories.contains(ImportCategory.styles)
          ? result.activeStyleNames
          : null,
      isStyleEnabled: categories.contains(ImportCategory.styles)
          ? result.isStyleEnabled
          : null,
      characters: categories.contains(ImportCategory.characters)
          ? result.characters
          : null,
      interactions: categories.contains(ImportCategory.characters)
          ? result.interactions
          : null,
      autoPositioning: categories.contains(ImportCategory.characters)
          ? result.autoPositioning
          : null,
    );
    notifyListeners();
  }

  /// Import all metadata from a PNG file (used by drag-and-drop).
  Future<void> importImageMetadata(File file) async {
    _state = _state.copyWith(isLoading: true);
    notifyListeners();

    try {
      final result = await parseImageMetadata(file);
      applyImportedMetadata(result, ImportCategory.values.toSet());
    } catch (e) {
      debugPrint("Metadata extraction error: $e");
      rethrow;
    } finally {
      _state = _state.copyWith(isLoading: false);
      notifyListeners();
    }
  }

  Future<void> savePreset(String name) async {
    final newPreset = GenerationPreset(
      name: name,
      prompt: promptController.text,
      negativePrompt: negativePromptController.text,
      width: _state.width,
      height: _state.height,
      scale: _state.scale,
      steps: _state.steps,
      sampler: _state.sampler,
      smea: _state.smea,
      smeaDyn: _state.smeaDyn,
      decrisper: _state.decrisper,
      characters: List<NaiCharacter>.from(_state.characters),
      interactions: List<NaiInteraction>.from(_state.interactions),
      directorReferences: _directorRefNotifier?.references.toList() ?? const [],
      vibeTransfers: _vibeTransferNotifier?.vibes.toList() ?? const [],
    );

    final updatedPresets = List<GenerationPreset>.from(_state.presets)
      ..add(newPreset);
    _state = _state.copyWith(presets: updatedPresets);
    notifyListeners();
    await _presetService.savePresets(updatedPresets);
  }

  void applyPreset(GenerationPreset preset) {
    promptController.text = preset.prompt;
    negativePromptController.text = preset.negativePrompt;
    _state = _state.copyWith(
      width: preset.width,
      height: preset.height,
      scale: preset.scale,
      steps: preset.steps,
      sampler: preset.sampler,
      smea: preset.smea,
      smeaDyn: preset.smeaDyn,
      decrisper: preset.decrisper,
      characters: List<NaiCharacter>.from(preset.characters),
      interactions: List<NaiInteraction>.from(preset.interactions),
    );
    if (preset.directorReferences.isNotEmpty) {
      _directorRefNotifier?.setReferences(preset.directorReferences);
    } else {
      _directorRefNotifier?.clearAll();
    }
    if (preset.vibeTransfers.isNotEmpty) {
      _vibeTransferNotifier?.setVibes(preset.vibeTransfers);
    } else {
      _vibeTransferNotifier?.clearAll();
    }
    notifyListeners();
  }

  Future<void> refreshPresets() async {
    final presets = await _presetService.loadPresets();
    _state = _state.copyWith(presets: presets);
    notifyListeners();
  }

  Future<void> refreshStyles() async {
    final styles = await _presetService.loadStyles();
    _state = _state.copyWith(styles: styles);
    notifyListeners();
  }

  Future<void> deletePreset(int index) async {
    final updatedPresets = List<GenerationPreset>.from(_state.presets)
      ..removeAt(index);
    _state = _state.copyWith(presets: updatedPresets);
    notifyListeners();
    await _presetService.savePresets(updatedPresets);
  }

  Future<Uint8List?> generateQuickPreview(
    String tag, {
    TagPreviewSettings? previewSettings,
  }) async {
    final settings = previewSettings ?? TagPreviewSettings();

    try {
      final seed = settings.seed ?? _randomUint32(math.Random());
      final result = await _service.generateImage(
        prompt: "${settings.positivePrompt}, $tag",
        negativePrompt: settings.negativePrompt,
        width: settings.width.toInt(),
        height: settings.height.toInt(),
        scale: settings.scale,
        steps: settings.steps,
        sampler: settings.sampler,
        seed: seed,
        useCurated: _state.useCurated,
      );

      // Auto-save the preview as well, so it's in the gallery
      if (_state.autoSaveImages) {
        final savedFile = await _saveToDisk(result.imageBytes, result.metadata);
        if (savedFile != null) {
          _galleryNotifier?.addFile(savedFile, DateTime.now());
          await _autoExportIfEnabled(result.imageBytes, result.metadata);
        }
      }

      return result.imageBytes;
    } catch (e) {
      debugPrint("Quick preview error: $e");
      return null;
    }
  }

  Future<Uint8List?> generateCascadeBeat(CascadeStitchedRequest request) async {
    _state = _state.copyWith(isLoading: true, hasAuthError: false);
    notifyListeners();

    try {
      final seed = _randomUint32(math.Random());

      // Process wildcards in cascade prompts
      final processedCaption = await _wildcardProcessor.process(
        request.baseCaption,
      );
      final processedNeg = await _wildcardProcessor.process(
        request.negativePrompt,
      );
      final processedChars = await Future.wait(
        request.characters.map(
          (c) async => c.copyWith(
            prompt: await _wildcardProcessor.process(c.prompt),
            uc: await _wildcardProcessor.process(c.uc),
          ),
        ),
      );

      final combinedNegative = [
        defaultNegativePrompt,
        processedNeg,
      ].where((s) => s.isNotEmpty).join(', ');

      final cascadePrompt = _state.furryMode
          ? "fur dataset, $processedCaption"
          : processedCaption;

      final result = await _service.generateImage(
        prompt: cascadePrompt,
        negativePrompt: combinedNegative,
        width: request.width,
        height: request.height,
        scale: request.scale,
        steps: request.steps,
        sampler: request.sampler,
        seed: seed,
        characters: processedChars,
        useCoords: request.useCoords,
        useCurated: _state.useCurated,
      );

      _lastMetadata = result.metadata;
      _imageSaved = false;
      _state = _state.copyWith(
        generatedImage: result.imageBytes,
        generatedImages: const [],
        clearSelectedGeneratedImageId: true,
        autoFollowLatestImage: true,
      );

      if (_state.autoSaveImages) {
        final savedFile = await _saveToDisk(result.imageBytes, result.metadata);
        if (savedFile != null) {
          _galleryNotifier?.addFile(savedFile, DateTime.now());
          _imageSaved = true;
          await _autoExportIfEnabled(result.imageBytes, result.metadata);
        }
      }

      return result.imageBytes;
    } on UnauthorizedException {
      _state = _state.copyWith(hasAuthError: true);
      return null;
    } catch (e) {
      debugPrint("Cascade generation error: $e");
      final error = _formatError(e);
      _state = _state.copyWith(
        errorMessage: error.message,
        errorTone: error.tone,
        errorSuggestRandomSeed: error.suggestRandomSeed,
      );
      return null;
    } finally {
      _state = _state.copyWith(isLoading: false);
      notifyListeners();
      fetchAnlas();
    }
  }

  Future<Uint8List?> generateImg2Img(
    Img2ImgRequest request, {
    Uint8List? sourceImageBytes,
  }) async {
    _state = _state.copyWith(isLoading: true, hasAuthError: false);
    notifyListeners();

    try {
      final seed = _state.randomizeSeed
          ? _randomUint32(math.Random())
          : (int.tryParse(seedController.text) ?? _randomUint32(math.Random()));
      if (_state.randomizeSeed) seedController.text = seed.toString();

      final dirPayload = _directorRefNotifier?.buildPayload();
      final vibePayload = _vibeTransferNotifier?.buildPayload();

      final result = await _service.generateImage(
        prompt: request.prompt,
        negativePrompt: request.negativePrompt,
        width: request.width,
        height: request.height,
        scale: request.scale,
        steps: request.steps,
        sampler: request.sampler,
        seed: seed,
        action: request.maskBase64 != null ? 'infill' : 'img2img',
        sourceImageBase64: request.sourceImageBase64,
        maskBase64: request.maskBase64,
        img2imgStrength: request.strength,
        img2imgNoise: request.noise,
        img2imgColorCorrect: request.colorCorrect,
        maskBlur: request.maskBase64 != null ? request.maskBlur : null,
        promptPrefix: request.promptPrefix,
        promptSuffix: request.promptSuffix,
        characters: request.characters,
        interactions: request.interactions,
        useCoords: request.useCoords,
        directorRefImages: dirPayload?.images,
        directorRefDescriptions: dirPayload?.descriptions,
        directorRefStrengths: dirPayload?.strengths,
        directorRefSecondaryStrengths: dirPayload?.secondaryStrengths,
        directorRefInfoExtracted: dirPayload?.infoExtracted,
        vibeTransferImages: vibePayload?.vibeVectors,
        vibeTransferStrengths: vibePayload?.strengths,
        vibeTransferInfoExtracted: vibePayload?.infoExtracted,
        useCurated: _state.useCurated,
      );

      Uint8List finalBytes = result.imageBytes;

      _lastMetadata = result.metadata;
      _imageSaved = false;
      _state = _state.copyWith(
        generatedImage: finalBytes,
        generatedImages: const [],
        clearSelectedGeneratedImageId: true,
        autoFollowLatestImage: true,
      );

      if (_state.autoSaveImages) {
        final timestamp = DateFormat(
          'yyyyMMdd_HHmmssSSS',
        ).format(DateTime.now());
        String? srcPath;
        if (sourceImageBytes != null) {
          try {
            final directory = Directory(_outputDir);
            if (!await directory.exists()) {
              await directory.create(recursive: true);
            }
            srcPath = p.join(directory.path, 'Src_$timestamp.png');
            await File(srcPath).writeAsBytes(sourceImageBytes);
          } catch (e) {
            debugPrint("Source image save error: $e");
          }
        }
        final savedFile = await _saveToDisk(
          finalBytes,
          result.metadata,
          timestamp: timestamp,
        );
        if (savedFile != null) {
          _galleryNotifier?.addFile(savedFile, DateTime.now());
          _imageSaved = true;
          await _autoExportIfEnabled(finalBytes, result.metadata);
          if (srcPath != null) {
            try {
              await File(srcPath).delete();
            } catch (_) {}
          }
        }
      }

      return finalBytes;
    } on UnauthorizedException {
      _state = _state.copyWith(hasAuthError: true);
      return null;
    } catch (e) {
      debugPrint("Img2Img generation error: $e");
      final error = _formatError(e);
      _state = _state.copyWith(
        errorMessage: error.message,
        errorTone: error.tone,
        errorSuggestRandomSeed: error.suggestRandomSeed,
      );
      return null;
    } finally {
      _state = _state.copyWith(isLoading: false);
      notifyListeners();
      fetchAnlas();
    }
  }

  /// The localized strings for the language the user has chosen.
  AppLocalizations get _l10n =>
      lookupAppLocalizations(LocaleNotifier.resolve(_prefs));

  GenerationError _formatError(Object e) {
    final l = _l10n;
    if (e is BackendException) {
      final seedMayHelp =
          e.code == BackendErrorCode.duplicateGeneration ||
          e.code == BackendErrorCode.duplicateWithinBatch;
      final tone = e.code == BackendErrorCode.pointsInsufficient
          ? (e.pointKind == 'red'
                ? GenerationErrorTone.redPoints
                : GenerationErrorTone.greenPoints)
          : GenerationErrorTone.general;
      return GenerationError(backendErrorMessage(l, e), tone, seedMayHelp);
    }
    // Direct NovelAI calls: the statuses are NovelAI's, not the gateway's.
    if (e is DioException) return GenerationError(directApiErrorMessage(l, e));
    return GenerationError(l.gatewayErrUnknown);
  }

  // — Session snapshot (remember session) —

  @override
  void notifyListeners() {
    super.notifyListeners();
    _scheduleSessionSave();
  }

  void _scheduleSessionSave() {
    if (!_sessionReady || !_prefs.rememberSession) return;
    _sessionSaveDebounce?.cancel();
    _sessionSaveDebounce = Timer(const Duration(seconds: 5), () {
      _saveSessionSnapshot();
    });
  }

  Future<void> _saveSessionSnapshot() async {
    final snapshot = SessionSnapshot(
      prompt: promptController.text,
      negativePrompt: negativePromptController.text,
      seed: seedController.text,
      width: _state.width,
      height: _state.height,
      scale: _state.scale,
      steps: _state.steps,
      sampler: _state.sampler,
      smea: _state.smea,
      smeaDyn: _state.smeaDyn,
      decrisper: _state.decrisper,
      randomizeSeed: _state.randomizeSeed,
      batchCount: _state.batchCount,
      autoPositioning: _state.autoPositioning,
      activeStyleNames: _state.activeStyleNames,
      isStyleEnabled: _state.isStyleEnabled,
      furryMode: _state.furryMode,
      useCurated: _state.useCurated,
      characters: _state.characters,
      interactions: _state.interactions,
      directorReferences: _directorRefNotifier?.references.toList() ?? [],
      vibeTransfers: _vibeTransferNotifier?.vibes.toList() ?? [],
    );
    await _sessionService.save(snapshot);
  }

  Future<void> _restoreSessionSnapshot() async {
    if (!_prefs.rememberSession || _metadataImportedBeforeSessionReady) return;
    final snapshot = await _sessionService.restore();
    if (snapshot == null || _metadataImportedBeforeSessionReady) return;

    promptController.text = snapshot.prompt;
    negativePromptController.text = snapshot.negativePrompt;
    seedController.text = snapshot.seed;

    _state = _state.copyWith(
      width: snapshot.width,
      height: snapshot.height,
      scale: snapshot.scale,
      steps: snapshot.steps,
      sampler: snapshot.sampler,
      smea: snapshot.smea,
      smeaDyn: snapshot.smeaDyn,
      decrisper: snapshot.decrisper,
      randomizeSeed: snapshot.randomizeSeed,
      batchCount: _clampBatchCount(snapshot.batchCount, 10),
      autoPositioning: snapshot.autoPositioning,
      activeStyleNames: _normalizeRestoredStyleNames(
        snapshot.activeStyleNames,
        _state.styles,
      ),
      isStyleEnabled: snapshot.isStyleEnabled,
      furryMode: snapshot.furryMode,
      useCurated: snapshot.useCurated,
      characters: snapshot.characters,
      interactions: snapshot.interactions,
    );

    // Restore director references
    if (snapshot.directorReferences.isNotEmpty) {
      _directorRefNotifier?.setReferences(snapshot.directorReferences);
    }

    // Restore vibe transfers
    if (snapshot.vibeTransfers.isNotEmpty) {
      _vibeTransferNotifier?.setVibes(snapshot.vibeTransfers);
    }

    notifyListeners();
  }

  Future<void> deleteSessionSnapshot() async {
    await _sessionService.delete();
  }

  @override
  void dispose() {
    _tagDebounce?.cancel();
    _sessionSaveDebounce?.cancel();
    promptController.dispose();
    negativePromptController.dispose();
    seedController.dispose();
    super.dispose();
  }
}

/// The prompts of one request (see [GenerationNotifier._composePrompts]).
class _ComposedPrompts {
  const _ComposedPrompts({
    required this.prompt,
    required this.baseNegative,
    required this.negative,
    required this.prefix,
    required this.suffix,
  });

  final String prompt;

  /// The negative prompt before the styles' negatives are merged in.
  final String baseNegative;
  final String negative;
  final String? prefix;
  final String? suffix;
}

/// The user declined the gateway's price.
class _QuoteDeclined implements Exception {
  const _QuoteDeclined();
}

/// Destination folder + filename base resolved from the pattern settings
/// (issue #27).
class _SaveTarget {
  final String dir;
  final String base;
  const _SaveTarget(this.dir, this.base);
}
