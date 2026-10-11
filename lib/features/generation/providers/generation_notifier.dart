import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../core/gateway/backend_error_messages.dart';
import '../../../core/gateway/backend_exception.dart';
import '../../../core/gateway/backend_gateway.dart';
import '../../../core/gateway/backend_permissions.dart';
import '../../../core/gateway/backend_rules.dart';
import '../../../core/gateway/image_quote.dart';
import '../../../core/l10n/locale_notifier.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/services/preferences_service.dart';
import '../../../core/services/client_diagnostics.dart';
import '../../../core/services/novel_ai_service.dart';
import '../../../core/services/backend_history_api.dart';
import '../../../core/services/nai_text_service.dart';
import '../../../core/services/wildcard_processor.dart';
import '../../../core/services/presets.dart';
import '../../../core/services/tag_service.dart';
import '../../../core/services/wildcard_service.dart';
import '../../../core/utils/tag_suggestion_helper.dart';
import '../../../core/widgets/syntax_highlight_controller.dart';
import '../../../core/services/styles.dart';
import '../../gallery/providers/gallery_notifier.dart';
import '../../tools/providers/tag_library_notifier.dart';
import '../models/nai_character.dart';
import '../models/character_preset.dart';
import '../models/generated_image_item.dart';
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
import '../services/gateway_task_watcher.dart';
import '../services/generation_image_persistence.dart';
import '../services/seed_policy.dart';

export '../models/generated_image_item.dart';

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

class GenerationState {
  final List<GeneratedImageItem> generatedImages;
  final String? selectedGeneratedImageId;
  final bool autoFollowLatestImage;

  /// Any generation work is in flight: a batch run or a single-image call.
  final bool isLoading;

  /// A batch run is in flight (submitted, queued, or being followed).
  final bool isGenerating;
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
    this.generatedImages = const [],
    this.selectedGeneratedImageId,
    this.autoFollowLatestImage = true,
    this.isLoading = false,
    this.isGenerating = false,
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

  /// The selected result, the one the actions (save, export, tools) apply to.
  GeneratedImageItem? get selectedItem => selectedGeneratedImageId == null
      ? null
      : generatedImages
            .where((item) => item.id == selectedGeneratedImageId)
            .firstOrNull;

  /// The selected result's image.
  Uint8List? get generatedImage => selectedItem?.bytes;

  GenerationState copyWith({
    List<GeneratedImageItem>? generatedImages,
    String? selectedGeneratedImageId,
    bool clearSelectedGeneratedImageId = false,
    bool? autoFollowLatestImage,
    bool? isLoading,
    bool? isGenerating,
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
      generatedImages: generatedImages ?? this.generatedImages,
      selectedGeneratedImageId: clearSelectedGeneratedImageId
          ? null
          : selectedGeneratedImageId ?? this.selectedGeneratedImageId,
      autoFollowLatestImage:
          autoFollowLatestImage ?? this.autoFollowLatestImage,
      isLoading: isLoading ?? this.isLoading,
      isGenerating: isGenerating ?? this.isGenerating,
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

  late final GenerationImagePersistence _persistence;
  late final GatewayTaskWatcher _watcher;
  Uint8List? _previousImageBytes;

  Timer? _tagDebounce;
  Timer? _sessionSaveDebounce;
  bool _sessionReady = false;
  bool _disposed = false;
  late final Future<void> _initialLoad;

  /// Imports that arrived before the saved session was restored. They are
  /// applied on top of the restored session, so the restore cannot overwrite
  /// them and the session saved afterwards holds them.
  final List<({MetadataImportResult result, Set<ImportCategory> categories})>
  _pendingImports = [];

  // — Runs —
  // A run is one batch of generate() (or the restore of a server batch). It
  // owns the result set it created: results carry the run id of their item and
  // are written back by item id, so a late result of an older run, or of an
  // account that was switched away from, finds nothing to write to.
  int _runSeq = 0;
  int? _activeRunId;
  GatewayWatchToken? _runToken;

  /// The gateway submission behind the result set, for cancelling and for
  /// following it again.
  String? _taskId;
  int _singleImageCalls = 0;
  final Map<String, Future<String?>> _saves = {};

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
    GatewayTaskWatcher? watcher,
  }) : _prefs = preferences,
       _tagService = tagService,
       _wildcardService = wildcardService,
       _outputDir = outputDir,
       _galleryNotifier = galleryNotifier,
       _characterLibrary = characterLibrary,
       _serviceFactory = serviceFactory ?? NovelAIService.new,
       _historyApi = historyApi ?? BackendHistoryApi() {
    _service = _serviceFactory('');
    _watcher = watcher ?? GatewayTaskWatcher(api: _historyApi);
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
    _persistence = GenerationImagePersistence(
      prefs: _prefs,
      outputDir: () => _outputDir,
      gallery: () => _galleryNotifier,
    );
    negativePromptController.text = "";
    promptController.addListener(_scheduleSessionSave);
    negativePromptController.addListener(_scheduleSessionSave);
    seedController.addListener(_scheduleSessionSave);
    _initialLoad = _loadInitialData();
  }

  /// Completes when the initial data is loaded and the saved session (and any
  /// import that waited for it) is applied.
  Future<void> get initialized => _initialLoad;

  void updateGalleryNotifier(GalleryNotifier galleryNotifier) {
    _galleryNotifier = galleryNotifier;
  }

  // — Result set and runs —

  bool get _busy => _activeRunId != null || _singleImageCalls > 0;

  void _syncBusy() {
    _state = _state.copyWith(
      isGenerating: _activeRunId != null,
      isLoading: _busy,
    );
  }

  /// Starts the run that owns the result set from now on.
  int _beginRun() {
    final runId = ++_runSeq;
    _activeRunId = runId;
    _runToken = GatewayWatchToken();
    _syncBusy();
    return runId;
  }

