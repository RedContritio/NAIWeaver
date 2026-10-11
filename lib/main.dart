import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'core/utils/app_snackbar.dart';
import 'core/widgets/confirm_dialog.dart';
import 'core/widgets/browser_native_text_area.dart';
import 'core/gateway/backend_gateway.dart';
import 'core/gateway/backend_permissions.dart';
import 'core/services/nai_cost_estimator.dart';
import 'core/services/client_diagnostics.dart';
import 'core/services/client_diagnostics_runtime.dart';
import 'features/auth/backend_auth_notifier.dart';
import 'features/auth/widgets/backend_auth_gate.dart';
import 'features/auth/widgets/backend_quota_badge.dart';
import 'features/auth/widgets/backend_queue_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'core/l10n/locale_notifier.dart';
import 'core/l10n/l10n_extensions.dart';
import 'core/services/path_service.dart';
import 'core/services/preferences_service.dart';
import 'core/services/backend_history_api.dart';
import 'core/services/update_service.dart';
import 'core/widgets/update_prompt.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'core/utils/responsive.dart';
import 'core/utils/resizable_lines.dart';
import 'core/utils/wheel_scroll.dart';
import 'core/widgets/help_dialog.dart';
import 'core/widgets/pin_lock_gate.dart';
import 'core/theme/theme_notifier.dart';
import 'core/theme/theme_extensions.dart';
import 'core/theme/vision_tokens.dart';
import 'features/generation/providers/generation_notifier.dart';
import 'features/generation/widgets/generation_page_layout.dart';
import 'features/generation/widgets/generation_mobile_sheet.dart';
import 'features/generation/widgets/generation_results_workspace.dart';
import 'features/generation/widgets/generation_seed_control.dart';
import 'features/generation/widgets/settings_panel.dart';
import 'features/tools/tools_hub_screen.dart';
import 'features/tools/providers/wildcard_notifier.dart';
import 'features/tools/providers/tag_library_notifier.dart';
import 'features/gallery/providers/gallery_notifier.dart';
import 'features/gallery/ui/gallery_screen.dart';
import 'features/history/server_history_screen.dart';
import 'features/generation/widgets/character_shelf.dart';
import 'core/ml/ml_notifier.dart';
import 'features/tools/cascade/providers/cascade_notifier.dart';
import 'features/tools/canvas/providers/canvas_notifier.dart';
import 'features/tools/img2img/providers/img2img_notifier.dart';
import 'features/tools/cascade/widgets/cascade_playback_view.dart';
import 'features/director_ref/providers/director_ref_notifier.dart';
import 'features/vibe_transfer/providers/vibe_transfer_notifier.dart';
import 'features/tools/slideshow/providers/slideshow_notifier.dart';
import 'features/tools/director_tools/providers/director_tools_notifier.dart';
import 'features/tools/enhance/providers/enhance_notifier.dart';
import 'features/text_gen/providers/text_gen_notifier.dart';
import 'features/characters/providers/character_library_notifier.dart';
import 'features/characters/gen/providers/character_gen_notifier.dart';
import 'features/characters/services/character_library_service.dart';
import 'features/characters/services/closet_service.dart';
import 'core/widgets/tag_suggestion_overlay.dart';
import 'core/jukebox/providers/jukebox_notifier.dart';
import 'core/jukebox/services/jukebox_audio_handler.dart';
import 'core/services/tag_service.dart';
import 'core/services/wiki_service.dart';
import 'core/services/wildcard_service.dart';
import 'package:audio_service/audio_service.dart';

class _AppWindowListener extends WindowListener {
  final PreferencesService _prefs;
  _AppWindowListener(this._prefs);

  @override
  void onWindowClose() async {
    try {
      final bounds = await windowManager.getBounds();
      final maximized = await windowManager.isMaximized();
      // Don't persist a degenerate rect (can happen if the window was minimized
      // or mid-animation when closing) — it would make the next launch's window
      // invisible.
      if (bounds.width >= 400 && bounds.height >= 300) {
        await _prefs.saveWindowState(
          x: bounds.left,
          y: bounds.top,
          w: bounds.width,
          h: bounds.height,
          maximized: maximized,
        );
      }
    } catch (_) {}
    await windowManager.destroy();
  }
}

