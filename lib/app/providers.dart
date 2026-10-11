import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../core/gateway/backend_permissions.dart';
import '../core/jukebox/providers/jukebox_notifier.dart';
import '../core/l10n/locale_notifier.dart';
import '../core/ml/ml_notifier.dart';
import '../core/services/client_diagnostics_runtime.dart';
import '../core/services/path_service.dart';
import '../core/services/preferences_service.dart';
import '../core/services/tag_service.dart';
import '../core/services/wiki_service.dart';
import '../core/services/wildcard_service.dart';
import '../core/theme/theme_notifier.dart';
import '../features/auth/backend_auth_notifier.dart';
import '../features/characters/gen/providers/character_gen_notifier.dart';
import '../features/characters/providers/character_library_notifier.dart';
import '../features/director_ref/providers/director_ref_notifier.dart';
import '../features/gallery/providers/gallery_notifier.dart';
import '../features/generation/providers/generation_notifier.dart';
import '../features/generation/services/reference_access_monitor.dart';
import '../features/text_gen/providers/text_gen_notifier.dart';
import '../features/tools/canvas/providers/canvas_notifier.dart';
import '../features/tools/cascade/providers/cascade_notifier.dart';
import '../features/tools/director_tools/providers/director_tools_notifier.dart';
import '../features/tools/enhance/providers/enhance_notifier.dart';
import '../features/tools/img2img/providers/img2img_notifier.dart';
import '../features/tools/providers/tag_library_notifier.dart';
import '../features/tools/providers/wildcard_notifier.dart';
import '../features/tools/slideshow/providers/slideshow_notifier.dart';
import '../features/vibe_transfer/providers/vibe_transfer_notifier.dart';
import 'bootstrap.dart';

/// The app's provider graph. [services] are built once in `bootstrap()`;
/// everything here is created lazily by the providers.
List<SingleChildWidget> buildAppProviders(AppServices services) {
  final paths = services.paths;
  final prefs = services.preferences;
  final tagService = services.tagService;
  final wildcardService = services.wildcardService;
  final wikiService = services.wikiService;
  final characterLibraryService = services.characterLibraryService;
  final closetService = services.closetService;
  final audioHandler = services.audioHandler;

  return [
    Provider<PathService>.value(value: paths),
    Provider<PreferencesService>.value(value: prefs),
    ChangeNotifierProvider(create: (_) => ThemeNotifier(prefs)),
    ChangeNotifierProvider(create: (_) => LocaleNotifier(prefs)),
    ChangeNotifierProvider(create: (_) => BackendAuthNotifier()..initialize()),
    ChangeNotifierProxyProvider<BackendAuthNotifier, GalleryNotifier>(
      create: (_) => GalleryNotifier(outputDir: paths.outputDir, prefs: prefs),
      update: (context, auth, gallery) =>
          gallery!..updateBackendUserId(auth.user?.id),
    ),
    ChangeNotifierProvider(
      create: (_) => DirectorRefNotifier()
        ..setDefaults(
          strength: prefs.refLastStrength,
          fidelity: prefs.refLastFidelity,
          prefs: prefs,
        ),
    ),
    ChangeNotifierProvider(create: (_) => VibeTransferNotifier()),
    ChangeNotifierProxyProvider3<
      DirectorRefNotifier,
      VibeTransferNotifier,
      BackendAuthNotifier,
      ReferenceAccessMonitor
    >(
      create: (context) => ReferenceAccessMonitor(
        references: Provider.of<DirectorRefNotifier>(context, listen: false),
        vibes: Provider.of<VibeTransferNotifier>(context, listen: false),
      ),
      update: (context, references, vibes, auth, monitor) =>
          monitor!..update(generationAccessOf(auth).paid),
    ),
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
        library: Provider.of<CharacterLibraryNotifier>(context, listen: false),
        textGen: Provider.of<TextGenNotifier>(context, listen: false),
      ),
      update: (context, library, textGen, previous) =>
          (previous ?? CharacterGenNotifier(library: library, textGen: textGen))
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
      create: (context) {
        final notifier = GenerationNotifier(
          preferences: prefs,
          tagService: tagService,
          wildcardService: wildcardService,
          outputDir: paths.outputDir,
          presetsFilePath: paths.presetsFilePath,
          stylesFilePath: paths.stylesFilePath,
          galleryNotifier: Provider.of<GalleryNotifier>(context, listen: false),
          characterLibrary: Provider.of<CharacterLibraryNotifier>(
            context,
            listen: false,
          ),
        );
        ClientDiagnosticsRuntime.instance.observeGeneration(notifier);
        return notifier;
      },
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
            previous?.updateTextGenNotifier(context.read<TextGenNotifier>());
            previous?.updateBackendUserId(backendAuth.user?.id);
            previous?.updateGatewayAccess(
              backendAuth.rules,
              generationAccessOf(backendAuth),
            );
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
      create: (_) => MLNotifier(mlModelsDir: paths.mlModelsDir, prefs: prefs),
    ),
    ChangeNotifierProvider(create: (_) => CascadeNotifier()),
    ChangeNotifierProvider(create: (_) => Img2ImgNotifier()),
    ChangeNotifierProvider(create: (_) => CanvasNotifier()),
    ChangeNotifierProvider(
      create: (_) => SlideshowNotifier()
        ..loadFromJson(prefs.slideshowConfigs)
        ..setDefaultConfigId(prefs.defaultSlideshowId),
    ),
    ChangeNotifierProvider(
      create: (_) {
        final n = JukeboxNotifier(
          soundfontsDir: paths.soundfontsDir,
          customSongsDir: paths.customSongsDir,
          customSongsJsonPath: paths.customSongsJsonPath,
          prefs: prefs,
        )..initialize();
        audioHandler?.attachNotifier(n);
        return n;
      },
    ),
  ];
}