  /// Ends [runId] (if it is still the active one) and settles its items.
  void _endRun(int runId) {
    if (_activeRunId == runId) {
      _activeRunId = null;
      _runToken = null;
      _syncBusy();
    }
    _state = _state.copyWith(
      generatedImages: [
        for (final item in _state.generatedImages)
          item.runId == runId && item.isLoading
              ? item.copyWith(isLoading: false)
              : item,
      ],
    );
  }

  /// The one place the result set is replaced. Callers notify.
  void _setResults(
    List<GeneratedImageItem> items, {
    String? selectedId,
    String? taskId,
  }) {
    _taskId = taskId;
    _state = _state.copyWith(
      generatedImages: items,
      selectedGeneratedImageId: selectedId,
      clearSelectedGeneratedImageId: selectedId == null,
      autoFollowLatestImage: true,
      duplicateImageDetected: false,
    );
  }

  /// Shows one image that has no batch (a tool result, a dropped file).
  GeneratedImageItem _showSingleImage(
    Uint8List bytes, {
    Map<String, dynamic>? metadata,
    int? seed,
  }) {
    final runId = ++_runSeq;
    final item = GeneratedImageItem(
      id: 'single-$runId',
      runId: runId,
      batchIndex: 1,
      batchCount: 1,
      bytes: bytes,
      metadata: metadata,
      seed: seed,
    );
    _setResults([item], selectedId: item.id);
    return item;
  }

  GeneratedImageItem? _itemById(String id, {int? runId}) => _state
      .generatedImages
      .where((item) => item.id == id && (runId == null || item.runId == runId))
      .firstOrNull;

  /// Rewrites the item [id] (of run [runId], when given). False when no such
  /// item exists any more: the caller drops the result instead of failing.
  bool _mapItem(
    String id,
    GeneratedImageItem Function(GeneratedImageItem item) update, {
    int? runId,
  }) {
    final index = _state.generatedImages.indexWhere(
      (item) => item.id == id && (runId == null || item.runId == runId),
    );
    if (index < 0) return false;
    final items = [..._state.generatedImages];
    items[index] = update(items[index]);
    _state = _state.copyWith(generatedImages: items);
    return true;
  }

  void _recordDropped(String what, int runId, String itemId) {
    ClientDiagnostics.instance.record('generation_result_dropped', {
      'what': what,
      'run_id': runId,
      'item_id': itemId,
      'active_run_id': _activeRunId,
    });
  }

  /// Puts the image of item [id] in its slot, and selects it when the user is
  /// following the newest result. False when the slot is gone or taken.
  bool _completeItem(int runId, String id, Uint8List bytes) {
    final existing = _itemById(id, runId: runId);
    if (existing == null) {
      _recordDropped('image', runId, id);
      return false;
    }
    if (existing.isComplete) return false;
    final isDuplicate =
        _previousImageBytes != null && listEquals(bytes, _previousImageBytes);
    _previousImageBytes = Uint8List.fromList(bytes);
    _mapItem(
      id,
      (item) => item.copyWith(
        bytes: bytes,
        isLoading: false,
        progress: GenerationTaskProgress.generating,
        duplicateImageDetected: isDuplicate,
        clearErrorMessage: true,
        retryable: false,
      ),
    );
    final shouldSelect =
        _state.autoFollowLatestImage ||
        _state.selectedGeneratedImageId == id ||
        _state.selectedGeneratedImageId == null;
    if (shouldSelect) _showSeedOfSelection(existing.seed);
    _state = _state.copyWith(
      selectedGeneratedImageId: shouldSelect ? id : null,
      duplicateImageDetected: isDuplicate,
    );
    notifyListeners();
    return true;
  }

  void _failItem(int runId, String id, Object error) {
    final failed = _mapItem(
      id,
      (item) => item.copyWith(
        isLoading: false,
        progress: GenerationTaskProgress.failed,
        errorMessage: _formatError(error).message,
        retryable: false,
      ),
      runId: runId,
    );
    if (failed) {
      notifyListeners();
    } else {
      _recordDropped('failure', runId, id);
    }
  }

  /// With random seeds the seed box is an output: it shows the seed of the
  /// image on screen.
  void _showSeedOfSelection(int? seed) {
    if (seed != null && _state.randomizeSeed) {
      seedController.text = seed.toString();
    }
  }

  /// Follows [itemIds] of the gateway submission [taskId] for run [runId]
  /// until each is final. Failing or giving up marks what is left as
  /// retryable instead of failed: the server may still finish it.
  Future<void> _watchRun(
    int runId,
    String taskId,
    Set<String> itemIds, {
    required GatewayWatchToken token,
  }) async {
    final saves = <Future<void>>[];
    try {
      await _watcher.watch(
        taskId: taskId,
        itemIds: itemIds,
        token: token,
        onItem: (server) => _applyServerItem(server, runId: runId),
        onImage: (server, bytes) {
          if (_completeItem(runId, server.id, bytes)) {
            saves.add(_autoSave(server.id));
          }
        },
        onImageFailed: (server, error) => _failItem(runId, server.id, error),
      );
    } on GatewayWatchTimeout {
      _stopFollowing(runId, itemIds, _l10n.generationWatchTimedOut);
    } catch (error) {
      if (!token.isCancelled) {
        _stopFollowing(runId, itemIds, _formatError(error).message);
      }
    }
    await Future.wait(saves);
  }

  void _applyServerItem(ServerHistoryItem server, {int? runId}) {
    var changed = false;
    _mapItem(server.id, (item) {
      if (item.isTerminal) return item;
      final progress = progressForGatewayStatus(server.status);
      final loading =
          !isFinalGatewayStatus(server.status) || server.status == 'success';
      final message = taskItemFailureMessage(
        _l10n,
        server.status,
        server.errorCode,
      );
      if (progress == item.progress && loading == item.isLoading) return item;
      changed = true;
      return item.copyWith(
        progress: progress,
        isLoading: loading,
        errorMessage: message,
        retryable: false,
      );
    }, runId: runId);
    if (changed) notifyListeners();
  }