void main() {
  runZonedGuarded(
    () async {
      // Rescales Android mouse-wheel deltas so one notch ≈ one text line
      // instead of 3-4 (issue #14).
      NaiWidgetsBinding.ensureInitialized();
      ClientDiagnosticsRuntime.instance.start();
      if (kIsWeb) {
        await BrowserContextMenu.enableContextMenu();
      }
      final paths = await PathService.initialize();
      await paths.ensureDirectories();
      await paths.seedAssets();
      final prefs = await SharedPreferences.getInstance();
      final secureStorage = FlutterSecureStorage(
        aOptions: const AndroidOptions(encryptedSharedPreferences: true),
      );
      final preferencesService = PreferencesService(prefs, secureStorage);
      await preferencesService.migrateApiKey();

      // Restore window state on desktop
      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        await windowManager.ensureInitialized();
        final saved = preferencesService.windowBounds;
        // Only restore a saved rect if it's sane — a stale/garbage value (zero or
        // negative size, or a position far off any plausible screen) would leave
        // the window invisible. Otherwise fall back to a sensible default + center.
        final bool savedIsSane =
            saved != null &&
            saved.w >= 400 &&
            saved.h >= 300 &&
            saved.w <= 16384 &&
            saved.h <= 16384 &&
            saved.x > -16384 &&
            saved.x < 16384 &&
            saved.y > -16384 &&
            saved.y < 16384;
        if (savedIsSane) {
          await windowManager.setBounds(
            Rect.fromLTWH(saved.x, saved.y, saved.w, saved.h),
          );
        } else {
          await windowManager.setSize(const Size(1280, 800));
          await windowManager.center();
        }
        if (preferencesService.windowMaximized) {
          await windowManager.maximize();
        }
        // Make sure the window is actually visible and frontmost regardless of what
        // was restored — guards against an off-screen restore on a now-disconnected
        // monitor.
        await windowManager.show();
        await windowManager.focus();
        windowManager.setPreventClose(true);
        windowManager.addListener(_AppWindowListener(preferencesService));
      }

      final customOut = preferencesService.customOutputDir;
      if (customOut.isNotEmpty) {
        // The custom dir can vanish (SD card ejected). Fall back to the default
        // for this session but keep the pref, so the override comes back with
        // the card.
        try {
          Directory(customOut).createSync(recursive: true);
          paths.outputDirOverride = customOut;
        } catch (e) {
          debugPrint('Custom output dir unavailable, using default: $e');
        }
      }

      final tagService = TagService(filePath: paths.tagFilePath);
      final wildcardService = WildcardService(wildcardDir: paths.wildcardDir);
      final wikiService = WikiService();
      final characterLibraryService = CharacterLibraryService(
        charactersDir: paths.charactersDir,
      );
      final closetService = ClosetService(charactersDir: paths.charactersDir);

      JukeboxAudioHandler? audioHandler;
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        try {
          audioHandler = await AudioService.init(
            builder: () => JukeboxAudioHandler(),
            config: const AudioServiceConfig(
              androidNotificationChannelId: 'dev.naiweaver.app.jukebox',
              androidNotificationChannelName: 'NAIWeaver Jukebox',
              androidNotificationOngoing: true,
              androidStopForegroundOnPause: true,
              androidNotificationIcon: 'mipmap/ic_launcher',
            ),
          );
        } catch (e) {
          debugPrint('AudioService init failed: $e');
        }
      }

      FlutterError.onError = (details) {
        ClientDiagnostics.instance.record('flutter_error', {
          'exception_type': details.exception.runtimeType.toString(),
          'library': details.library,
        });
        FlutterError.presentError(details);
        debugPrint('FlutterError: ${details.exceptionAsString()}');
      };
      runApp(
        MultiProvider(
          providers: [
            Provider<PathService>.value(value: paths),
            Provider<PreferencesService>.value(value: preferencesService),
            ChangeNotifierProvider(
              create: (_) => ThemeNotifier(preferencesService),
            ),
            ChangeNotifierProvider(
              create: (_) => LocaleNotifier(preferencesService),
            ),
            ChangeNotifierProvider(
              create: (_) => BackendAuthNotifier()..initialize(),
            ),
            ChangeNotifierProxyProvider<BackendAuthNotifier, GalleryNotifier>(
              create: (_) => GalleryNotifier(
                outputDir: paths.outputDir,
                prefs: preferencesService,
              ),
              update: (context, auth, gallery) =>
                  gallery!..updateBackendUserId(auth.user?.id),
            ),
            ChangeNotifierProvider(
              create: (_) => DirectorRefNotifier()
                ..setDefaults(
                  strength: preferencesService.refLastStrength,
                  fidelity: preferencesService.refLastFidelity,
                  prefs: preferencesService,
                ),
            ),
            ChangeNotifierProvider(create: (_) => VibeTransferNotifier()),
            ChangeNotifierProvider(create: (_) => DirectorToolsNotifier()),
            ChangeNotifierProvider(create: (_) => EnhanceNotifier()),
            ChangeNotifierProvider(create: (_) => TextGenNotifier()),
            ChangeNotifierProvider(
              create: (_) => CharacterLibraryNotifier(
                service: characterLibraryService,
                closetService: closetService,
              )..loadAll(),
            ),
            ChangeNotifierProxyProvider2<
              CharacterLibraryNotifier,
              TextGenNotifier,
              CharacterGenNotifier
            >(
              create: (context) => CharacterGenNotifier(
                library: Provider.of<CharacterLibraryNotifier>(
                  context,
                  listen: false,
                ),
                textGen: Provider.of<TextGenNotifier>(context, listen: false),
              ),
              update: (context, library, textGen, previous) =>
                  (previous ??
                        CharacterGenNotifier(
                          library: library,
                          textGen: textGen,
                        ))
                    ..updateTextGen(textGen),
            ),
            Provider<TagService>.value(value: tagService),
            Provider<WildcardService>.value(value: wildcardService),
            Provider<WikiService>.value(value: wikiService),
            ChangeNotifierProxyProvider6<
              GalleryNotifier,
              DirectorRefNotifier,
              VibeTransferNotifier,
              DirectorToolsNotifier,
              EnhanceNotifier,
              BackendAuthNotifier,
              GenerationNotifier
            >(
              create: (context) => GenerationNotifier(
                preferences: preferencesService,
                tagService: tagService,
                wildcardService: wildcardService,
                outputDir: paths.outputDir,
                presetsFilePath: paths.presetsFilePath,
                stylesFilePath: paths.stylesFilePath,
                galleryNotifier: Provider.of<GalleryNotifier>(
                  context,
                  listen: false,
                ),
                characterLibrary: Provider.of<CharacterLibraryNotifier>(
                  context,
                  listen: false,
                ),
              ),
              update:
                  (
                    context,
                    gallery,
                    directorRef,
                    vibeTransfer,
                    directorTools,
                    enhance,
                    backendAuth,
                    previous,
                  ) {
                    previous?.updateGalleryNotifier(gallery);
                    previous?.updateDirectorRefNotifier(directorRef);
                    previous?.updateVibeTransferNotifier(vibeTransfer);
                    previous?.updateDirectorToolsNotifier(directorTools);
                    previous?.updateEnhanceNotifier(enhance);
                    previous?.updateTextGenNotifier(
                      context.read<TextGenNotifier>(),
                    );
                    previous?.updateBackendUserId(backendAuth.user?.id);
                    return previous!;
                  },
            ),
            ChangeNotifierProvider(
              create: (_) => WildcardNotifier(
                wildcardDir: paths.wildcardDir,
                tagService: tagService,
                wildcardService: wildcardService,
              ),
            ),
            ChangeNotifierProvider(
              create: (_) => TagLibraryNotifier(
                tagService: tagService,
                examplesDir: paths.examplesDir,
              ),
            ),
            ChangeNotifierProvider(
              create: (_) => MLNotifier(
                mlModelsDir: paths.mlModelsDir,
                prefs: preferencesService,
              ),
            ),
            ChangeNotifierProvider(create: (_) => CascadeNotifier()),
            ChangeNotifierProvider(create: (_) => Img2ImgNotifier()),
            ChangeNotifierProvider(create: (_) => CanvasNotifier()),
            ChangeNotifierProvider(
              create: (_) => SlideshowNotifier()
                ..loadFromJson(preferencesService.slideshowConfigs)
                ..setDefaultConfigId(preferencesService.defaultSlideshowId),
            ),
            ChangeNotifierProvider(
              create: (_) {
                final n = JukeboxNotifier(
                  soundfontsDir: paths.soundfontsDir,
                  customSongsDir: paths.customSongsDir,
                  customSongsJsonPath: paths.customSongsJsonPath,
                  prefs: preferencesService,
                )..initialize();
                audioHandler?.attachNotifier(n);
                return n;
              },
            ),
          ],
          child: Builder(
            builder: (context) {
              final themeNotifier = context.watch<ThemeNotifier>();
              final localeNotifier = context.watch<LocaleNotifier>();
              return ValueListenableBuilder<bool>(
                valueListenable: preferencesService.tooltipVisibilityNotifier,
                builder: (context, visible, child) =>
                    TooltipVisibility(visible: visible, child: child!),
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  scrollBehavior: const MaterialScrollBehavior().copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.stylus,
                      PointerDeviceKind.mouse,
                    },
                  ),
                  theme: themeNotifier.themeData,
                  locale: localeNotifier.locale,
                  localizationsDelegates: [
                    AppLocalizations.delegate,
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  supportedLocales: AppLocalizations.supportedLocales,
                  navigatorObservers: [DiagnosticsNavigatorObserver.instance],
                  home: PinLockGate(
                    prefs: preferencesService,
                    child: const BackendAuthGate(child: SimpleGeneratorApp()),
                  ),
                ),
              );
            },
          ),
        ),
      );
    },
    (error, stack) {
      ClientDiagnostics.instance.record('uncaught_zone_error', {
        'error_type': error.runtimeType.toString(),
      });
      debugPrint('Uncaught error: $error');
      debugPrint('$stack');
    },
  );
}

class SimpleGeneratorApp extends StatefulWidget {
  const SimpleGeneratorApp({super.key, this.historyApi});

  final BackendHistoryApi? historyApi;

  @override
  State<SimpleGeneratorApp> createState() => _SimpleGeneratorAppState();
}

