import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../core/jukebox/services/jukebox_audio_handler.dart';
import '../core/services/client_diagnostics.dart';
import '../core/services/client_diagnostics_runtime.dart';
import '../core/services/path_service.dart';
import '../core/services/preferences_service.dart';
import '../core/services/tag_service.dart';
import '../core/services/wiki_service.dart';
import '../core/services/wildcard_service.dart';
import '../core/utils/wheel_scroll.dart';
import '../features/characters/services/character_library_service.dart';
import '../features/characters/services/closet_service.dart';
import '../l10n/app_localizations.dart';
import 'app.dart';

/// Everything that has to exist before the first frame.
class AppServices {
  AppServices({
    required this.paths,
    required this.preferences,
    required this.tagService,
    required this.wildcardService,
    required this.wikiService,
    required this.characterLibraryService,
    required this.closetService,
    required this.audioHandler,
  });

  final PathService paths;
  final PreferencesService preferences;
  final TagService tagService;
  final WildcardService wildcardService;
  final WikiService wikiService;
  final CharacterLibraryService characterLibraryService;
  final ClosetService closetService;
  final JukeboxAudioHandler? audioHandler;
}

/// Saves the window rectangle when the desktop window closes.
class _AppWindowListener extends WindowListener {
  _AppWindowListener(this._prefs);

  final PreferencesService _prefs;

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

bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// Restores the saved window rectangle, or a sane default.
Future<void> _restoreWindow(PreferencesService prefs) async {
  await windowManager.ensureInitialized();
  final saved = prefs.windowBounds;
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
  if (prefs.windowMaximized) {
    await windowManager.maximize();
  }
  // Make sure the window is actually visible and frontmost regardless of what
  // was restored — guards against an off-screen restore on a now-disconnected
  // monitor.
  await windowManager.show();
  await windowManager.focus();
  windowManager.setPreventClose(true);
  windowManager.addListener(_AppWindowListener(prefs));
}

Future<JukeboxAudioHandler?> _initAudio() async {
  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return null;
  try {
    return await AudioService.init(
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
    return null;
  }
}

/// Initializes bindings, storage, the desktop window and the shared services.
Future<AppServices> bootstrap() async {
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

  if (_isDesktop) await _restoreWindow(preferencesService);

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

  return AppServices(
    paths: paths,
    preferences: preferencesService,
    tagService: TagService(filePath: paths.tagFilePath),
    wildcardService: WildcardService(wildcardDir: paths.wildcardDir),
    wikiService: WikiService(),
    characterLibraryService: CharacterLibraryService(
      charactersDir: paths.charactersDir,
    ),
    closetService: ClosetService(charactersDir: paths.charactersDir),
    audioHandler: await _initAudio(),
  );
}

/// Shown when [bootstrap] throws: without it the app would stay blank.
class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // Preferences may be what failed, so the default locale is used.
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          final l = AppLocalizations.of(context);
          final theme = Theme.of(context);
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l.startupFailedTitle,
                        style: theme.textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${error.runtimeType}: $error',
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: onRetry,
                        child: Text(l.commonRetry),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Starts the app with [home] as the page behind the PIN and sign-in gates.
void runNaiWeaver({required Widget home}) {
  // Error reporting first, so start-up failures are recorded too.
  FlutterError.onError = (details) {
    ClientDiagnostics.instance.record('flutter_error', {
      'exception_type': details.exception.runtimeType.toString(),
      'library': details.library,
    });
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  runZonedGuarded(
    () async {
      Future<void> start() async {
        try {
          final services = await bootstrap();
          runApp(NaiWeaverApp(services: services, home: home));
        } catch (error, stack) {
          ClientDiagnostics.instance.record('bootstrap_failed', {
            'error_type': error.runtimeType.toString(),
          });
          debugPrint('Bootstrap failed: $error');
          debugPrint('$stack');
          runApp(
            _StartupFailureApp(error: error, onRetry: () => unawaited(start())),
          );
        }
      }

      await start();
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