  void _stopFollowing(int runId, Set<String> itemIds, String message) {
    _state = _state.copyWith(
      generatedImages: [
        for (final item in _state.generatedImages)
          itemIds.contains(item.id) && item.runId == runId && !item.isTerminal
              ? item.copyWith(
                  isLoading: false,
                  retryable: true,
                  errorMessage: message,
                )
              : item,
      ],
      errorMessage: message,
    );
    notifyListeners();
  }

  /// Whether queued work can still be cancelled: on the gateway the items
  /// that have not started, directly the images not yet requested.
  bool get canCancelQueued =>
      (_service.viaGateway ? _taskId != null : _activeRunId != null) &&
      _state.generatedImages.any(
        (item) =>
            item.progress == GenerationTaskProgress.queued && !item.isTerminal,
      );

  /// Cancels the queued images of the batch. Images that already started are
  /// not affected and still arrive.
  Future<void> cancelQueued() async {
    if (!canCancelQueued) return;
    if (!_service.viaGateway) {
      // The serial loop checks the token before each request.
      _runToken?.cancel();
      return;
    }
    final taskId = _taskId!;
    try {
      final task = await _historyApi.cancelGenerationTask(taskId);
      if (_taskId != taskId) return;
      for (final server in task.items) {
        _applyServerItem(server);
      }
    } catch (error) {
      final formatted = _formatError(error);
      _state = _state.copyWith(
        errorMessage: formatted.message,
        errorTone: formatted.tone,
      );
      notifyListeners();
    }
  }

  /// Items the client stopped following, which the server may still finish.
  bool get canResumeWatching =>
      _activeRunId == null &&
      _taskId != null &&
      _state.generatedImages.any((item) => item.retryable);

  /// Follows the retryable items again.
  Future<void> resumeWatching() async {
    if (!canResumeWatching) return;
    final taskId = _taskId!;
    final retryable = _state.generatedImages
        .where((item) => item.retryable)
        .toList();
    final runId = retryable.first.runId;
    _activeRunId = runId;
    final token = _runToken = GatewayWatchToken();
    final ids = {for (final item in retryable) item.id};
    _state = _state.copyWith(
      generatedImages: [
        for (final item in _state.generatedImages)
          ids.contains(item.id)
              ? item.copyWith(
                  isLoading: true,
                  retryable: false,
                  clearErrorMessage: true,
                )
              : item,
      ],
      clearErrorMessage: true,
    );
    _syncBusy();
    notifyListeners();
    try {
      await _watchRun(runId, taskId, ids, token: token);
    } finally {
      _endRun(runId);
      notifyListeners();
      fetchAnlas();
    }
  }

  /// Rebuild the result workspace after a browser reload. Generation tasks are
  /// durable on the gateway; the UI is only a view of those server records.
  void updateBackendUserId(int? userId) {
    if (_backendUserId == userId) return;
    _backendUserId = userId;
    // The workspace belongs to the previous account: another user must never
    // see its images, even when their own history is empty. Whatever the old
    // run still delivers finds no slot and is dropped.
    _runToken?.cancel();
    _runToken = null;
    _activeRunId = null;
    _setResults(const []);
    _syncBusy();
    _state = _state.copyWith(clearErrorMessage: true);
    notifyListeners();
    if (useBackendGateway && userId != null) {
      unawaited(_restoreGatewayWorkspace(userId));
    }
  }