class _SimpleGeneratorAppState extends State<SimpleGeneratorApp>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late VoidCallback _generationListener;
  GenerationNotifier? _listenedGenerationNotifier;
  late VoidCallback _promptDiagnosticsListener;
  late VoidCallback _negativePromptDiagnosticsListener;
  bool _diagnosticControllerListenersAttached = false;
  String? _lastGenerationDiagnosticSignature;
  String? _lastPromptDiagnosticSignature;
  String? _lastNegativePromptDiagnosticSignature;
  bool _isTouchingSuggestions = false;
  int _tagSuggestionIndex = -1;
  int? _mainPromptLines;
  bool _mainPromptLinesLoaded = false;
  final FocusNode _globalFocusNode = FocusNode(skipTraversal: true);
  final FocusNode _promptFocusNode = FocusNode();
  final GlobalKey _mainPromptAreaKey = GlobalKey(
    debugLabel: 'main-prompt-area',
  );
  final GlobalKey<GenerationMobileSheetState> _mobileGenerationSheetKey =
      GlobalKey<GenerationMobileSheetState>();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(
      begin: 0.2,
      end: 1.0,
    ).animate(_pulseController);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = context.read<GenerationNotifier>();
      _listenedGenerationNotifier = notifier;
      _generationListener = () => _onGenerationStateChanged(notifier);
      notifier.addListener(_generationListener);
      _promptDiagnosticsListener = () => _recordPromptEditingState(
        event: 'positive_prompt_editing_state_changed',
        controller: notifier.promptController,
        negative: false,
      );
      _negativePromptDiagnosticsListener = () => _recordPromptEditingState(
        event: 'negative_prompt_editing_state_changed',
        controller: notifier.negativePromptController,
        negative: true,
      );
      notifier.promptController.addListener(_promptDiagnosticsListener);
      notifier.negativePromptController.addListener(
        _negativePromptDiagnosticsListener,
      );
      _diagnosticControllerListenersAttached = true;
      _onGenerationStateChanged(notifier);
      _promptDiagnosticsListener();
      _negativePromptDiagnosticsListener();
      _maybeCheckForUpdate();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_mainPromptLinesLoaded) return;
    _mainPromptLines = context.read<PreferencesService>().uiMainPromptLines;
    _mainPromptLinesLoaded = true;
  }

  /// Background, once-per-day update check. Never blocks startup and never
  /// throws into the launch path; if an update is found (and not skipped),
  /// surfaces a non-intrusive SnackBar prompt.
  Future<void> _maybeCheckForUpdate() async {
    if (kIsWeb) return;
    try {
      final prefs = context.read<PreferencesService>();
      final now = DateTime.now().millisecondsSinceEpoch;
      const dayMs = 24 * 60 * 60 * 1000;
      if (now - prefs.lastUpdateCheck < dayMs) return;

      // Let first frame / model loading settle before hitting the network.
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;

      final info = await PackageInfo.fromPlatform();
      final result = await UpdateService.checkForUpdate(info.version);
      // Throttle regardless of outcome so a transient failure doesn't re-check
      // on every launch.
      await prefs.setLastUpdateCheck(now);

      if (!mounted) return;
      if (result.updateAvailable &&
          result.latestVersion != null &&
          result.latestVersion != prefs.skippedUpdateVersion) {
        showUpdatePrompt(context, result);
      }
    } catch (_) {
      // A launch-time update check must never crash or block the app.
    }
  }

  void _onGenerationStateChanged(GenerationNotifier notifier) {
    if (!mounted) return;
    final state = notifier.state;
    _recordGenerationState(notifier);

    // Control pulse animation
    if (state.isLoading) {
      if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
    } else {
      if (_pulseController.isAnimating) _pulseController.stop();
    }

    // Show auth error
    if (state.hasAuthError) {
      _showAuthError(context);
      notifier.clearAuthError();
    }

    // Show generation error
    if (state.errorMessage != null) {
      _showError(
        context,
        state.errorSuggestRandomSeed
            ? context.l.generationNoParametersVaried
            : state.errorMessage!,
        tone: state.errorTone,
        onRandomizeSeed: state.errorSuggestRandomSeed
            ? () => notifier.updateSettings(randomizeSeed: true)
            : null,
      );
      notifier.clearError();
    }

    // Show duplicate image warning
    if (state.duplicateImageDetected) {
      showAppSnackBar(
        context,
        context.l.duplicateImageWarning.toUpperCase(),
        color: Colors.orange,
        action: SnackBarAction(
          label: context.l.duplicateImageRandomize.toUpperCase(),
          textColor: Colors.orange,
          onPressed: () => notifier.updateSettings(randomizeSeed: true),
        ),
      );
      notifier.clearDuplicateWarning();
    }
  }

  void _recordPromptEditingState({
    required String event,
    required TextEditingController controller,
    required bool negative,
  }) {
    final value = controller.value;
    final signature = [
      value.text.length,
      value.selection.baseOffset,
      value.selection.extentOffset,
      value.composing.start,
      value.composing.end,
    ].join(':');
    if (negative) {
      if (_lastNegativePromptDiagnosticSignature == signature) return;
      _lastNegativePromptDiagnosticSignature = signature;
    } else {
      if (_lastPromptDiagnosticSignature == signature) return;
      _lastPromptDiagnosticSignature = signature;
    }
    ClientDiagnostics.instance.record(event, {
      'character_count': value.text.length,
      'selection_base_offset': value.selection.baseOffset,
      'selection_extent_offset': value.selection.extentOffset,
      'selection_valid': value.selection.isValid,
      'selection_collapsed': value.selection.isCollapsed,
      'composing_start': value.composing.start,
      'composing_end': value.composing.end,
      'composing_valid': value.composing.isValid,
    });
  }

  void _recordGenerationState(GenerationNotifier notifier) {
    final state = notifier.state;
    final tasks = state.generatedImages;
    final complete = tasks.where((item) => item.isComplete).length;
    final queued = tasks
        .where((item) => item.progress == GenerationTaskProgress.queued)
        .length;
    final generating = tasks
        .where((item) => item.progress == GenerationTaskProgress.generating)
        .length;
    final failed = tasks
        .where((item) => item.progress == GenerationTaskProgress.failed)
        .length;
    final rejected = tasks
        .where((item) => item.progress == GenerationTaskProgress.rejected)
        .length;
    final cancelled = tasks
        .where((item) => item.progress == GenerationTaskProgress.cancelled)
        .length;
    final selectedIndex = tasks.indexWhere(
      (item) => item.id == state.selectedGeneratedImageId,
    );
    final signature = [
      state.isLoading,
      state.batchCount,
      tasks.length,
      complete,
      queued,
      generating,
      failed,
      rejected,
      cancelled,
      selectedIndex,
      state.width,
      state.height,
      state.steps,
      state.scale,
      state.sampler,
      state.smea,
      state.smeaDyn,
      state.decrisper,
      state.activeStyleNames.length,
      state.characters.length,
      state.interactions.length,
      state.errorMessage != null,
      state.duplicateImageDetected,
    ].join(':');
    if (_lastGenerationDiagnosticSignature == signature) return;
    _lastGenerationDiagnosticSignature = signature;
    ClientDiagnostics.instance.record('generation_state_changed', {
      'is_loading': state.isLoading,
      'configured_batch_count': state.batchCount,
      'task_count': tasks.length,
      'completed_task_count': complete,
      'queued_task_count': queued,
      'generating_task_count': generating,
      'failed_task_count': failed,
      'rejected_task_count': rejected,
      'cancelled_task_count': cancelled,
      'selected_task_index': selectedIndex,
      'auto_follow_latest': state.autoFollowLatestImage,
      'width': state.width,
      'height': state.height,
      'steps': state.steps,
      'scale': state.scale,
      'sampler': state.sampler,
      'smea': state.smea,
      'smea_dyn': state.smeaDyn,
      'decrisper': state.decrisper,
      'random_mode': state.randomizeSeed,
      'active_style_count': state.activeStyleNames.length,
      'character_count': state.characters.length,
      'interaction_count': state.interactions.length,
      'positive_length': notifier.promptController.text.length,
      'negative_length': notifier.negativePromptController.text.length,
      'has_error': state.errorMessage != null,
      'error_tone': state.errorTone.name,
      'duplicate_detected': state.duplicateImageDetected,
      'use_curated': state.useCurated,
    });
  }

  /// Applies a main-prompt tag suggestion and surfaces the one outcome that
  /// needs user feedback: hitting the 6-character cap while routing a saved
  /// character to the editor.
  void _applyMainTagSuggestion(GenerationNotifier notifier, DanbooruTag tag) {
    final result = notifier.applyTagSuggestion(tag);
    if (result == ApplyTagResult.characterLimitReached && mounted) {
      showErrorSnackBar(context, context.l.charEditorCharacterLimitReached);
    }
  }

  void _showError(
    BuildContext context,
    String message, {
    GenerationErrorTone tone = GenerationErrorTone.general,
    VoidCallback? onRandomizeSeed,
  }) {
    final t = context.tRead;
    final pointColor = switch (tone) {
      GenerationErrorTone.greenPoints => t.accentSuccess,
      GenerationErrorTone.redPoints => t.accentDanger,
      GenerationErrorTone.general => null,
    };
    final pointMessageParts = message.split('点数');
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1A0000),
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: t.accentDanger, width: 0.5),
        ),
        content: Row(
          children: [
            Icon(Icons.error_outline, color: t.accentDanger, size: 16),
            const SizedBox(width: 12),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    color: t.accentDanger,
                    fontSize: t.fontSize(10),
                    letterSpacing: 1,
                    fontWeight: FontWeight.bold,
                  ),
                  children: pointColor == null || pointMessageParts.length != 2
                      ? [TextSpan(text: message)]
                      : [
                          TextSpan(text: pointMessageParts.first),
                          TextSpan(
                            text: '点数',
                            style: TextStyle(color: pointColor),
                          ),
                          TextSpan(text: pointMessageParts.last),
                        ],
                ),
              ),
            ),
          ],
        ),
        action: onRandomizeSeed == null
            ? null
            : SnackBarAction(
                label: context.l.generationRandomizeSeed.toUpperCase(),
                textColor: Colors.orange,
                onPressed: onRandomizeSeed,
              ),
      ),
    );
  }

  void _showAuthError(BuildContext context) {
    final t = context.tRead;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1A0000),
        duration: const Duration(seconds: 10),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: t.accentDanger, width: 0.5),
        ),
        content: Row(
          children: [
            Icon(Icons.error_outline, color: t.accentDanger, size: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.l.mainAuthError.toUpperCase(),
                style: TextStyle(
                  color: t.accentDanger,
                  fontSize: t.fontSize(10),
                  letterSpacing: 1,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: context.l.mainSettings.toUpperCase(),
          textColor: t.textPrimary,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    const ToolsHubScreen(initialToolId: 'settings'),
              ),
            );
          },
        ),
      ),
    );
  }

  void _cycleStyle(GenerationNotifier notifier, bool forward) {
    final styles = notifier.state.styles;
    if (styles.isEmpty) return;

    // Only cycle through non-default styles (preserve quality tags)
    final cyclableStyles = styles.where((s) => !s.isDefault).toList();
    if (cyclableStyles.isEmpty) return;

    final active = notifier.state.activeStyleNames;

    // Find current non-default active style
    final currentIndex = active.isNotEmpty
        ? cyclableStyles.indexWhere((s) => active.contains(s.name))
        : -1;

    final nextIndex = forward
        ? (currentIndex + 1) % cyclableStyles.length
        : (currentIndex - 1 + cyclableStyles.length) % cyclableStyles.length;

    // Only clear non-default active styles
    for (final name in [...active]) {
      if (!styles.any((s) => s.name == name && s.isDefault)) {
        notifier.toggleStyle(name);
      }
    }
    notifier.toggleStyle(cyclableStyles[nextIndex].name);

    ScaffoldMessenger.of(context).clearSnackBars();
    showAppSnackBar(context, cyclableStyles[nextIndex].name.toUpperCase());
  }

  void _adjustTagWeight(TextEditingController controller, double delta) {
    final text = controller.text;
    final sel = controller.selection;
    if (!sel.isValid || sel.baseOffset < 0) return;
    final cursor = sel.baseOffset;

    // Find tag boundaries (comma-delimited)
    int start = text.lastIndexOf(',', cursor - 1) + 1;
    int end = text.indexOf(',', cursor);
    if (end < 0) end = text.length;

    String tag = text.substring(start, end).trim();
    if (tag.isEmpty) return;

    // Parse existing weight: value::tag:: (NAI format) or legacy {tag:weight}
    double weight = 1.0;
    String bareTag = tag;

    // NAI format: 1.2::tag::
    final naiMatch = RegExp(r'^(-?[0-9.]+)::(.+)::$').firstMatch(tag);
    // Legacy format: {tag:weight}
    final legacyMatch = RegExp(r'^\{(.+):([0-9.-]+)\}$').firstMatch(tag);

    if (naiMatch != null) {
      weight = double.tryParse(naiMatch.group(1)!) ?? 1.0;
      bareTag = naiMatch.group(2)!;
    } else if (legacyMatch != null) {
      bareTag = legacyMatch.group(1)!;
      weight = double.tryParse(legacyMatch.group(2)!) ?? 1.0;
    } else if (tag.startsWith('{') && tag.endsWith('}')) {
      bareTag = tag.substring(1, tag.length - 1);
      weight = 1.05;
    }

    weight = ((weight + delta) * 10).round() / 10;

    // Format result using NAI's value::tag:: syntax
    String result;
    if ((weight - 1.0).abs() < 0.01) {
      result = bareTag;
    } else {
      result = '${weight.toStringAsFixed(1)}::$bareTag::';
    }

    // Preserve spacing
    final prefix = text.substring(
      start,
      start +
          (text.substring(start).length -
              text.substring(start).trimLeft().length),
    );
    final newText =
        text.substring(0, start) + prefix + result + text.substring(end);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: start + prefix.length + result.length,
      ),
    );
  }

  @override
  void dispose() {
    _globalFocusNode.dispose();
    _promptFocusNode.dispose();
    final notifier = _listenedGenerationNotifier;
    notifier?.removeListener(_generationListener);
    if (notifier != null && _diagnosticControllerListenersAttached) {
      notifier.promptController.removeListener(_promptDiagnosticsListener);
      notifier.negativePromptController.removeListener(
        _negativePromptDiagnosticsListener,
      );
    }
    _pulseController.dispose();
    super.dispose();
  }

  void _startGeneration(GenerationNotifier notifier, int imageBatchLimit) {
    final mobileSheet = _mobileGenerationSheetKey.currentState;
    if (mobileSheet != null) unawaited(mobileSheet.collapse());
    final future = notifier.generate(batchLimit: imageBatchLimit);
    if (!useBackendGateway) return;
    future.whenComplete(() {
      if (!mounted) return;
      unawaited(context.read<BackendAuthNotifier>().refreshSession());
    });
  }

  void _selectResultImage(GenerationNotifier notifier, String id) {
    _promptFocusNode.unfocus();
    notifier.selectGeneratedImage(id);
  }

  void _scheduleFreeImageClamp(GenerationState state) {
    final needsResolutionClamp = !AdvancedSettingsPanel.isFreeResolution(
      state.width,
      state.height,
    );
    final hasPaidPayloads =
        context.read<DirectorRefNotifier>().references.isNotEmpty ||
        context.read<VibeTransferNotifier>().vibes.isNotEmpty;
    final needsClamp =
        needsResolutionClamp ||
        state.steps > 28 ||
        state.smea ||
        state.smeaDyn ||
        hasPaidPayloads;
    if (!needsClamp) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = context.read<GenerationNotifier>();
      final current = notifier.state;
      final currentResolutionAllowed = AdvancedSettingsPanel.isFreeResolution(
        current.width,
        current.height,
      );
      notifier.updateSettings(
        width: currentResolutionAllowed ? null : 832,
        height: currentResolutionAllowed ? null : 1216,
        steps: current.steps > 28 ? 28 : null,
        smea: current.smea ? false : null,
        smeaDyn: current.smeaDyn ? false : null,
      );
      final directorRefs = context.read<DirectorRefNotifier>();
      if (directorRefs.references.isNotEmpty) {
        directorRefs.clearAll();
      }
      final vibeTransfers = context.read<VibeTransferNotifier>();
      if (vibeTransfers.vibes.isNotEmpty) {
        vibeTransfers.clearAll();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _buildScaffold(context);
  }

  Widget _buildScaffold(BuildContext context) {
    final notifier = context.watch<GenerationNotifier>();
    final cascadeNotifier = context.watch<CascadeNotifier>();
    final state = notifier.state;

    final isCascadeMode = cascadeNotifier.state.activeCascade != null;

    final mobile = isMobile(context);
    final compactGenerationLayout = MediaQuery.sizeOf(context).width <= 900;
    final t = context.t;
    final themeNotifier = context.watch<ThemeNotifier>();
    final useSidebar = isWidescreenLayout(
      context,
      themeNotifier.sidebarLayoutMode,
    );
    final promptOnLeft = themeNotifier.sidebarPromptPosition == 'left';
    final imageGenerationAllowed = canGenerateImage(context);
    final imageBatchLimit = backendImageBatchLimit(context);
    final backendUser = useBackendGateway
        ? context.watch<BackendAuthNotifier>().user
        : null;
    final showLocalGallery = !(useBackendGateway && kIsWeb);

    if (isFreeOnlyImageUser(context)) {
      _scheduleFreeImageClamp(state);
    }

    Widget scaffold = Focus(
      focusNode: _globalFocusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter &&
            HardwareKeyboard.instance.isControlPressed) {
          final n = context.read<GenerationNotifier>();
          if (imageGenerationAllowed && !n.state.isLoading) {
            _startGeneration(n, imageBatchLimit);
          }
          return KeyEventResult.handled;
        }
        // Alt+Left/Right → cycle style (works when the prompt field is not
        // focused; the prompt field has its own copy of this binding).
        if (HardwareKeyboard.instance.isAltPressed &&
            !HardwareKeyboard.instance.isControlPressed &&
            (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                event.logicalKey == LogicalKeyboardKey.arrowRight)) {
          _cycleStyle(
            context.read<GenerationNotifier>(),
            event.logicalKey == LogicalKeyboardKey.arrowRight,
          );
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          final mobileSheet = _mobileGenerationSheetKey.currentState;
          if (mobileSheet?.isExpanded ?? false) {
            await mobileSheet!.collapse();
            return;
          }
          // First: collapse settings panel if expanded
          if (notifier.state.isSettingsExpanded) {
            notifier.toggleSettings();
            return;
          }
          // Second: show exit confirmation
          final confirmed = await showConfirmDialog(
            context,
            title: context.l.commonConfirm,
            message: context.l.mainExitConfirmation,
            confirmLabel: context.l.commonConfirm,
          );
          if (confirmed == true && context.mounted) {
            SystemNavigator.pop();
          }
        },
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          backgroundColor: t.background,
          appBar: AppBar(
            title: Image.asset(
              'assets/logo.png',
              height: 28,
              filterQuality: FilterQuality.medium,
              color: t.logoColor,
              colorBlendMode: BlendMode.srcIn,
            ),
            centerTitle: false,
            backgroundColor: t.background,
            elevation: 0,
            toolbarHeight: mobile ? 48 : 32,
            actions: [
              if (context.read<PreferencesService>().showAnlasTracker)
                if (useBackendGateway && kIsWeb)
                  const BackendQuotaBadge()
                else if (state.anlas != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Tooltip(
                      message: context.l.mainRefreshAnlas,
                      child: InkWell(
                        onTap: () => notifier.fetchAnlas(),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: mobile ? 10 : 8,
                            vertical: mobile ? 4 : 2,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: t.borderMedium),
                            color: t.borderSubtle,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.toll,
                                size: mobile ? 14 : 11,
                                color: t.headerText,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${state.anlas}',
                                style: TextStyle(
                                  color: t.headerText,
                                  fontSize: t.fontSize(mobile ? 10 : 8),
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              IconButton(
                onPressed: () => showHelpDialog(context),
                icon: Icon(
                  Icons.help_outline,
                  color: t.headerText,
                  size: mobile ? 20 : 16,
                ),
                tooltip: context.l.mainHelp,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              if (showLocalGallery)
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const GalleryScreen(),
                      ),
                    );
                  },
                  child: Text(
                    context.l.mainGallery.toUpperCase(),
                    style: TextStyle(
                      color: t.headerText,
                      fontSize: t.fontSize(mobile ? 11 : 8),
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (useBackendGateway &&
                  hasBackendPermission(context, BackendPermission.historyRead))
                TextButton(
                  onPressed: () async {
                    final imported = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute<bool>(
                        builder: (context) =>
                            ServerHistoryScreen(api: widget.historyApi),
                      ),
                    );
                    if (imported != true || !mounted) return;
                    final sheet = _mobileGenerationSheetKey.currentState;
                    if (sheet != null) {
                      await sheet.openTab(GenerationMobileTab.prompt);
                    } else if (notifier.state.isSettingsExpanded) {
                      notifier.toggleSettings();
                    }
                  },
                  child: Text(
                    context.l.mainServerHistory.toUpperCase(),
                    style: TextStyle(
                      color: t.headerText,
                      fontSize: t.fontSize(mobile ? 11 : 8),
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ToolsHubScreen(),
                    ),
                  );
                },
                child: Text(
                  context.l.mainTools.toUpperCase(),
                  style: TextStyle(
                    color: t.headerText,
                    fontSize: t.fontSize(mobile ? 11 : 8),
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (useBackendGateway) const BackendQueueBadge(),
              if (useBackendGateway)
                PopupMenuButton<String>(
                  tooltip: backendUser?.username ?? context.l.gatewayLogout,
                  color: t.surfaceHigh,
                  icon: Icon(
                    Icons.account_circle_outlined,
                    color: t.headerText,
                    size: mobile ? 20 : 16,
                  ),
                  onSelected: (value) {
                    if (value == 'logout') {
                      context.read<BackendAuthNotifier>().logout();
                    }
                  },
                  itemBuilder: (context) => [
                    if (backendUser != null)
                      PopupMenuItem<String>(
                        enabled: false,
                        child: Text(
                          backendUser.username,
                          style: TextStyle(
                            color: t.textTertiary,
                            fontSize: t.fontSize(11),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    PopupMenuItem<String>(
                      value: 'logout',
                      child: Row(
                        children: [
                          Icon(Icons.logout, size: 16, color: t.textPrimary),
                          const SizedBox(width: 8),
                          Text(
                            context.l.gatewayLogout,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: t.fontSize(11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
          body: SafeArea(
            bottom: false,
            left: false,
            right: false,
            child: useSidebar
                ? _buildSidebarBody(
                    context,
                    notifier,
                    state,
                    isCascadeMode,
                    mobile,
                    t,
                    promptOnLeft,
                  )
                : compactGenerationLayout
                ? _buildMobileBody(
                    context,
                    notifier,
                    state,
                    isCascadeMode,
                    mobile,
                    t,
                  )
                : _buildDefaultBody(
                    context,
                    notifier,
                    state,
                    isCascadeMode,
                    mobile,
                    t,
                  ),
          ),
        ),
      ),
    );

    return isDesktopPlatform()
        ? DropTarget(
            onDragDone: (details) async {
              if (details.files.isNotEmpty) {
                try {
                  await notifier.importImageMetadata(
                    File(details.files.first.path),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.l.mainImportFailed(e.toString())),
                    ),
                  );
                }
              }
            },
            onDragEntered: (details) => notifier.setDragging(true),
            onDragExited: (details) => notifier.setDragging(false),
            child: scaffold,
          )
        : scaffold;
  }

  Widget _buildMobileBody(
    BuildContext context,
    GenerationNotifier notifier,
    GenerationState state,
    bool isCascadeMode,
    bool mobile,
    VisionTokens t,
  ) {
    if (isCascadeMode) {
      return GenerationPageLayout(
        results: _buildDefaultResultsArea(context, notifier, state, mobile),
        footer: const CascadePlaybackView(),
      );
    }

    final activeDirectorRefCount = context
        .watch<DirectorRefNotifier>()
        .references
        .where((reference) => reference.enabled)
        .length;
    final activeVibeCount = context
        .watch<VibeTransferNotifier>()
        .vibes
        .where((vibe) => vibe.enabled)
        .length;

    void manageStyles() {
      String? activeStyle;
      for (final name in notifier.state.activeStyleNames) {
        final style = notifier.state.styles
            .where((candidate) => candidate.name == name)
            .firstOrNull;
        if (style != null && !style.isDefault) {
          activeStyle = name;
          break;
        }
      }
      activeStyle ??= notifier.state.activeStyleNames.firstOrNull;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ToolsHubScreen(
            initialToolId: 'styles',
            initialStyleName: activeStyle,
          ),
        ),
      );
    }

    void editStyle(String styleName) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ToolsHubScreen(
            initialToolId: 'styles',
            initialStyleName: styleName,
          ),
        ),
      );
    }

    return GenerationPageLayout(
      // Resolved inside the layout, where the sheet measures itself.
      overlayReservedHeightOf: GenerationMobileSheet.collapsedHeightOf,
      results: _buildDefaultResultsArea(context, notifier, state, mobile),
      footer: const SizedBox.shrink(),
      overlay: Positioned.fill(
        child: GenerationMobileSheet(
          key: _mobileGenerationSheetKey,
          promptLabel: context.l.generationSheetPrompt.toUpperCase(),
          inputsLabel: context.l.generationSheetInputs.toUpperCase(),
          parametersLabel: context.l.generationSheetParameters.toUpperCase(),
          inputCount: activeDirectorRefCount + activeVibeCount,
          compactPrompt: ValueListenableBuilder<TextEditingValue>(
            valueListenable: notifier.promptController,
            builder: (context, value, _) {
              final prompt = value.text.trim();
              return Row(
                children: [
                  Icon(Icons.edit_outlined, size: 16, color: t.textDisabled),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      prompt.isEmpty
                          ? context.l.mainEnterPrompt.toUpperCase()
                          : prompt.replaceAll('\n', ' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: prompt.isEmpty ? t.hintText : t.textSecondary,
                        fontSize: t.fontSize(11),
                        letterSpacing: prompt.isEmpty ? 1.2 : 0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          compactActions: _buildCompactGenerationAction(
            context,
            notifier,
            state,
            t,
          ),
          prompt: GenerationMobilePromptPage(
            prompt: _buildPromptArea(
              context,
              notifier,
              state,
              true,
              t,
              showQuickSeed: false,
              embedded: true,
            ),
            settings: ExpandedSettingsContent(
              group: GenerationSettingsGroup.prompt,
              forceCompact: true,
              ownsScrollView: false,
              onManageStyles: manageStyles,
              onEditStyle: editStyle,
              onSavePreset: () => _showSavePresetDialog(context, notifier),
            ),
          ),
          inputs: ExpandedSettingsContent(
            group: GenerationSettingsGroup.inputs,
            forceCompact: true,
            onManageStyles: manageStyles,
            onEditStyle: editStyle,
            onSavePreset: () => _showSavePresetDialog(context, notifier),
          ),
          parameters: ExpandedSettingsContent(
            group: GenerationSettingsGroup.parameters,
            forceCompact: true,
            onManageStyles: manageStyles,
            onEditStyle: editStyle,
            onSavePreset: () => _showSavePresetDialog(context, notifier),
          ),
        ),
      ),
    );
  }

  // — Default body (classic bottom-sheet layout) —
  Widget _buildDefaultBody(
    BuildContext context,
    GenerationNotifier notifier,
    GenerationState state,
    bool isCascadeMode,
    bool mobile,
    VisionTokens t,
  ) {
    final settingsBarHeight = AdvancedSettingsPanel.collapsedExtent(context);
    return GenerationPageLayout(
      overlayReservedHeight: settingsBarHeight,
      results: _buildDefaultResultsArea(context, notifier, state, mobile),
      footer: isCascadeMode
          ? const CascadePlaybackView()
          : state.isSettingsExpanded
          ? const SizedBox.shrink()
          : _buildPromptArea(context, notifier, state, mobile, t),
      overlay: AdvancedSettingsPanel(
        prompt: isCascadeMode
            ? null
            : _buildPromptArea(
                context,
                notifier,
                state,
                mobile,
                t,
                showQuickSeed: false,
                embedded: true,
              ),
        onManageStyles: () {
          String? activeStyle;
          for (final name in notifier.state.activeStyleNames) {
            final style = notifier.state.styles
                .where((s) => s.name == name)
                .firstOrNull;
            if (style != null && !style.isDefault) {
              activeStyle = name;
              break;
            }
          }
          activeStyle ??= notifier.state.activeStyleNames.isNotEmpty
              ? notifier.state.activeStyleNames.first
              : null;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ToolsHubScreen(
                initialToolId: 'styles',
                initialStyleName: activeStyle,
              ),
            ),
          );
        },
        onEditStyle: (styleName) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ToolsHubScreen(
                initialToolId: 'styles',
                initialStyleName: styleName,
              ),
            ),
          );
        },
        onSavePreset: () => _showSavePresetDialog(context, notifier),
      ),
    );
  }

  Widget _buildDefaultResultsArea(
    BuildContext context,
    GenerationNotifier notifier,
    GenerationState state,
    bool mobile,
  ) {
    return GenerationResultsWorkspace(
      notifier: notifier,
      state: state,
      mobile: mobile,
      pulseAnimation: _pulseAnimation,
      onSelectImage: (id) => _selectResultImage(notifier, id),
    );
  }

  // — Sidebar body (widescreen layout) —
  Widget _buildSidebarBody(
    BuildContext context,
    GenerationNotifier notifier,
    GenerationState state,
    bool isCascadeMode,
    bool mobile,
    VisionTokens t,
    bool promptOnLeft,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final widthMode = context.watch<ThemeNotifier>().sidebarWidthMode;
    final double sidebarWidth;
    if (widthMode == 'compact') {
      sidebarWidth = (screenWidth * 0.28).clamp(300.0, 380.0);
    } else {
      sidebarWidth = (screenWidth * 0.38).clamp(420.0, 560.0);
    }

    return Row(
      children: [
        // Left sidebar
        SizedBox(
          width: sidebarWidth,
          child: Container(
            decoration: BoxDecoration(
              color: t.surfaceHigh,
              border: Border(right: BorderSide(color: t.borderStrong)),
            ),
            child: Column(
              children: [
                Expanded(
                  child: ExpandedSettingsContent(
                    inSidebar: true,
                    onManageStyles: () {
                      String? activeStyle;
                      for (final name in notifier.state.activeStyleNames) {
                        final style = notifier.state.styles
                            .where((s) => s.name == name)
                            .firstOrNull;
                        if (style != null && !style.isDefault) {
                          activeStyle = name;
                          break;
                        }
                      }
                      activeStyle ??= notifier.state.activeStyleNames.isNotEmpty
                          ? notifier.state.activeStyleNames.first
                          : null;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ToolsHubScreen(
                            initialToolId: 'styles',
                            initialStyleName: activeStyle,
                          ),
                        ),
                      );
                    },
                    onEditStyle: (styleName) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ToolsHubScreen(
                            initialToolId: 'styles',
                            initialStyleName: styleName,
                          ),
                        ),
                      );
                    },
                    onSavePreset: () =>
                        _showSavePresetDialog(context, notifier),
                  ),
                ),
                if (promptOnLeft && !isCascadeMode)
                  _buildPromptArea(
                    context,
                    notifier,
                    state,
                    mobile,
                    t,
                    useSidebarStyle: true,
                    showQuickSeed: false,
                  ),
              ],
            ),
          ),
        ),

        // Right content area
        Expanded(
          child: GenerationPageLayout(
            results: GenerationResultsWorkspace(
              notifier: notifier,
              state: state,
              mobile: mobile,
              pulseAnimation: _pulseAnimation,
              onSelectImage: (id) => _selectResultImage(notifier, id),
            ),
            footer: isCascadeMode
                ? const CascadePlaybackView()
                : promptOnLeft
                ? const SizedBox.shrink()
                : SafeArea(
                    top: false,
                    left: false,
                    right: false,
                    child: _buildPromptArea(
                      context,
                      notifier,
                      state,
                      mobile,
                      t,
                      showQuickSeed: false,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // — Shared prompt area widget —
  Widget _buildPromptArea(
    BuildContext context,
    GenerationNotifier notifier,
    GenerationState state,
    bool mobile,
    VisionTokens t, {
    bool useSidebarStyle = false,
    bool showQuickSeed = true,
    bool embedded = false,
  }) {
    final imageGenerationAllowed = canGenerateImage(context);
    final imageBatchLimit = backendImageBatchLimit(context);
    final paidImageFeaturesAllowed = canUsePaidImageFeatures(context);
    final vibeFeatureAllowed =
        paidImageFeaturesAllowed &&
        hasBackendPermission(context, BackendPermission.imageEncodeVibe);
    final activeDirectorRefCount = context
        .watch<DirectorRefNotifier>()
        .references
        .where((r) => r.enabled)
        .length;
    final activeVibeCount = context
        .watch<VibeTransferNotifier>()
        .vibes
        .where((v) => v.enabled)
        .length;
    final usesRedPoints =
        state.smea ||
        state.smeaDyn ||
        activeDirectorRefCount > 0 ||
        activeVibeCount > 0 ||
        !isOpusFreeBaseImage(
          width: state.width.toInt(),
          height: state.height.toInt(),
          steps: state.steps.toInt(),
          hasImageInput: false,
        );
    final greenPointDiscount =
        context.watch<BackendAuthNotifier>().quota?.free.greenPointDiscount ??
        0;
    final imageCostEstimate = estimateNaiImageCost(
      width: state.width.toInt(),
      height: state.height.toInt(),
      steps: state.steps.toInt(),
      smea: state.smea,
      smeaDyn: state.smeaDyn,
      serialImages: math.max(1, math.min(state.batchCount, imageBatchLimit)),
      directorReferenceCount: paidImageFeaturesAllowed
          ? activeDirectorRefCount
          : 0,
      vibeReferenceCount: vibeFeatureAllowed ? activeVibeCount : 0,
      isOpus: false,
    );
    final defaultPromptLines = embedded
        ? 4
        : useSidebarStyle
        ? 5
        : (mobile ? t.promptMaxLines + 2 : t.promptMaxLines + 1);
    final promptLines = (_mainPromptLines ?? defaultPromptLines).clamp(
      kMainPromptMinLines,
      kMainPromptMaxLines,
    );
    final actionWidth = mobile ? 72.0 : 68.0;
    final showCostEstimate = useBackendGateway && imageGenerationAllowed;
    return Container(
      key: _mainPromptAreaKey,
      padding: embedded
          ? const EdgeInsets.fromLTRB(12, 6, 12, 8)
          : EdgeInsets.fromLTRB(16, useSidebarStyle ? 8 : 0, 16, 12),
      decoration: embedded
          ? null
          : useSidebarStyle
          ? BoxDecoration(
              color: t.surfaceHigh,
              border: Border(top: BorderSide(color: t.borderMedium)),
            )
          : BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  t.background.withValues(alpha: 0.8),
                  t.background,
                ],
                stops: const [0.4, 0.7, 1.0],
              ),
            ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!embedded)
            Selector<GenerationNotifier, String>(
              selector: (_, n) => n.state.characterEditorMode,
              builder: (context, mode, _) {
                if (mode == 'compact') return const CharacterShelf();
                return const SizedBox.shrink();
              },
            ),
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _isTouchingSuggestions = true,
            onPointerUp: (_) => Future.delayed(
              const Duration(milliseconds: 300),
              () => _isTouchingSuggestions = false,
            ),
            onPointerCancel: (_) => _isTouchingSuggestions = false,
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: TagSuggestionOverlay(
                suggestions: state.tagSuggestions,
                onTagSelected: (tag) {
                  _applyMainTagSuggestion(notifier, tag);
                  setState(() => _tagSuggestionIndex = -1);
                },
                selectedIndex: _tagSuggestionIndex,
              ),
            ),
          ),
          if (showQuickSeed &&
              context.read<PreferencesService>().showSeedControl)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: GenerationSeedControl(
                controller: notifier.seedController,
                randomize: state.randomizeSeed,
                onRandomizeChanged: (randomize) =>
                    notifier.updateSettings(randomizeSeed: randomize),
                variant: GenerationSeedControlVariant.compact,
              ),
            ),
          ResizableGenerationComposer(
            promptLines: promptLines,
            promptFontSize: t.promptFontSize - 1,
            actionWidth: actionWidth,
            onPromptLinesChanged: (lines) {
              setState(() => _mainPromptLines = lines);
            },
            onPromptResizeDone: (lines) {
              final clamped = lines.clamp(
                kMainPromptMinLines,
                kMainPromptMaxLines,
              );
              setState(() => _mainPromptLines = clamped);
              unawaited(
                context.read<PreferencesService>().setUiMainPromptLines(
                  clamped,
                ),
              );
            },
            promptInput: Focus(
              onFocusChange: (hasFocus) {
                if (hasFocus) {
                  final mobileSheet = _mobileGenerationSheetKey.currentState;
                  if (mobileSheet != null) {
                    unawaited(mobileSheet.openTab(GenerationMobileTab.prompt));
                  }
                } else {
                  Future.delayed(const Duration(milliseconds: 200), () {
                    if (!_isTouchingSuggestions) {
                      notifier.clearTagSuggestions();
                      setState(() => _tagSuggestionIndex = -1);
                    }
                  });
                }
              },
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                  return KeyEventResult.ignored;
                }
                final currentState = notifier.state;

                // Ctrl+Enter → generate
                if (event.logicalKey == LogicalKeyboardKey.enter &&
                    HardwareKeyboard.instance.isControlPressed) {
                  if (imageGenerationAllowed && !currentState.isLoading) {
                    _startGeneration(notifier, imageBatchLimit);
                  }
                  return KeyEventResult.handled;
                }

                // Alt+Left/Right → cycle style. (Was Ctrl+Shift+Arrow, but
                // that collided with the OS word-by-word text-selection
                // shortcut inside the prompt field — Alt+Arrow leaves native
                // selection free.)
                if (HardwareKeyboard.instance.isAltPressed &&
                    !HardwareKeyboard.instance.isControlPressed &&
                    (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                        event.logicalKey == LogicalKeyboardKey.arrowRight)) {
                  _cycleStyle(
                    notifier,
                    event.logicalKey == LogicalKeyboardKey.arrowRight,
                  );
                  return KeyEventResult.handled;
                }

                // Ctrl+Up/Down → adjust tag weight
                if (HardwareKeyboard.instance.isControlPressed &&
                    (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                        event.logicalKey == LogicalKeyboardKey.arrowDown)) {
                  final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
                  _adjustTagWeight(notifier.promptController, up ? 0.1 : -0.1);
                  return KeyEventResult.handled;
                }

                final suggestions = currentState.tagSuggestions;
                if (suggestions.isEmpty) return KeyEventResult.ignored;

                if (event.logicalKey == LogicalKeyboardKey.tab) {
                  if (HardwareKeyboard.instance.isShiftPressed) {
                    setState(() {
                      _tagSuggestionIndex = (_tagSuggestionIndex - 1).clamp(
                        -1,
                        suggestions.length - 1,
                      );
                    });
                  } else {
                    setState(() {
                      _tagSuggestionIndex =
                          (_tagSuggestionIndex + 1) % suggestions.length;
                    });
                  }
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.enter &&
                    _tagSuggestionIndex >= 0 &&
                    _tagSuggestionIndex < suggestions.length) {
                  _applyMainTagSuggestion(
                    notifier,
                    suggestions[_tagSuggestionIndex],
                  );
                  setState(() => _tagSuggestionIndex = -1);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: BrowserNativeTextArea(
                controller: notifier.promptController,
                focusNode: _promptFocusNode,
                hintText: context.l.mainEnterPrompt.toUpperCase(),
                style: TextStyle(
                  fontSize: t.promptFontSize - 1,
                  letterSpacing: 0.5,
                ),
                backgroundColor: t.background.withValues(alpha: 0.8),
                borderColor: t.borderMedium,
                selectionColor: t.accent.withValues(alpha: 0.72),
                selectionTextColor:
                    ThemeData.estimateBrightnessForColor(t.accent) ==
                        Brightness.dark
                    ? Colors.white
                    : Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                onChanged: (val) {
                  notifier.handleTagSuggestions(
                    val,
                    notifier.promptController.selection,
                  );
                  setState(() => _tagSuggestionIndex = -1);
                },
                onBlur: () {
                  Future.delayed(const Duration(milliseconds: 200), () {
                    if (mounted && !_isTouchingSuggestions) {
                      notifier.clearTagSuggestions();
                      setState(() => _tagSuggestionIndex = -1);
                    }
                  });
                },
                onKeyDown: (key, control, alt, shift) {
                  final currentState = notifier.state;
                  if (key == 'Enter' && control) {
                    if (imageGenerationAllowed && !currentState.isLoading) {
                      _startGeneration(notifier, imageBatchLimit);
                    }
                    return true;
                  }
                  if (alt &&
                      !control &&
                      (key == 'ArrowLeft' || key == 'ArrowRight')) {
                    _cycleStyle(notifier, key == 'ArrowRight');
                    return true;
                  }
                  if (control && (key == 'ArrowUp' || key == 'ArrowDown')) {
                    _adjustTagWeight(
                      notifier.promptController,
                      key == 'ArrowUp' ? 0.1 : -0.1,
                    );
                    return true;
                  }
                  final suggestions = currentState.tagSuggestions;
                  if (suggestions.isEmpty) return false;
                  if (key == 'Tab') {
                    setState(() {
                      if (shift) {
                        _tagSuggestionIndex = (_tagSuggestionIndex - 1).clamp(
                          -1,
                          suggestions.length - 1,
                        );
                      } else {
                        _tagSuggestionIndex =
                            (_tagSuggestionIndex + 1) % suggestions.length;
                      }
                    });
                    return true;
                  }
                  if (key == 'Enter' &&
                      _tagSuggestionIndex >= 0 &&
                      _tagSuggestionIndex < suggestions.length) {
                    _applyMainTagSuggestion(
                      notifier,
                      suggestions[_tagSuggestionIndex],
                    );
                    setState(() => _tagSuggestionIndex = -1);
                    return true;
                  }
                  return false;
                },
                fallback: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.stylus,
                    },
                  ),
                  child: TextField(
                    controller: notifier.promptController,
                    focusNode: _promptFocusNode,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    onChanged: (val) {
                      notifier.handleTagSuggestions(
                        val,
                        notifier.promptController.selection,
                      );
                      setState(() => _tagSuggestionIndex = -1);
                    },
                    onTapOutside: (_) {
                      Future.delayed(const Duration(milliseconds: 200), () {
                        if (!_isTouchingSuggestions) {
                          notifier.clearTagSuggestions();
                        }
                      });
                    },
                    onSubmitted: (_) {
                      if (state.tagSuggestions.isNotEmpty) {
                        _applyMainTagSuggestion(
                          notifier,
                          state.tagSuggestions.first,
                        );
                      } else {
                        if (imageGenerationAllowed) {
                          _startGeneration(notifier, imageBatchLimit);
                        }
                      }
                    },
                    style: TextStyle(
                      fontSize: t.promptFontSize - 1,
                      letterSpacing: 0.5,
                    ),
                    decoration: InputDecoration(
                      hintText: context.l.mainEnterPrompt.toUpperCase(),
                      hintStyle: TextStyle(
                        fontSize: t.fontSize(mobile ? 12 : 9),
                        letterSpacing: 2,
                        color: t.hintText,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      fillColor: t.background.withValues(alpha: 0.8),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: t.borderMedium),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: t.borderMedium),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            action: PromptGenerationAction(
              estimateHeight: mobile ? 26 : 23,
              estimate: showCostEstimate
                  ? _buildGenerationCostBadge(
                      context,
                      imageCostEstimate,
                      mobile,
                      t,
                      usesRedPoints,
                      greenPointDiscount,
                    )
                  : null,
              generateButton: ElevatedButton(
                onPressed: state.isLoading || !imageGenerationAllowed
                    ? null
                    : () {
                        FocusScope.of(context).unfocus();
                        _startGeneration(notifier, imageBatchLimit);
                      },
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: t.accent,
                  foregroundColor: t.background,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  elevation: 0,
                ),
                child: state.isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: t.background,
                        ),
                      )
                    : const Icon(Icons.arrow_forward_ios, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactGenerationAction(
    BuildContext context,
    GenerationNotifier notifier,
    GenerationState state,
    VisionTokens t,
  ) {
    final imageGenerationAllowed = canGenerateImage(context);
    final imageBatchLimit = backendImageBatchLimit(context);
    final paidImageFeaturesAllowed = canUsePaidImageFeatures(context);
    final vibeFeatureAllowed =
        paidImageFeaturesAllowed &&
        hasBackendPermission(context, BackendPermission.imageEncodeVibe);
    final activeDirectorRefCount = context
        .watch<DirectorRefNotifier>()
        .references
        .where((reference) => reference.enabled)
        .length;
    final activeVibeCount = context
        .watch<VibeTransferNotifier>()
        .vibes
        .where((vibe) => vibe.enabled)
        .length;
    final usesRedPoints =
        state.smea ||
        state.smeaDyn ||
        activeDirectorRefCount > 0 ||
        activeVibeCount > 0 ||
        !isOpusFreeBaseImage(
          width: state.width.toInt(),
          height: state.height.toInt(),
          steps: state.steps.toInt(),
          hasImageInput: false,
        );
    final estimate = estimateNaiImageCost(
      width: state.width.toInt(),
      height: state.height.toInt(),
      steps: state.steps.toInt(),
      smea: state.smea,
      smeaDyn: state.smeaDyn,
      serialImages: math.max(1, math.min(state.batchCount, imageBatchLimit)),
      directorReferenceCount: paidImageFeaturesAllowed
          ? activeDirectorRefCount
          : 0,
      vibeReferenceCount: vibeFeatureAllowed ? activeVibeCount : 0,
      isOpus: false,
    );
    final greenPointDiscount =
        context.watch<BackendAuthNotifier>().quota?.free.greenPointDiscount ??
        0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (useBackendGateway && imageGenerationAllowed) ...[
          SizedBox(
            width: 92,
            height: 28,
            child: _buildGenerationCostBadge(
              context,
              estimate,
              true,
              t,
              usesRedPoints,
              greenPointDiscount,
            ),
          ),
          const SizedBox(width: 6),
        ],
        SizedBox(
          width: 42,
          height: 38,
          child: ElevatedButton(
            onPressed: state.isLoading || !imageGenerationAllowed
                ? null
                : () {
                    FocusScope.of(context).unfocus();
                    _startGeneration(notifier, imageBatchLimit);
                  },
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.zero,
              backgroundColor: t.accent,
              foregroundColor: t.background,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
              elevation: 0,
            ),
            child: state.isLoading
                ? SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: t.background,
                    ),
                  )
                : const Icon(Icons.arrow_forward_ios, size: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildGenerationCostBadge(
    BuildContext context,
    NaiImageCostEstimate estimate,
    bool mobile,
    VisionTokens t,
    bool usesRedPoints,
    int greenPointDiscount,
  ) {
    final l = context.l;
    final costColor = usesRedPoints ? t.accentDanger : t.accentSuccess;
    final displayedCost = usesRedPoints
        ? estimate.totalAnlas
        : (estimate.totalAnlas * (100 - greenPointDiscount) / 100).ceil();
    final label = '${l.mainEstimatedCostLabel} $displayedCost';
    final details = <String>[
      l.mainEstimatedCostTooltip,
      '${l.mainEstimatedCostBase}: ${estimate.baseAnlas} ${l.mainAnlas}',
      if (estimate.hasReferenceCost)
        '${l.mainEstimatedCostReference}: ${estimate.directorReferenceAnlas} ${l.mainAnlas}',
      if (estimate.hasVibeCost)
        '${l.mainEstimatedCostVibe}: ${estimate.vibeReferenceAnlas} ${l.mainAnlas}',
      if (estimate.serialImages > 1)
        '${l.mainEstimatedCostSerialImages}: ${estimate.serialImages}',
    ];

    return Tooltip(
      message: details.join('\n'),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: mobile ? 3 : 2),
        decoration: BoxDecoration(
          color: costColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: costColor.withValues(alpha: 0.35),
            width: 0.5,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.toll, size: mobile ? 13 : 11, color: costColor),
              const SizedBox(width: 4),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: t.fontSize(mobile ? 10 : 8),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSavePresetDialog(
    BuildContext context,
    GenerationNotifier notifier,
  ) {
    final TextEditingController nameController = TextEditingController();
    final t = context.tRead;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: t.surfaceHigh,
        title: Text(
          context.l.mainSavePreset.toUpperCase(),
          style: TextStyle(
            fontSize: t.fontSize(10),
            letterSpacing: 2,
            color: t.textSecondary,
          ),
        ),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(13)),
          decoration: InputDecoration(
            hintText: context.l.mainPresetName.toUpperCase(),
            hintStyle: TextStyle(color: t.textMinimal, fontSize: t.fontSize(9)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: t.borderMedium),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              context.l.commonCancel.toUpperCase(),
              style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(9)),
            ),
          ),
          TextButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                notifier.savePreset(nameController.text);
                Navigator.pop(context);
              }
            },
            child: Text(
              context.l.commonSave.toUpperCase(),
              style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(9)),
            ),
          ),
        ],
      ),
    );
  }
}