  Future<void> _restoreGatewayWorkspace(int userId) async {
    if (_restoringWorkspaceForUserId == userId || _activeRunId != null) return;
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
      if (_backendUserId != userId || _activeRunId != null || _disposed) return;
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

      final taskId = currentTask?.id ?? recoverable.first.batchId;
      final runId = _beginRun();
      final token = _runToken!;
      final restored = List<GeneratedImageItem>.generate(recoverable.length, (
        index,
      ) {
        final task = recoverable[index];
        final open = !isFinalGatewayStatus(task.status);
        return GeneratedImageItem(
          id: task.id,
          runId: runId,
          batchIndex: index + 1,
          batchCount: recoverable.length,
          seed: task.seed,
          metadata: _historyMetadata(task),
          isLoading: open || task.status == 'success',
          progress: progressForGatewayStatus(task.status),
          errorMessage: taskItemFailureMessage(
            _l10n,
            task.status,
            task.errorCode,
          ),
        );
      });
      _setResults(restored, selectedId: restored.first.id, taskId: taskId);
      notifyListeners();

      // One watcher follows every unfinished item at once, and fetches the
      // images of the finished ones.
      final following = {
        for (final task in recoverable)
          if (task.status == 'success' || !isFinalGatewayStatus(task.status))
            task.id,
      };
      try {
        if (taskId != null && following.isNotEmpty) {
          await _watchRun(runId, taskId, following, token: token);
        }
      } finally {
        _endRun(runId);
        notifyListeners();
      }
    } catch (error) {
      debugPrint('Could not restore gateway generation workspace: $error');
    } finally {
      if (_restoringWorkspaceForUserId == userId) {
        _restoringWorkspaceForUserId = null;
      }
    }
  }

  Map<String, dynamic> _historyMetadata(ServerHistoryItem task) => {
    ...task.generationMetadata,
    'seed': task.seed,
  };

  void updateCharacterLibraryNotifier(CharacterLibraryNotifier notifier) {
    _characterLibrary = notifier;
  }

  void updateDirectorRefNotifier(DirectorRefNotifier notifier) {
    if (identical(_directorRefNotifier, notifier)) return;
    _directorRefNotifier = notifier..addListener(_scheduleSessionSave);
  }

  void updateVibeTransferNotifier(VibeTransferNotifier notifier) {
    if (!identical(_vibeTransferNotifier, notifier)) {
      _vibeTransferNotifier = notifier..addListener(_scheduleSessionSave);
    }
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

  /// The styles a fresh editor starts with: the ones the user marked as
  /// default in the style editor; without any, the built-in quality style.
  @visibleForTesting
  static List<String> defaultActiveStyleNames(List<PromptStyle> styles) {
    final marked = [
      for (final style in styles)
        if (style.isDefault) style.name,
    ];
    if (marked.isNotEmpty) return marked;
    for (final style in styles) {
      if (style.name == _qualityStyleName) return [style.name];
    }
    for (final style in styles) {
      if (style.name.toLowerCase().contains('quality')) return [style.name];
    }
    return styles.isNotEmpty ? [styles.first.name] : <String>[];
  }

  /// Snapshots written before versions existed may hold the old default
  /// ("Light - NAI" alone); those are moved to today's default once. A
  /// snapshot of this build keeps whatever the user chose.
  static List<String> _migrateRestoredStyleNames(
    SessionSnapshot snapshot,
    List<PromptStyle> styles,
  ) {
    final names = snapshot.activeStyleNames;
    if (snapshot.version < 1 &&
        names.length == 1 &&
        names.first == _legacyLightStyleName) {
      return defaultActiveStyleNames(styles);
    }
    return names;
  }

  Future<void> _loadInitialData() async {
    await _tagService.loadTags();
    await _wildcardService.refresh();
    final presets = await _presetService.loadPresets();
    final styles = await _presetService.loadStyles();
    if (_disposed) return;

    final apiKey = useBackendGateway
        ? serverManagedApiKey
        : await _prefs.getApiKey();
    if (_disposed) return;
    _service = _serviceFactory(apiKey);
    _textService = NaiTextService(apiKey);
    _vibeTransferNotifier?.updateService(_service);
    _directorToolsNotifier?.updateService(_service);
    _enhanceNotifier?.updateService(_service);
    _textGenNotifier?.updateService(_textService);

    _state = _state.copyWith(
      presets: presets,
      styles: styles,
      activeStyleNames: defaultActiveStyleNames(styles),
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

    // The saved session first; whatever was imported meanwhile goes on top.
    await _restoreSessionSnapshot();
    if (_disposed) return;
    _sessionReady = true;
    final imports = [..._pendingImports];
    _pendingImports.clear();
    for (final pending in imports) {
      applyImportedMetadata(pending.result, pending.categories);
    }

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
    _scheduleSessionSave();
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
    _scheduleSessionSave();
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
    _scheduleSessionSave();
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
    _scheduleSessionSave();
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
    _scheduleSessionSave();
    notifyListeners();
  }

  /// Shows [image] (a tool preview) as the result. Ignored while a batch runs:
  /// it would replace the images that are still arriving.
  void setGeneratedImage(Uint8List? image) {
    if (_activeRunId != null) return;
    if (image == null) {
      _setResults(const []);
    } else {
      _showSingleImage(image);
    }
    notifyListeners();
  }

  void selectGeneratedImage(String id) {
    final selected = _itemById(id);
    if (selected == null) return;

    _state = _state.copyWith(
      selectedGeneratedImageId: id,
      autoFollowLatestImage: false,
      duplicateImageDetected: selected.duplicateImageDetected,
    );
    _showSeedOfSelection(selected.seed);
    notifyListeners();
  }

  /// Makes the seed of image [id] the fixed seed of the next generation.
  void reuseSeed(String id) {
    final seed = _itemById(id)?.seed;
    if (seed == null) return;
    seedController.text = seed.toString();
    updateSettings(randomizeSeed: false);
  }

  /// Saves image [itemId] (the one the caller captured when the user asked,
  /// not whichever is selected by the time the write finishes). Saving twice
  /// writes once: the second call gets the first one's file name.
  Future<String?> saveImage(String itemId) => _persist(itemId, auto: false);

  /// The save after a generation finished, when the user enabled it.
  Future<String?> _autoSave(String itemId) async {
    if (!_state.autoSaveImages) return null;
    return _persist(itemId, auto: true);
  }

  Future<String?> _persist(String itemId, {required bool auto}) {
    final running = _saves[itemId];
    if (running != null) return running;
    final item = _itemById(itemId);
    final bytes = item?.bytes;
    final metadata = item?.metadata;
    if (item == null || bytes == null || metadata == null) {
      return Future.value(null);
    }
    if (item.saved) return Future.value(item.savedBasename);
    final save = _persistNow(itemId, bytes, metadata, auto: auto);
    _saves[itemId] = save;
    return save.whenComplete(() => _saves.remove(itemId));
  }

  Future<String?> _persistNow(
    String itemId,
    Uint8List bytes,
    Map<String, dynamic> metadata, {
    required bool auto,
  }) async {
    final basename = await (auto
        ? _persistence.autoSave(bytes, metadata)
        : _persistence.save(bytes, metadata));
    if (basename == null) return null;
    _mapItem(
      itemId,
      (item) => item.copyWith(saved: true, savedBasename: basename),
    );
    notifyListeners();
    return basename;
  }

  /// Ensures image [itemId] is saved and returns its file name, for adding it
  /// to an album. Web has no gallery to add to.
  Future<String?> ensureSavedAndGetBasename(String itemId) async {
    final item = _itemById(itemId);
    if (item == null) return null;
    if (item.saved) return item.savedBasename;
    if (kIsWeb) return null;
    return saveImage(itemId);
  }

  /// Copies image [itemId] to the clipboard (shares it on mobile).
  Future<void> copyImage(BuildContext context, String itemId) async {
    final bytes = _itemById(itemId)?.bytes;
    if (bytes == null) return;
    await _persistence.copyToClipboard(context, bytes);
  }

  /// Exports image [itemId] to the export folder, the device gallery or a
  /// file dialog.
  Future<void> exportImage(BuildContext context, String itemId) async {
    final item = _itemById(itemId);
    final bytes = item?.bytes;
    if (bytes == null) return;
    await _persistence.exportToDevice(context, bytes, item!.metadata);
  }

  void removeInteraction(NaiInteraction interaction) {
    final updated = _characterManager.removeInteraction(
      _state.interactions,
      interaction,
    );
    _state = _state.copyWith(interactions: updated);
    _scheduleSessionSave();
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
    _scheduleSessionSave();
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
    _scheduleSessionSave();
    notifyListeners();
  }

  static int _clampBatchCount(int value, int limit) {
    final max = math.max(1, math.min(limit, 10));
    return math.max(1, math.min(value, max));
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
    state: _state,
    seed: 0,
    prompts: _composePrompts(
      state: _state,
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
    required GenerationState state,
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
      isStyleEnabled: state.isStyleEnabled,
      activeStyleNames: state.activeStyleNames,
      styles: state.styles,
      furryMode: state.furryMode,
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
  /// shown and for what is submitted, under the settings of [state]. The
  /// request holds copies, so editing the form later does not change it.
  /// [directorRefs] and [vibes] are the payloads of the inputs that are
  /// actually sent.
  ImageGenerationRequest _buildRequest({
    required GenerationState state,
    required int seed,
    required _ComposedPrompts prompts,
    required List<NaiCharacter> characters,
    required DirectorRefPayload? directorRefs,
    required VibeTransferPayload? vibes,
  }) {
    return _service.buildImageGenerationRequest(
      prompt: prompts.prompt,
      negativePrompt: prompts.negative,
      width: state.width.toInt(),
      height: state.height.toInt(),
      scale: state.scale,
      steps: state.steps.toInt(),
      sampler: state.sampler,
      smea: state.smea,
      smeaDyn: state.smeaDyn,
      decrisper: state.decrisper,
      seed: seed,
      promptPrefix: prompts.prefix,
      promptSuffix: prompts.suffix,
      characters: characters,
      interactions: state.interactions,
      useCoords: state.characters.isNotEmpty ? !state.autoPositioning : false,
      directorRefImages: directorRefs?.images,
      directorRefDescriptions: directorRefs?.descriptions,
      directorRefStrengths: directorRefs?.strengths,
      directorRefSecondaryStrengths: directorRefs?.secondaryStrengths,
      directorRefInfoExtracted: directorRefs?.infoExtracted,
      vibeTransferImages: vibes?.vibeVectors,
      vibeTransferStrengths: vibes?.strengths,
      vibeTransferInfoExtracted: vibes?.infoExtracted,
      useCurated: state.useCurated,
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
  }) => _service.submitGatewayBatch(
    request: request,
    seeds: seeds,
    clientRequestId: clientRequestId,
    confirmQuote: confirmQuote,
    canPayRed: _access.canPay,
    rules: _rules,
  );

  void _rejectBusy() {
    _state = _state.copyWith(errorMessage: _l10n.generationBusy);
    notifyListeners();
  }

  GenerationOutcome _rejectedBusy() {
    _rejectBusy();
    return GenerationOutcome.rejected(_l10n.generationBusy);
  }

  /// Submits the current prompt and settings. Through the gateway the price
  /// shown to the user is sent along; when the gateway prices the request
  /// differently, [confirmQuote] asks the user whether to go on at the
  /// gateway's price (declining submits nothing).
  ///
  /// [prompt] and [negativePrompt] stand in for the prompt boxes when the
  /// caller has its own (the photoshoot), which are then left alone. Only one
  /// generation runs at a time: asking while another runs is refused. The
  /// settings are read once, here; the request, its metadata and the result
  /// slots are frozen from that moment.
  Future<GenerationOutcome> generate({
    int batchLimit = 1,
    QuoteConfirmer? confirmQuote,
    String? prompt,
    String? negativePrompt,
  }) async {
    if (_busy) return _rejectedBusy();
    clearTagSuggestions();

    final s = _state;
    final promptText = prompt ?? promptController.text;
    final negativeText = negativePrompt ?? negativePromptController.text;
    final batchCount = _clampBatchCount(s.batchCount, batchLimit);
    final List<int> seeds;
    try {
      seeds = resolveSeeds(
        count: batchCount,
        randomize: s.randomizeSeed,
        seedText: seedController.text,
      );
    } on InvalidSeedInput {
      _state = _state.copyWith(errorMessage: _l10n.generationSeedInvalid);
      notifyListeners();
      return GenerationOutcome.rejected(_l10n.generationSeedInvalid);
    }
    if (s.randomizeSeed) seedController.text = seeds.last.toString();

    final runId = _beginRun();
    final token = _runToken!;
    final nonceSource = math.Random.secure();
    final submissionId = [
      DateTime.now().microsecondsSinceEpoch.toRadixString(16),
      randomSeed(nonceSource).toRadixString(16).padLeft(8, '0'),
      randomSeed(nonceSource).toRadixString(16).padLeft(8, '0'),
    ].join('-');
    final gatewayBatch = _service.viaGateway;
    _state = _state.copyWith(hasAuthError: false, clearErrorMessage: true);
    notifyListeners();

    // Keep screen/CPU awake during generation to prevent network drops
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        WakelockPlus.enable();
      } catch (_) {}
    }

    Object? firstError;
    var declined = false;
    var authFailed = false;
    String? failureMessage;
    try {
      final processedPrompt = await _wildcardProcessor.process(promptText);
      final prompts = _composePrompts(
        state: s,
        prompt: _tagService.resolveAliases(processedPrompt),
        baseNegative: _tagService.resolveAliases(
          await _wildcardProcessor.process(negativeText),
        ),
      );
      final dirPayload = _directorRefNotifier?.buildPayload();
      final vibePayload = _vibeTransferNotifier?.buildPayload();

      // Process wildcards in character prompts
      final processedCharacters = await Future.wait(
        s.characters.map(
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
      // The account was switched while the prompts were being prepared.
      if (_activeRunId != runId) return const GenerationOutcome.rejected();

      // Everything that will be sent, and everything the saved files will say
      // about it, is fixed here.
      final requests = [
        for (final seed in seeds)
          _buildRequest(
            state: s,
            seed: seed,
            prompts: prompts,
            characters: processedCharacters,
            directorRefs: dirPayload,
            vibes: vibePayload,
          ),
      ];
      final metadata = [
        for (var index = 0; index < batchCount; index++)
          {
            ...requests[index].metadata,
            // Style info for the round-trip restore of an image.
            'active_style_names': s.isStyleEnabled ? s.activeStyleNames : [],
            'is_style_enabled': s.isStyleEnabled,
            'original_negative_prompt': prompts.baseNegative,
            if (batchCount > 1) 'batch_index': index + 1,
            if (batchCount > 1) 'batch_count': batchCount,
          },
      ];
      GeneratedImageItem slot(String id, int index) => GeneratedImageItem(
        id: id,
        runId: runId,
        batchIndex: index + 1,
        batchCount: batchCount,
        metadata: metadata[index],
        seed: seeds[index],
        isLoading: true,
        progress: GenerationTaskProgress.queued,
      );

      if (gatewayBatch) {
        final submission = await _submitGatewayBatch(
          request: requests.first,
          seeds: seeds,
          clientRequestId: submissionId,
          confirmQuote: confirmQuote,
        );
        if (_activeRunId != runId) return const GenerationOutcome.rejected();
        final submitted = submission.items.toList()
          ..sort((a, b) => a.batchIndex.compareTo(b.batchIndex));
        final accepted = [
          for (var index = 0; index < batchCount; index++)
            slot(submitted[index].id, index).copyWith(
              progress: progressForGatewayStatus(submitted[index].status),
            ),
        ];
        _setResults(
          accepted,
          selectedId: accepted.first.id,
          taskId: submission.taskId,
        );
        notifyListeners();
        await _watchRun(runId, submission.taskId, {
          for (final item in accepted) item.id,
        }, token: token);
      } else {
        final placeholders = [
          for (var index = 0; index < batchCount; index++)
            slot('$submissionId-$index', index),
        ];
        _setResults(placeholders, selectedId: placeholders.first.id);
        notifyListeners();
        // NovelAI allows one generation per account at a time: one request in
        // flight, and each one starts only if the batch was not cancelled.
        for (var index = 0; index < batchCount; index++) {
          final id = placeholders[index].id;
          if (token.isCancelled || _activeRunId != runId) {
            _cancelUnsent(runId, firstError);
            break;
          }
          _mapItem(
            id,
            (item) =>
                item.copyWith(progress: GenerationTaskProgress.generating),
            runId: runId,
          );
          notifyListeners();
          try {
            final bytes = await _service.generateDirect(requests[index]);
            if (_completeItem(runId, id, bytes)) await _autoSave(id);
          } catch (error) {
            firstError ??= error;
            if (_itemById(id, runId: runId) == null) break;
            _failItem(runId, id, error);
            // The same account and key would fail the rest the same way.
            _cancelUnsent(runId, error);
            break;
          }
        }
        if (firstError != null) {
          if (firstError is UnauthorizedException) throw firstError;
          final error = _formatError(firstError);
          failureMessage = error.message;
          _state = _state.copyWith(
            errorMessage: error.message,
            errorTone: error.tone,
            errorSuggestRandomSeed: error.suggestRandomSeed,
          );
        }
      }
    } on UnauthorizedException {
      authFailed = true;
      _state = _state.copyWith(hasAuthError: true);
    } on QuoteDeclinedException {
      // The user chose not to pay the gateway's price: nothing was submitted.
      declined = true;
    } catch (e) {
      debugPrint("Generation error: $e");
      final error = _formatError(e);
      failureMessage = error.message;
      _state = _state.copyWith(
        errorMessage: error.message,
        errorTone: error.tone,
        errorSuggestRandomSeed: error.suggestRandomSeed,
      );
    } finally {
      _endRun(runId);
      notifyListeners();
      fetchAnlas();
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        try {
          WakelockPlus.disable();
        } catch (_) {}
      }
    }

    final items = _state.generatedImages.where((item) => item.runId == runId);
    return GenerationOutcome(
      declined: declined,
      authFailed: authFailed,
      completed: items.where((item) => item.isComplete).length,
      failed: items.where((item) => !item.isComplete).length,
      errorMessage:
          items.map((item) => item.errorMessage).nonNulls.firstOrNull ??
          failureMessage,
    );
  }

  /// Marks the images of [runId] that were never requested as cancelled.
  void _cancelUnsent(int runId, Object? because) {
    final message = because == null
        ? _l10n.generationItemCancelled
        : _formatError(because).message;
    _state = _state.copyWith(
      generatedImages: [
        for (final item in _state.generatedImages)
          item.runId == runId &&
                  !item.isTerminal &&
                  item.progress == GenerationTaskProgress.queued
              ? item.copyWith(
                  isLoading: false,
                  progress: GenerationTaskProgress.cancelled,
                  errorMessage: message,
                )
              : item,
      ],
    );
    notifyListeners();
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

  /// The one entry point for putting a character's tags (and the negative
  /// tags that belong to it) into the prompts.
  ///
  /// Where they go:
  /// - [promptTarget] / [negativeTarget], when given, are appended to as they
  ///   are (the character card being edited, for instance);
  /// - otherwise [target] decides: `'editor'` adds a character card named
  ///   [name] with [tags] as its prompt and [negativeTags] as its UC (returns
  ///   [ApplyTagResult.characterLimitReached] and changes nothing at the
  ///   6-card maximum), `'main'` writes into the main prompt and negative
  ///   prompt. A null [target] follows the `charInsertTarget` preference.
  ///
  /// With the main target, [replaceMainPrompt] swaps the main prompt text for
  /// [tags] instead of appending. Negative tags are always appended to what is
  /// already there, de-duplicated.
  ApplyTagResult insertCharacterTags(
    String tags,
    String? negativeTags, {
    String? target,
    String name = '',
    bool replaceMainPrompt = false,
    TextEditingController? promptTarget,
    TextEditingController? negativeTarget,
  }) {
    final cleanTags = tags.trim();
    if (promptTarget != null || negativeTarget != null) {
      if (promptTarget != null) _appendPromptTags(promptTarget, cleanTags);
      if (negativeTarget != null) {
        TagSuggestionHelper.appendNegatives(negativeTarget, negativeTags);
      }
      return ApplyTagResult.insertedIntoPrompt;
    }
    final effectiveTarget = target ?? _prefs.charInsertTarget;
    if (effectiveTarget == 'editor') {
      if (_state.characters.length >= CharacterManager.maxCharacters) {
        return ApplyTagResult.characterLimitReached;
      }
      addCharacter(
        name: name,
        prompt: cleanTags,
        uc: (negativeTags ?? '').trim(),
      );
      if (_state.characterEditorMode != 'expanded') {
        setCharacterEditorMode('expanded');
      }
      return ApplyTagResult.addedCharacterCard;
    }
    if (replaceMainPrompt) {
      promptController.text = cleanTags;
    } else {
      _appendPromptTags(promptController, cleanTags);
    }
    TagSuggestionHelper.appendNegatives(negativePromptController, negativeTags);
    return ApplyTagResult.insertedIntoPrompt;
  }

  /// Appends comma-separated [tags] to a prompt [controller], ending with the
  /// separator so the next tag can follow. No-op when [tags] is blank.
  static void _appendPromptTags(TextEditingController controller, String tags) {
    if (tags.isEmpty) return;
    final existing = controller.text.trimRight();
    final text = existing.isEmpty
        ? '$tags, '
        : '$existing${existing.endsWith(',') ? '' : ','} $tags, ';
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// Adds [tag] (a `saved_character` suggestion) as a new character card, with
  /// its expansion as the card prompt and negative expansion as the card UC.
  /// Returns [ApplyTagResult.characterLimitReached] without mutating state when
  /// the editor is already at the 6-character maximum.
  ApplyTagResult _addSavedCharacterAsCard(DanbooruTag tag) {
    final prompt = (tag.expansion != null && tag.expansion!.trim().isNotEmpty)
        ? tag.expansion!.trim()
        : tag.tag;
    return insertCharacterTags(
      prompt,
      tag.negativeExpansion,
      target: 'editor',
      name: tag.tag,
    );
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
  ///
  /// The saved session is restored first and an import goes on top of it, so
  /// an import that arrives while the app is still starting waits for the
  /// restore instead of being overwritten by it.
  void applyImportedMetadata(
    MetadataImportResult result,
    Set<ImportCategory> categories,
  ) {
    if (!_sessionReady) {
      _pendingImports.add((result: result, categories: categories));
      return;
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

    final settings = categories.contains(ImportCategory.settings);
    final styles = categories.contains(ImportCategory.styles);
    final characters = categories.contains(ImportCategory.characters);
    _state = _state.copyWith(
      width: settings ? result.width : null,
      height: settings ? result.height : null,
      scale: settings ? result.scale : null,
      steps: settings ? result.steps : null,
      sampler: settings ? result.sampler : null,
      smea: settings ? result.smea : null,
      smeaDyn: settings ? result.smeaDyn : null,
      decrisper: settings ? result.decrisper : null,
      randomizeSeed: categories.contains(ImportCategory.seed) ? false : null,
      activeStyleNames: styles ? result.activeStyleNames : null,
      isStyleEnabled: styles ? result.isStyleEnabled : null,
      characters: characters ? result.characters : null,
      interactions: characters ? result.interactions : null,
      autoPositioning: characters ? result.autoPositioning : null,
    );
    // The dropped image replaces the shown result, unless a batch is still
    // delivering its images: those are never discarded for it.
    final image = result.imageBytes;
    if (image != null && _activeRunId == null) _showSingleImage(image);
    _scheduleSessionSave();
    notifyListeners();
  }

  /// Import all metadata from a PNG file (used by drag-and-drop).
  Future<void> importImageMetadata(File file) async {
    try {
      final result = await parseImageMetadata(file);
      applyImportedMetadata(result, ImportCategory.values.toSet());
    } catch (e) {
      debugPrint("Metadata extraction error: $e");
      rethrow;
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
    _scheduleSessionSave();
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

  /// Runs one single-image call (a tool preview, a cascade beat, img2img).
  /// Only one generation runs at a time, so this is refused (null) while a
  /// batch or another call is in flight: appending to or replacing a batch
  /// that is still delivering paid images would lose or misplace them. The
  /// busy state is [_singleImageCalls], undone in one place.
  Future<T?> _runSingleImage<T>(
    String label,
    Future<T?> Function() call, {
    bool showErrors = true,
  }) async {
    if (_busy) {
      if (showErrors) _rejectBusy();
      return null;
    }
    _singleImageCalls++;
    _state = _state.copyWith(hasAuthError: false);
    _syncBusy();
    notifyListeners();
    try {
      return await call();
    } on UnauthorizedException {
      _state = _state.copyWith(hasAuthError: true);
      return null;
    } on QuoteDeclinedException {
      return null;
    } on InvalidSeedInput {
      if (showErrors) {
        _state = _state.copyWith(errorMessage: _l10n.generationSeedInvalid);
      }
      return null;
    } catch (e) {
      debugPrint('$label error: $e');
      if (showErrors) {
        final error = _formatError(e);
        _state = _state.copyWith(
          errorMessage: error.message,
          errorTone: error.tone,
          errorSuggestRandomSeed: error.suggestRandomSeed,
        );
      }
      return null;
    } finally {
      _singleImageCalls--;
      _syncBusy();
      notifyListeners();
      if (showErrors) fetchAnlas();
    }
  }

  Future<Uint8List?> generateQuickPreview(
    String tag, {
    TagPreviewSettings? previewSettings,
  }) {
    final settings = previewSettings ?? TagPreviewSettings();
    return _runSingleImage<Uint8List>('Quick preview', () async {
      final seed = settings.seed ?? randomSeed();
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
        canPayRed: _access.canPay,
      );

      // Auto-save the preview as well, so it's in the gallery
      if (_state.autoSaveImages) {
        await _persistence.autoSave(result.imageBytes, result.metadata);
      }

      return result.imageBytes;
    }, showErrors: false);
  }

  /// Shows [result] as the only image and saves it when auto save is on.
  Future<void> _showToolResult(
    GenerationResult result,
    int seed, {
    Future<String?> Function(GeneratedImageItem item)? autoSave,
  }) async {
    final item = _showSingleImage(
      result.imageBytes,
      metadata: result.metadata,
      seed: seed,
    );
    notifyListeners();
    if (!_state.autoSaveImages) return;
    final basename = await (autoSave?.call(item) ?? _autoSave(item.id));
    if (basename == null) return;
    _mapItem(
      item.id,
      (current) => current.copyWith(saved: true, savedBasename: basename),
    );
    notifyListeners();
  }

  /// The seeds of a single image from the form (the random switch and the
  /// seed box), written back to the box when it is random.
  int _singleSeed() {
    final seed = resolveSeeds(
      count: 1,
      randomize: _state.randomizeSeed,
      seedText: seedController.text,
    ).single;
    if (_state.randomizeSeed) seedController.text = seed.toString();
    return seed;
  }

  Future<Uint8List?> generateCascadeBeat(
    CascadeStitchedRequest request, {
    QuoteConfirmer? confirmQuote,
  }) {
    return _runSingleImage<Uint8List>('Cascade generation', () async {
      final seed = _singleSeed();
      final userId = _backendUserId;

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
        confirmQuote: confirmQuote,
        canPayRed: _access.canPay,
      );
      // The account was switched while the image was being made.
      if (_backendUserId != userId) return null;

      await _showToolResult(result, seed);
      return result.imageBytes;
    });
  }

  Future<Uint8List?> generateImg2Img(
    Img2ImgRequest request, {
    Uint8List? sourceImageBytes,
    QuoteConfirmer? confirmQuote,
  }) {
    return _runSingleImage<Uint8List>('Img2Img generation', () async {
      final seed = _singleSeed();
      final userId = _backendUserId;

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
        confirmQuote: confirmQuote,
        canPayRed: _access.canPay,
      );
      if (_backendUserId != userId) return null;

      await _showToolResult(
        result,
        seed,
        autoSave: (item) => _autoSaveImg2Img(item, sourceImageBytes),
      );
      return result.imageBytes;
    });
  }

  /// Saves an img2img result like every other tool result, next to a copy of
  /// its source (kept until the result is saved, so a failed save loses
  /// neither).
  Future<String?> _autoSaveImg2Img(
    GeneratedImageItem item,
    Uint8List? sourceImageBytes,
  ) async {
    final bytes = item.bytes;
    final metadata = item.metadata;
    if (bytes == null || metadata == null || kIsWeb) return null;
    final timestamp = DateFormat('yyyyMMdd_HHmmssSSS').format(DateTime.now());
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
    final basename = await _persistence.autoSaveToolResult(
      bytes,
      metadata,
      fileName: 'Gen_$timestamp.png',
    );
    if (basename != null && srcPath != null) {
      try {
        await File(srcPath).delete();
      } catch (_) {}
    }
    return basename;
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
    // Work that was in flight when the notifier went away still finishes.
    if (_disposed) return;
    super.notifyListeners();
  }

  /// Saves the session soon. Called where the form changes, never by a
  /// notification: results arriving or a flag flipping are not the session.
  void _scheduleSessionSave() {
    if (!_sessionReady || _disposed || !_prefs.rememberSession) return;
    _sessionSaveDebounce?.cancel();
    _sessionSaveDebounce = Timer(const Duration(seconds: 5), () {
      _saveSessionSnapshot();
    });
  }

  /// Writes the session now instead of when the delay is over.
  @visibleForTesting
  Future<void> flushSessionSave() {
    _sessionSaveDebounce?.cancel();
    return _saveSessionSnapshot();
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
    if (!_prefs.rememberSession) return;
    final snapshot = await _sessionService.restore();
    if (snapshot == null || _disposed) return;

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
      activeStyleNames: _migrateRestoredStyleNames(snapshot, _state.styles),
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
    _disposed = true;
    _runToken?.cancel();
    _tagDebounce?.cancel();
    _sessionSaveDebounce?.cancel();
    promptController.dispose();
    negativePromptController.dispose();
    seedController.dispose();
    super.dispose();
  }
}

/// How a call of [GenerationNotifier.generate] ended.
class GenerationOutcome {
  const GenerationOutcome({
    this.declined = false,
    this.authFailed = false,
    this.completed = 0,
    this.failed = 0,
    this.errorMessage,
  }) : rejected = false;

  /// Refused (another generation runs, or the seed is not valid): nothing was
  /// submitted.
  const GenerationOutcome.rejected([this.errorMessage])
    : rejected = true,
      declined = false,
      authFailed = false,
      completed = 0,
      failed = 0;

  final bool rejected;

  /// The user declined the gateway's price.
  final bool declined;
  final bool authFailed;

  /// Images that arrived, and images that did not (failed, cancelled, or
  /// still unfinished).
  final int completed;
  final int failed;
  final String? errorMessage;

  /// Every image of the run arrived.
  bool get succeeded =>
      !rejected && !declined && !authFailed && failed == 0 && completed > 0;
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
