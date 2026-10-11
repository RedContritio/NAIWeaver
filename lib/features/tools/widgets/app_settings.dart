import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/gateway/backend_gateway.dart';
import '../../../core/gateway/backend_permissions.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/l10n/locale_notifier.dart';
import '../../../core/services/device_storage.dart';
import '../../../core/services/output_migration_service.dart';
import '../../../core/services/path_service.dart';
import '../../../core/services/preferences_service.dart';
import '../../../core/services/saf_export_service.dart';
import '../../../core/services/update_service.dart';
import '../../../core/services/update_download_service.dart';
import '../../../core/widgets/update_prompt.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/theme_notifier.dart';
import '../../../core/theme/vision_tokens.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/utils/filename_pattern.dart';
import '../../../core/utils/migration_planner.dart';
import '../../../core/utils/nai_filename.dart';
import '../../../core/utils/removable_storage.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/manager_list_tile.dart';
import '../../../core/widgets/pin_lock_gate.dart';
import '../../../core/widgets/section_title.dart';
import '../../../core/widgets/ui/app_panel.dart';
import '../../../core/widgets/ui/app_tabs.dart';
import '../../gallery/providers/gallery_notifier.dart';
import '../../generation/providers/generation_notifier.dart';
import '../tools_hub_screen.dart';
import 'demo_image_picker.dart';
import 'shelf_toggle.dart';
import 'synced_text_field.dart';
import '../../../core/theme/vision_metrics.dart';

class AppSettings extends StatefulWidget {
  const AppSettings({super.key});

  @override
  State<AppSettings> createState() => _AppSettingsState();
}

class _AppSettingsState extends State<AppSettings> {
  late TextEditingController _apiKeyController;
  late TextEditingController _filenamePatternController;
  late TextEditingController _savePathPatternController;
  bool _isObscured = true;
  bool _isCheckingUpdate = false;

  /// App-files dirs on removable volumes (SD cards), e.g.
  /// `/storage/1234-ABCD/Android/data/dev.naiweaver.app/files`.
  /// Empty everywhere except Android with a card inserted.
  List<String> _removableVolumes = const [];

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
    final prefs = context.read<PreferencesService>();
    _filenamePatternController = TextEditingController(
      text: prefs.filenamePattern,
    );
    _savePathPatternController = TextEditingController(
      text: prefs.savePathPattern,
    );
    _loadApiKey();
    _loadRemovableVolumes();
  }

  Future<void> _loadRemovableVolumes() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final dirs = await getExternalStorageDirectories();
      final removable = removableStorageDirs(dirs?.map((d) => d.path).toList());
      if (mounted && removable.isNotEmpty) {
        setState(() => _removableVolumes = removable);
      }
    } catch (_) {
      // No removable storage — the SD quick-pick stays hidden.
    }
  }

  Future<void> _loadApiKey() async {
    if (useBackendGateway) return;
    final prefs = context.read<PreferencesService>();
    final key = await prefs.getApiKey();
    if (mounted) {
      _apiKeyController.text = key;
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _filenamePatternController.dispose();
    _savePathPatternController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<GenerationNotifier>();
    final state = notifier.state;
    final prefs = context.read<PreferencesService>();
    final t = context.t;
    final l = context.l;
    final paidImageFeaturesAllowed = canUsePaidImageFeatures(context);
    // The web gateway has no local gallery, no folder picker and no direct
    // Anlas lookup, so the settings that depend on them are not offered.
    final gateway = useBackendGateway;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(VisionMetrics.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(l.settingsApiSettings.toUpperCase(), t),
          _buildApiKeyField(notifier, t),
          const SizedBox(height: VisionMetrics.space24),
          _buildHeader(l.settingsGeneralSettings.toUpperCase(), t),
          if (!gateway) _buildAutoSaveToggle(notifier, state.autoSaveImages, t),
          if (isDesktopPlatform()) ...[
            const SizedBox(height: VisionMetrics.space12),
            _buildOutputFolderRow(t),
          ],
          if (!kIsWeb) ...[
            const SizedBox(height: VisionMetrics.space12),
            _buildFilenamePatternSection(t),
          ],
          const SizedBox(height: VisionMetrics.space12),
          _buildSmartStyleImportToggle(t),
          const SizedBox(height: VisionMetrics.space12),
          _buildCharInsertTargetToggle(t),
          const SizedBox(height: VisionMetrics.space12),
          _buildRememberSessionToggle(t),
          const SizedBox(height: VisionMetrics.space12),
          _buildImg2ImgImportPromptToggle(t),
          const SizedBox(height: VisionMetrics.space12),
          if (!gateway) ...[
            _buildDefaultSaveAlbumDropdown(t),
            const SizedBox(height: VisionMetrics.space12),
          ],
          _buildLanguageDropdown(t),
          const SizedBox(height: VisionMetrics.space24),
          _buildHeader(l.settingsUiSettings.toUpperCase(), t),
          _buildLayoutModeSelector(t),
          _buildPromptPositionSelector(t),
          _buildSidebarWidthSelector(t),
          const SizedBox(height: VisionMetrics.space12),
          _buildFontScaleSlider(t),
          const SizedBox(height: VisionMetrics.space12),
          if (!gateway) ...[
            _buildAnlasTrackerToggle(t),
            const SizedBox(height: VisionMetrics.space12),
          ],
          _buildSeedControlToggle(t),
          const SizedBox(height: VisionMetrics.space12),
          _buildShowTooltipsToggle(t),
          const SizedBox(height: VisionMetrics.space12),
          _buildHideTagValuesToggle(t),
          const SizedBox(height: VisionMetrics.space12),
          _buildShelfToggle(
            label: l.settingsEditButton.toUpperCase(),
            description: l.settingsEditButtonDesc,
            value: state.showEditButton,
            onChanged: (_) => notifier.toggleShowEditButton(),
            t: t,
          ),
          const SizedBox(height: VisionMetrics.space12),
          _buildShelfToggle(
            label: l.settingsBgRemovalButton.toUpperCase(),
            description: l.settingsBgRemovalButtonDesc,
            value: state.showBgRemovalButton,
            onChanged: (_) => notifier.toggleShowBgRemovalButton(),
            t: t,
          ),
          const SizedBox(height: VisionMetrics.space12),
          _buildShelfToggle(
            label: l.settingsUpscaleButton.toUpperCase(),
            description: l.settingsUpscaleButtonDesc,
            value: state.showUpscaleButton,
            onChanged: (_) => notifier.toggleShowUpscaleButton(),
            t: t,
          ),
          const SizedBox(height: VisionMetrics.space12),
          _buildShelfToggle(
            label: l.settingsEnhanceButton.toUpperCase(),
            description: l.settingsEnhanceButtonDesc,
            value: state.showEnhanceButton,
            onChanged: (_) => notifier.toggleShowEnhanceButton(),
            t: t,
          ),
          const SizedBox(height: VisionMetrics.space12),
          _buildShelfToggle(
            label: l.settingsDirectorToolsButton.toUpperCase(),
            description: l.settingsDirectorToolsButtonDesc,
            value: state.showDirectorToolsButton,
            onChanged: (_) => notifier.toggleShowDirectorToolsButton(),
            t: t,
          ),
          if (!kIsWeb) ...[
            const SizedBox(height: VisionMetrics.space12),
            _buildShelfToggle(
              label: l.settingsCopyButton.toUpperCase(),
              description: l.settingsCopyButtonDesc,
              value: prefs.showCopyButton,
              onChanged: (_) async {
                await prefs.setShowCopyButton(!prefs.showCopyButton);
                setState(() {});
              },
              t: t,
            ),
          ],
          if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) ...[
            const SizedBox(height: VisionMetrics.space12),
            _buildShelfToggle(
              label: l.settingsExportButton.toUpperCase(),
              description: l.settingsExportButtonDesc,
              value: prefs.showExportButton,
              onChanged: (_) async {
                await prefs.setShowExportButton(!prefs.showExportButton);
                setState(() {});
              },
              t: t,
            ),
            const SizedBox(height: VisionMetrics.space12),
            _buildShelfToggle(
              label: l.settingsAutoExport.toUpperCase(),
              description: l.settingsAutoExportDesc,
              value: prefs.autoExportToDevice,
              onChanged: (_) async {
                await prefs.setAutoExportToDevice(!prefs.autoExportToDevice);
                setState(() {});
              },
              t: t,
            ),
            const SizedBox(height: VisionMetrics.space12),
            _buildTextFieldSetting(
              label: l.settingsExportAlbum.toUpperCase(),
              description: l.settingsExportAlbumDesc,
              value: prefs.exportAlbumName,
              onChanged: (value) => prefs.setExportAlbumName(value),
              t: t,
            ),
          ],
          const SizedBox(height: VisionMetrics.space12),
          if (!gateway) ...[
            _buildExportFolderPicker(t),
            const SizedBox(height: VisionMetrics.space12),
          ],
          if (paidImageFeaturesAllowed) ...[
            _buildShelfToggle(
              label: l.settingsDirectorRefShelf.toUpperCase(),
              description: l.settingsDirectorRefShelfDesc,
              value: state.showDirectorRefShelf,
              onChanged: (_) => notifier.toggleDirectorRefShelf(),
              t: t,
            ),
            const SizedBox(height: VisionMetrics.space12),
          ],
          if (paidImageFeaturesAllowed &&
              hasBackendPermission(
                context,
                BackendPermission.imageEncodeVibe,
              )) ...[
            _buildShelfToggle(
              label: l.settingsVibeTransferShelf.toUpperCase(),
              description: l.settingsVibeTransferShelfDesc,
              value: state.showVibeTransferShelf,
              onChanged: (_) => notifier.toggleVibeTransferShelf(),
              t: t,
            ),
            const SizedBox(height: VisionMetrics.space12),
          ],
          _buildCharEditorModeToggle(notifier, state, t),
          const SizedBox(height: VisionMetrics.space12),
          _buildThemeBuilderButton(t),
          const SizedBox(height: VisionMetrics.space24),
          _buildHeader(l.settingsExport.toUpperCase(), t),
          _buildStripMetadataToggle(t),
          const SizedBox(height: VisionMetrics.space24),
          _buildHeader(l.settingsSecurity.toUpperCase(), t),
          _buildPinLockSection(t),
          const SizedBox(height: VisionMetrics.space24),
          if (!gateway) ...[
            _buildHeader(l.settingsDemoMode.toUpperCase(), t),
            _buildDemoModeSection(t),
            const SizedBox(height: VisionMetrics.space24),
          ],
          _buildHeader(l.settingsLinks.toUpperCase(), t),
          _buildGithubButton(t),
          if (!kIsWeb) ...[
            const SizedBox(height: VisionMetrics.space12),
            _buildUpdateCheckButton(t),
          ],
          const SizedBox(height: VisionMetrics.space24),
          _buildHeader(l.settingsCredits.toUpperCase(), t),
          _buildCreditsSection(t),
        ],
      ),
    );
  }

  Widget _buildHeader(String title, VisionTokens t) =>
      SectionTitle(title, t: t);

  Widget _buildApiKeyField(GenerationNotifier notifier, VisionTokens t) {
    final l = context.l;
    if (useBackendGateway) {
      return SizedBox(
        width: double.infinity,
        child: AppPanel(
          variant: AppPanelVariant.raised,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.settingsApiManaged.toUpperCase(),
                style: TextStyle(
                  color: t.headerText,
                  fontSize: t.fontSize(11),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: VisionMetrics.space8),
              Text(
                l.settingsApiManagedDesc,
                style: TextStyle(
                  color: t.textTertiary,
                  fontSize: t.fontSize(9),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.settingsApiKeyLabel.toUpperCase(),
          style: TextStyle(
            color: t.textTertiary,
            fontSize: t.fontSize(9),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: VisionMetrics.space8),
        TextField(
          controller: _apiKeyController,
          obscureText: _isObscured,
          style: TextStyle(
            color: t.headerText,
            fontSize: t.fontSize(12),
            fontFamily: 'monospace',
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: t.borderSubtle,
            hintText: l.settingsApiKeyHint,
            hintStyle: TextStyle(color: t.textDisabled),
            suffixIcon: ManagerIconButton(
              icon: _isObscured ? Icons.visibility_off : Icons.visibility,
              tooltip: l.settingsApiKeyVisibility,
              onPressed: () => setState(() => _isObscured = !_isObscured),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(VisionMetrics.radius4),
              borderSide: BorderSide(color: t.borderMedium),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(VisionMetrics.radius4),
              borderSide: BorderSide(color: t.borderMedium),
            ),
          ),
          onChanged: (val) => notifier.updateApiKey(val),
        ),
      ],
    );
  }

  Widget _buildAutoSaveToggle(
    GenerationNotifier notifier,
    bool value,
    VisionTokens t,
  ) {
    final l = context.l;
    return _buildShelfToggle(
      label: l.settingsAutoSave.toUpperCase(),
      description: l.settingsAutoSaveDesc,
      value: value,
      onChanged: (val) => notifier.toggleAutoSave(val),
      t: t,
    );
  }

  /// Album name a fresh save would land in, for the pattern live preview.
  String _previewAlbumName() {
    final id = context.read<PreferencesService>().defaultSaveAlbumId;
    if (id == null || id.isEmpty) return '';
    for (final album in context.read<GalleryNotifier>().albums) {
      if (album.id == id) return album.name;
    }
    return '';
  }

  /// Custom filename / save-path pattern fields with a live preview of the
  /// resulting name (issue #27). Both empty by default = current behavior.
  Widget _buildFilenamePatternSection(VisionTokens t) {
    final prefs = context.read<PreferencesService>();
    final l = context.l;
    return Builder(
      builder: (context) {
        // Sample values mirror the example from the issue thread.
        final sample = FilenamePatternContext(
          prompt: '1girl, black hair, smile',
          seed: '12345678',
          savedAt: DateTime.now(),
          albumName: _previewAlbumName(),
          sequence: 1234,
        );
        final fnPattern = _filenamePatternController.text;
        var name = fnPattern.isEmpty
            ? ''
            : expandFilenamePattern(fnPattern, sample);
        if (name.isEmpty) name = naiFilenameBase(sample.prompt, sample.seed);
        final sub = expandSavePathPattern(
          _savePathPatternController.text,
          sample,
        );
        final preview = '${sub.isEmpty ? '' : '$sub/'}$name.png';

        Widget field(
          TextEditingController controller,
          String hint,
          Future<void> Function(String) save,
        ) {
          return SizedBox(
            height: 36,
            child: TextField(
              controller: controller,
              style: TextStyle(
                fontSize: t.fontSize(11),
                color: t.textSecondary,
              ),
              decoration: InputDecoration(
                fillColor: t.borderSubtle,
                filled: true,
                hintText: hint,
                hintStyle: TextStyle(
                  fontSize: t.fontSize(11),
                  color: t.textDisabled,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(VisionMetrics.radius4),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: VisionMetrics.space12,
                  vertical: VisionMetrics.space8,
                ),
              ),
              onChanged: (value) {
                save(value.trim());
                setState(() {}); // refresh the live preview
              },
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
            ),
          );
        }

        Widget header(String label, String desc) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: t.headerText,
                fontSize: t.fontSize(11),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: VisionMetrics.space4),
            Text(
              desc,
              style: TextStyle(color: t.textTertiary, fontSize: t.fontSize(9)),
            ),
            const SizedBox(height: VisionMetrics.space8),
          ],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(
              l.settingsFilenamePattern.toUpperCase(),
              l.settingsFilenamePatternDesc,
            ),
            field(
              _filenamePatternController,
              kDefaultFilenamePattern,
              prefs.setFilenamePattern,
            ),
            const SizedBox(height: VisionMetrics.space12),
            header(
              l.settingsSavePathPattern.toUpperCase(),
              l.settingsSavePathPatternDesc,
            ),
            field(
              _savePathPatternController,
              '<year>/<month>/<day>',
              prefs.setSavePathPattern,
            ),
            const SizedBox(height: VisionMetrics.space8),
            Text(
              '${l.settingsPatternPreview.toUpperCase()}: $preview',
              style: TextStyle(
                color: t.textSecondary,
                fontSize: t.fontSize(9),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOutputFolderRow(VisionTokens t) {
    final prefs = context.read<PreferencesService>();
    final l = context.l;
    return Builder(
      builder: (context) {
        final customDir = prefs.customOutputDir;
        final hasCustom = customDir.isNotEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.settingsOutputFolder.toUpperCase(),
              style: TextStyle(
                color: t.headerText,
                fontSize: t.fontSize(11),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: VisionMetrics.space4),
            Text(
              l.settingsOutputFolderDesc,
              style: TextStyle(color: t.textTertiary, fontSize: t.fontSize(9)),
            ),
            const SizedBox(height: VisionMetrics.space8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: VisionMetrics.space12,
                vertical: VisionMetrics.space8,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: t.borderMedium),
                borderRadius: BorderRadius.circular(VisionMetrics.radius4),
                color: t.borderSubtle,
              ),
              child: Text(
                hasCustom ? customDir : l.settingsOutputFolderDefault,
                style: TextStyle(
                  color: hasCustom ? t.headerText : t.textDisabled,
                  fontSize: t.fontSize(10),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: VisionMetrics.space8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SettingsActionButton(
                  label: l.settingsOutputFolderBrowse,
                  onTap: () async {
                    final dir = await FilePicker.platform.getDirectoryPath();
                    if (dir != null && context.mounted) {
                      await _applyOutputDir(dir);
                      setState(() {});
                    }
                  },
                ),
                if (_removableVolumes.isNotEmpty)
                  _SettingsActionButton(
                    label: l.settingsUseSdCard,
                    onTap: _onUseSdCard,
                  ),
                if (hasCustom)
                  _SettingsActionButton(
                    icon: Icons.close,
                    label: l.settingsFolderUseDefault,
                    onTap: () async {
                      await prefs.setCustomOutputDir('');
                      if (!context.mounted) return;
                      final paths = context.read<PathService>();
                      paths.outputDirOverride = null;
                      final defaultDir = paths.outputDir;
                      context.read<GalleryNotifier>().setOutputDir(defaultDir);
                      context.read<GenerationNotifier>().setOutputDir(
                        defaultDir,
                      );
                      setState(() {});
                    },
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// The BROWSE / USE SD CARD shared wiring: persist the custom dir and point
  /// PathService + gallery + generation at it.
  Future<void> _applyOutputDir(String dir) async {
    final prefs = context.read<PreferencesService>();
    await prefs.setCustomOutputDir(dir);
    if (!mounted) return;
    final paths = context.read<PathService>();
    paths.outputDirOverride = dir;
    await paths.ensureDirectories();
    if (!mounted) return;
    context.read<GalleryNotifier>().setOutputDir(dir);
    context.read<GenerationNotifier>().setOutputDir(dir);
  }

  Future<void> _onUseSdCard() async {
    final prefs = context.read<PreferencesService>();
    final paths = context.read<PathService>();
    final l = context.l;
    final t = context.tRead;
    final target = removableOutputDir(_removableVolumes.first);

    // An interrupted move leaves files behind in the previous output dir —
    // offer to resume before anything else.
    final pendingSource = prefs.sdMigrationSource;
    if (pendingSource.isNotEmpty) {
      final remaining = await OutputMigrationService.scanDir(pendingSource);
      if (remaining.isEmpty || pendingSource == paths.outputDir) {
        // Nothing left to move, or the output dir was pointed back at the
        // pending source (e.g. the custom dir was cleared) — a "resume"
        // would be a same-dir move. Drop the pending state and fall through
        // to the normal flow.
        await prefs.setSdMigrationSource('');
      } else {
        if (!mounted) return;
        final resume = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: t.surfaceHigh,
            title: Text(
              l.settingsSdResumeTitle.toUpperCase(),
              style: TextStyle(
                fontSize: t.fontSize(10),
                letterSpacing: 2,
                color: t.textSecondary,
              ),
            ),
            content: Text(
              l.settingsSdResumeBody(remaining.length),
              style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(10)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(
                  l.commonCancel.toUpperCase(),
                  style: TextStyle(
                    color: t.textDisabled,
                    fontSize: t.fontSize(9),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(
                  l.settingsSdResume.toUpperCase(),
                  style: TextStyle(color: t.accent, fontSize: t.fontSize(9)),
                ),
              ),
            ],
          ),
        );
        if (resume != true || !mounted) return;
        final destNow = paths.outputDir;
        final plan = planMigration(
          source: remaining,
          destination: await OutputMigrationService.scanDir(destNow),
        );
        if (!mounted) return;
        await _executeSdMove(
          sourceDir: pendingSource,
          destDir: destNow,
          plan: plan,
          setLocalState: setState,
        );
        return;
      }
    }

    final current = paths.outputDir;
    if (current == target) {
      if (mounted) showAppSnackBar(context, l.settingsSdAlready);
      return;
    }

    final sourceFiles = await OutputMigrationService.scanDir(current);
    final sourceBytes = sourceFiles.fold(0, (sum, f) => sum + f.size);
    if (!mounted) return;
    final choice = await showDialog<_SdChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surfaceHigh,
        title: Text(
          l.settingsSdDialogTitle.toUpperCase(),
          style: TextStyle(
            fontSize: t.fontSize(10),
            letterSpacing: 2,
            color: t.textSecondary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(VisionMetrics.space8),
              decoration: BoxDecoration(
                border: Border.all(
                  color: t.accentDanger.withValues(
                    alpha: VisionMetrics.opacityScrim,
                  ),
                ),
                borderRadius: BorderRadius.circular(VisionMetrics.radius4),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber,
                    size: VisionMetrics.iconMedium,
                    color: t.accentDanger,
                  ),
                  const SizedBox(width: VisionMetrics.space8),
                  Expanded(
                    child: Text(
                      l.settingsSdUninstallWarning,
                      style: TextStyle(
                        color: t.accentDanger,
                        fontSize: t.fontSize(9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (sourceFiles.isNotEmpty) ...[
              const SizedBox(height: VisionMetrics.space12),
              Text(
                l.settingsSdExistingInfo(
                  sourceFiles.length,
                  formatMigrationBytes(sourceBytes),
                ),
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: t.fontSize(10),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              l.commonCancel.toUpperCase(),
              style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(9)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_SdChoice.fresh),
            child: Text(
              l.settingsSdFreshButton.toUpperCase(),
              style: TextStyle(color: t.textSecondary, fontSize: t.fontSize(9)),
            ),
          ),
          if (sourceFiles.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_SdChoice.move),
              child: Text(
                l.settingsSdMoveButton.toUpperCase(),
                style: TextStyle(color: t.accent, fontSize: t.fontSize(9)),
              ),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == _SdChoice.fresh) {
      await _applyOutputDir(target);
      setState(() {});
      return;
    }

    // Rescan the source now that the dialog is closed: anything generated
    // while it was open must ride along instead of being stranded.
    final freshSource = await OutputMigrationService.scanDir(current);
    final destFiles = await OutputMigrationService.scanDir(target);
    final plan = planMigration(source: freshSource, destination: destFiles);
    await Directory(target).create(recursive: true);
    final free = await DeviceStorage.freeBytesAt(target);
    if (free != null && !plan.fitsIn(free)) {
      if (mounted) {
        showErrorSnackBar(
          context,
          l.settingsSdNotEnoughSpace(
            formatMigrationBytes(plan.bytesToCopy + migrationHeadroomBytes),
            formatMigrationBytes(free),
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    // Switch the output dir BEFORE moving: new generations land on the SD
    // card immediately instead of being stranded in the old dir mid-move.
    await _applyOutputDir(target);
    await prefs.setSdMigrationSource(current);
    setState(() {});
    if (!mounted) return;
    await _executeSdMove(
      sourceDir: current,
      destDir: target,
      plan: plan,
      setLocalState: setState,
    );
  }

  Future<void> _executeSdMove({
    required String sourceDir,
    required String destDir,
    required MigrationPlan plan,
    required StateSetter setLocalState,
  }) async {
    final prefs = context.read<PreferencesService>();
    final l = context.l;
    final t = context.tRead;

    final progress = ValueNotifier<(int, int)>((0, plan.totalFiles));
    var cancelRequested = false;

    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: t.surfaceHigh,
          title: Text(
            l.settingsSdDialogTitle.toUpperCase(),
            style: TextStyle(
              fontSize: t.fontSize(10),
              letterSpacing: 2,
              color: t.textSecondary,
            ),
          ),
          content: ValueListenableBuilder<(int, int)>(
            valueListenable: progress,
            builder: (ctx, p, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.settingsSdMoving,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: t.fontSize(10),
                  ),
                ),
                const SizedBox(height: VisionMetrics.space12),
                LinearProgressIndicator(
                  value: p.$2 == 0 ? null : p.$1 / p.$2,
                  color: t.accent,
                  backgroundColor: t.borderSubtle,
                ),
                const SizedBox(height: VisionMetrics.space8),
                Text(
                  '${p.$1} / ${p.$2}',
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: t.fontSize(10),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => cancelRequested = true,
              child: Text(
                l.commonCancel.toUpperCase(),
                style: TextStyle(
                  color: t.textDisabled,
                  fontSize: t.fontSize(9),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    OutputMigrationResult result;
    try {
      result = await OutputMigrationService.run(
        sourceDir: sourceDir,
        destDir: destDir,
        plan: plan,
        onProgress: (done, total) => progress.value = (done, total),
        shouldCancel: () => cancelRequested,
        onSourceFileRemoved: (path) => FileImage(File(path)).evict(),
      );
    } catch (e) {
      // A thrown run (not a per-file failure) must still close the progress
      // dialog and leave the pending-move pref for a retry.
      result = OutputMigrationResult(
        moved: 0,
        failed: plan.totalFiles,
        cancelled: false,
        errors: ['$e'],
      );
    }

    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    await dialogFuture;
    if (!mounted) return;

    if (result.failed > 0) {
      showErrorSnackBar(context, l.settingsSdMoveFailed(result.failed));
    } else if (result.cancelled) {
      showAppSnackBar(
        context,
        l.settingsSdMovePaused(plan.totalFiles - result.moved),
      );
    } else {
      await prefs.setSdMigrationSource('');
      if (mounted) showAppSnackBar(context, l.settingsSdMoveDone(result.moved));
    }
    if (!mounted) return;
    context.read<GalleryNotifier>().refresh();
    setState(() {});
  }

  Widget _buildStripMetadataToggle(VisionTokens t) {
    final prefs = context.read<PreferencesService>();
    final l = context.l;
    return _buildPrefToggle(
      label: l.settingsStripMetadata.toUpperCase(),
      description: l.settingsStripMetadataDesc,
      value: prefs.stripMetadataOnExport,
      save: prefs.setStripMetadataOnExport,
      t: t,
    );
  }

  /// One labelled switch row; every settings toggle goes through here.
  Widget _buildShelfToggle({
    required String label,
    required String description,
    required bool value,
    required ValueChanged<bool>? onChanged,
    required VisionTokens t,
  }) {
    return ShelfToggle(
      label: label,
      description: description,
      value: value,
      onChanged: onChanged,
    );
  }

  /// A toggle backed by a preference: [save] persists the new value, then the
  /// page rebuilds so the switch reads it back.
  Widget _buildPrefToggle({
    required String label,
    required String description,
    required bool value,
    required Future<void> Function(bool) save,
    required VisionTokens t,
  }) {
    return _buildShelfToggle(
      label: label,
      description: description,
      value: value,
      onChanged: (v) async {
        await save(v);
        if (mounted) setState(() {});
      },
      t: t,
    );
  }

  Widget _buildTextFieldSetting({
    required String label,
    required String description,
    required String value,
    required Function(String) onChanged,
    required VisionTokens t,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: t.headerText,
            fontSize: t.fontSize(11),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: VisionMetrics.space4),
        Text(
          description,
          style: TextStyle(color: t.textTertiary, fontSize: t.fontSize(9)),
        ),
        const SizedBox(height: VisionMetrics.space8),
        SyncedTextField(
          value: value,
          style: TextStyle(fontSize: t.fontSize(11), color: t.textSecondary),
          decoration: InputDecoration(
            fillColor: t.borderSubtle,
            filled: true,
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(VisionMetrics.radius4),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: VisionMetrics.space12,
              vertical: VisionMetrics.space12,
            ),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildAnlasTrackerToggle(VisionTokens t) {
    final prefs = context.read<PreferencesService>();
    final l = context.l;
    return _buildPrefToggle(
      label: l.settingsAnlasTracker.toUpperCase(),
      description: l.settingsAnlasTrackerDesc,
      value: prefs.showAnlasTracker,
      save: prefs.setShowAnlasTracker,
      t: t,
    );
  }

  /// Human-readable label for the stored export folder. SAF tree URIs are
  /// ugly (`content://…/tree/XXXX-XXXX%3ANAIWeaver`), so show the decoded
  /// trailing folder segment; plain filesystem paths are shown as-is.
  String _exportFolderLabel(String path) {
    if (!SafExportService.isSafUri(path)) return path;
    final decoded = Uri.decodeComponent(path);
    final lastColon = decoded.lastIndexOf(':');
    final tail = lastColon >= 0 ? decoded.substring(lastColon + 1) : decoded;
    return tail.isEmpty ? 'SD CARD' : 'SD: $tail';
  }

  Widget _buildExportFolderPicker(VisionTokens t) {
    final prefs = context.read<PreferencesService>();
    final l = context.l;
    return Builder(
      builder: (context) {
        final currentPath = prefs.exportFolderPath;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.settingsExportFolder.toUpperCase(),
              style: TextStyle(
                color: t.headerText,
                fontSize: t.fontSize(11),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: VisionMetrics.space4),
            Text(
              l.settingsExportFolderDesc,
              style: TextStyle(color: t.textTertiary, fontSize: t.fontSize(9)),
            ),
            const SizedBox(height: VisionMetrics.space8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: VisionMetrics.space12,
                      vertical: VisionMetrics.space8,
                    ),
                    decoration: BoxDecoration(
                      color: t.borderSubtle,
                      borderRadius: BorderRadius.circular(
                        VisionMetrics.radius4,
                      ),
                    ),
                    child: Text(
                      currentPath.isEmpty
                          ? l.settingsExportFolderDefault
                          : _exportFolderLabel(currentPath),
                      style: TextStyle(
                        fontSize: t.fontSize(9),
                        color: currentPath.isEmpty
                            ? t.textDisabled
                            : t.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: VisionMetrics.space8),
                ManagerIconButton(
                  icon: Icons.folder_open,
                  color: t.accent,
                  tooltip: l.settingsOutputFolderBrowse,
                  onPressed: () async {
                    // On Android, pick via SAF so the chosen folder can live on
                    // a removable SD card (plain filesystem writes can't reach
                    // it under scoped storage — issue #13).
                    if (SafExportService.isSupported) {
                      final folder = await SafExportService.instance
                          .pickFolder();
                      if (folder != null) {
                        await prefs.setExportFolderPath(folder.uri);
                        setState(() {});
                      }
                      return;
                    }
                    final dir = await FilePicker.platform.getDirectoryPath(
                      dialogTitle: l.settingsExportFolder,
                    );
                    if (dir != null) {
                      await prefs.setExportFolderPath(dir);
                      setState(() {});
                    }
                  },
                ),
                if (currentPath.isNotEmpty)
                  ManagerIconButton(
                    icon: Icons.close,
                    tooltip: l.settingsFolderUseDefault,
                    onPressed: () async {
                      await prefs.setExportFolderPath('');
                      setState(() {});
                    },
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildSeedControlToggle(VisionTokens t) {
    final prefs = context.read<PreferencesService>();
    final l = context.l;
    return _buildPrefToggle(
      label: l.settingsSeedControl.toUpperCase(),
      description: l.settingsSeedControlDesc,
      value: prefs.showSeedControl,
      save: prefs.setShowSeedControl,
      t: t,
    );
  }

  Widget _buildFontScaleSlider(VisionTokens t) {
    final themeNotifier = context.watch<ThemeNotifier>();
    final scale = themeNotifier.activeConfig.fontScale;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l.settingsFontSize.toUpperCase(),
                style: TextStyle(
                  color: t.headerText,
                  fontSize: t.fontSize(11),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: VisionMetrics.space4),
              Text(
                context.l.settingsFontSizeDesc,
                style: TextStyle(
                  color: t.textTertiary,
                  fontSize: t.fontSize(9),
                ),
              ),
              const SizedBox(height: VisionMetrics.space4),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: t.accent,
                  inactiveTrackColor: t.borderSubtle,
                  thumbColor: t.accent,
                  overlayColor: t.accent.withValues(
                    alpha: VisionMetrics.opacityPressed,
                  ),
                  trackHeight: 2,
                ),
                child: Slider(
                  min: 0.85,
                  max: 1.40,
                  divisions: 11, // 0.05 increments
                  value: scale.clamp(0.85, 1.40),
                  onChanged: (v) => themeNotifier.setFontScale(v),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: VisionMetrics.space12),
        SizedBox(
          width: 56,
          child: Text(
            '${(scale * 100).round()}%',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: t.fontSize(11),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShowTooltipsToggle(VisionTokens t) {
    final prefs = context.read<PreferencesService>();
    final l = context.l;
    return _buildPrefToggle(
      label: l.settingsShowTooltips.toUpperCase(),
      description: l.settingsShowTooltipsDesc,
      value: prefs.showTooltips,
      save: prefs.setShowTooltips,
      t: t,
    );
  }

  Widget _buildHideTagValuesToggle(VisionTokens t) {
    final prefs = context.read<PreferencesService>();
    final l = context.l;
    return _buildPrefToggle(
      label: l.settingsHideTagValues.toUpperCase(),
      description: l.settingsHideTagValuesDesc,
      value: prefs.hideTagValues,
      save: prefs.setHideTagValues,
      t: t,
    );
  }

  Widget _buildCharEditorModeToggle(
    GenerationNotifier notifier,
    GenerationState state,
    VisionTokens t,
  ) {
    final l = context.l;
    return _buildShelfToggle(
      label: l.settingsCharEditorMode.toUpperCase(),
      description: l.settingsCharEditorModeDesc,
      value: state.characterEditorMode == 'expanded',
      onChanged: (_) {
        final newMode = state.characterEditorMode == 'expanded'
            ? 'compact'
            : 'expanded';
        notifier.setCharacterEditorMode(newMode);
      },
      t: t,
    );
  }

  Widget _buildLayoutModeSelector(VisionTokens t) {
    final themeNotifier = context.watch<ThemeNotifier>();
    final l = context.l;
    final current = themeNotifier.sidebarLayoutMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.settingsLayoutMode.toUpperCase(),
          style: TextStyle(
            color: t.headerText,
            fontSize: t.fontSize(11),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: VisionMetrics.space4),
        Text(
          l.settingsLayoutModeDesc,
          style: TextStyle(color: t.textTertiary, fontSize: t.fontSize(9)),
        ),
        const SizedBox(height: VisionMetrics.space8),
        AppSegmented<String>(
          options: [
            AppOption(value: 'auto', label: l.settingsLayoutAuto),
            AppOption(value: 'always', label: l.settingsLayoutSidebar),
            AppOption(value: 'never', label: l.settingsLayoutClassic),
          ],
          selected: current,
          onChanged: themeNotifier.setSidebarLayoutMode,
        ),
      ],
    );
  }

  Widget _buildSidebarWidthSelector(VisionTokens t) {
    final themeNotifier = context.watch<ThemeNotifier>();
    final l = context.l;
    final current = themeNotifier.sidebarWidthMode;
    final layoutMode = themeNotifier.sidebarLayoutMode;
    if (layoutMode == 'never') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: VisionMetrics.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.settingsSidebarWidth.toUpperCase(),
            style: TextStyle(
              color: t.headerText,
              fontSize: t.fontSize(11),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: VisionMetrics.space4),
          Text(
            l.settingsSidebarWidthDesc,
            style: TextStyle(color: t.textTertiary, fontSize: t.fontSize(9)),
          ),
          const SizedBox(height: VisionMetrics.space8),
          AppSegmented<String>(
            options: [
              AppOption(value: 'compact', label: l.settingsSidebarCompact),
              AppOption(value: 'normal', label: l.settingsSidebarNormal),
            ],
            selected: current,
            onChanged: themeNotifier.setSidebarWidthMode,
          ),
        ],
      ),
    );
  }

  Widget _buildPromptPositionSelector(VisionTokens t) {
    final themeNotifier = context.watch<ThemeNotifier>();
    final l = context.l;
    final current = themeNotifier.sidebarPromptPosition;
    final layoutMode = themeNotifier.sidebarLayoutMode;
    // Only show when sidebar mode is possible
    if (layoutMode == 'never') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: VisionMetrics.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.settingsPromptPosition.toUpperCase(),
            style: TextStyle(
              color: t.headerText,
              fontSize: t.fontSize(11),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: VisionMetrics.space4),
          Text(
            l.settingsPromptPositionDesc,
            style: TextStyle(color: t.textTertiary, fontSize: t.fontSize(9)),
          ),
          const SizedBox(height: VisionMetrics.space8),
          AppSegmented<String>(
            options: [
              AppOption(value: 'left', label: l.settingsPromptLeft),
              AppOption(value: 'right', label: l.settingsPromptRight),
            ],
            selected: current,
            onChanged: themeNotifier.setSidebarPromptPosition,
          ),
        ],
      ),
    );
  }

  Widget _buildSmartStyleImportToggle(VisionTokens t) {
    final prefs = context.read<PreferencesService>();
    final l = context.l;
    return _buildPrefToggle(
      label: l.settingsSmartStyleImport.toUpperCase(),
      description: l.settingsSmartStyleImportDesc,
      value: prefs.smartStyleImport,
      save: prefs.setSmartStyleImport,
      t: t,
    );
  }

  Widget _buildCharInsertTargetToggle(VisionTokens t) {
    final prefs = context.read<PreferencesService>();
    final l = context.l;
    return _buildPrefToggle(
      label: l.settingsCharInsertTarget.toUpperCase(),
      description: l.settingsCharInsertTargetDesc,
      value: prefs.charInsertTarget == 'editor',
      save: (val) => prefs.setCharInsertTarget(val ? 'editor' : 'main'),
      t: t,
    );
  }

  Widget _buildRememberSessionToggle(VisionTokens t) {
    final prefs = context.read<PreferencesService>();
    final l = context.l;
    return _buildPrefToggle(
      label: l.settingsRememberSession.toUpperCase(),
      description: l.settingsRememberSessionDesc,
      value: prefs.rememberSession,
      save: (val) async {
        final gen = context.read<GenerationNotifier>();
        await prefs.setRememberSession(val);
        if (!val) gen.deleteSessionSnapshot();
      },
      t: t,
    );
  }

  Widget _buildImg2ImgImportPromptToggle(VisionTokens t) {
    final prefs = context.read<PreferencesService>();
    final l = context.l;
    return _buildPrefToggle(
      label: l.settingsImg2ImgImportPrompt.toUpperCase(),
      description: l.settingsImg2ImgImportPromptDesc,
      value: prefs.img2imgImportPrompt,
      save: prefs.setImg2ImgImportPrompt,
      t: t,
    );
  }

  Widget _buildDefaultSaveAlbumDropdown(VisionTokens t) {
    final prefs = context.read<PreferencesService>();
    final gallery = context.watch<GalleryNotifier>();
    final l = context.l;
    return Builder(
      builder: (context) {
        final currentId = prefs.defaultSaveAlbumId;
        final albums = gallery.albums;
        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.settingsSaveToAlbum.toUpperCase(),
                    style: TextStyle(
                      color: t.headerText,
                      fontSize: t.fontSize(11),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: VisionMetrics.space4),
                  Text(
                    l.settingsSaveToAlbumDesc,
                    style: TextStyle(
                      color: t.textTertiary,
                      fontSize: t.fontSize(9),
                    ),
                  ),
                ],
              ),
            ),
            DropdownButton<String>(
              value: currentId != null && albums.any((a) => a.id == currentId)
                  ? currentId
                  : null,
              hint: Text(
                l.commonNone.toUpperCase(),
                style: TextStyle(
                  color: t.textDisabled,
                  fontSize: t.fontSize(10),
                ),
              ),
              dropdownColor: t.surfaceHigh,
              underline: const SizedBox.shrink(),
              style: TextStyle(
                color: t.textSecondary,
                fontSize: t.fontSize(10),
                letterSpacing: 1,
              ),
              items: [
                DropdownMenuItem<String>(
                  value: null,
                  child: Text(
                    l.commonNone.toUpperCase(),
                    style: TextStyle(
                      color: t.textDisabled,
                      fontSize: t.fontSize(10),
                    ),
                  ),
                ),
                for (final album in albums)
                  DropdownMenuItem<String>(
                    value: album.id,
                    child: Text(
                      album.name.toUpperCase(),
                      style: TextStyle(fontSize: t.fontSize(10)),
                    ),
                  ),
              ],
              onChanged: (val) async {
                await prefs.setDefaultSaveAlbumId(val);
                setState(() {});
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildLanguageDropdown(VisionTokens t) {
    final localeNotifier = context.watch<LocaleNotifier>();
    final l = context.l;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.settingsLanguage.toUpperCase(),
                style: TextStyle(
                  color: t.headerText,
                  fontSize: t.fontSize(11),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        DropdownButton<Locale>(
          value: localeNotifier.locale,
          dropdownColor: t.surfaceHigh,
          underline: const SizedBox.shrink(),
          style: TextStyle(
            color: t.textSecondary,
            fontSize: t.fontSize(10),
            letterSpacing: 1,
          ),
          items: const [
            DropdownMenuItem(value: Locale('en'), child: Text('ENGLISH')),
            DropdownMenuItem(value: Locale('ja'), child: Text('日本語')),
            DropdownMenuItem(value: Locale('zh'), child: Text('中文 (简体)')),
          ],
          onChanged: (locale) {
            if (locale != null) {
              localeNotifier.setLocale(locale);
            }
          },
        ),
      ],
    );
  }

  Widget _buildThemeBuilderButton(VisionTokens t) {
    final l = context.l;
    return _SettingsActionButton(
      icon: Icons.palette,
      label: l.settingsThemeBuilder,
      onTap: () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const ToolsHubScreen(initialToolId: 'theme'),
          ),
        );
      },
    );
  }

  Widget _buildPinLockSection(VisionTokens t) {
    final prefs = context.read<PreferencesService>();
    final l = context.l;
    return Builder(
      builder: (context) {
        final pinEnabled = prefs.pinEnabled;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildShelfToggle(
              label: l.settingsPinLock.toUpperCase(),
              description: l.settingsPinLockDesc,
              value: pinEnabled,
              onChanged: (_) async {
                if (!pinEnabled) {
                  final result = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => _SetPinDialog(t: t),
                  );
                  if (result == true) {
                    setState(() {});
                  }
                } else {
                  final result = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => _VerifyPinDialog(prefs: prefs, t: t),
                  );
                  if (result == true) {
                    await prefs.setPinEnabled(false);
                    await prefs.setPinHash('');
                    await prefs.setPinSalt('');
                    await prefs.setPinLockOnResume(false);
                    await prefs.setPinBiometricEnabled(false);
                    setState(() {});
                  }
                }
              },
              t: t,
            ),
            if (pinEnabled) ...[
              const SizedBox(height: VisionMetrics.space12),
              _buildShelfToggle(
                label: l.settingsLockOnResume.toUpperCase(),
                description: l.settingsLockOnResumeDesc,
                value: prefs.pinLockOnResume,
                onChanged: (_) async {
                  await prefs.setPinLockOnResume(!prefs.pinLockOnResume);
                  setState(() {});
                },
                t: t,
              ),
              const SizedBox(height: VisionMetrics.space12),
              _buildShelfToggle(
                label: l.settingsBiometricUnlock.toUpperCase(),
                description: l.settingsBiometricUnlockDesc,
                value: prefs.pinBiometricEnabled,
                onChanged: (_) async {
                  if (!prefs.pinBiometricEnabled) {
                    final auth = LocalAuthentication();
                    final canCheck =
                        await auth.canCheckBiometrics ||
                        await auth.isDeviceSupported();
                    if (!canCheck) {
                      if (context.mounted) {
                        showErrorSnackBar(
                          context,
                          l.settingsBiometricsUnavailable,
                        );
                      }
                      return;
                    }
                    // Verify biometrics are actually enrolled
                    final available = await auth.getAvailableBiometrics();
                    if (available.isEmpty) {
                      if (context.mounted) {
                        showErrorSnackBar(
                          context,
                          l.settingsBiometricsUnavailable,
                        );
                      }
                      return;
                    }
                  }
                  await prefs.setPinBiometricEnabled(
                    !prefs.pinBiometricEnabled,
                  );
                  setState(() {});
                },
                t: t,
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildDemoModeSection(VisionTokens t) {
    final gallery = context.watch<GalleryNotifier>();
    final prefs = context.read<PreferencesService>();
    final l = context.l;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildShelfToggle(
                label: l.settingsDemoMode.toUpperCase(),
                description: l.settingsDemoModeDesc,
                value: gallery.demoMode,
                onChanged: (_) {
                  gallery.demoMode = !gallery.demoMode;
                },
                t: t,
              ),
            ),
            ManagerIconButton(
              icon: Icons.settings,
              onPressed: () => _showDemoPrefixSettings(prefs, t),
              tooltip: l.settingsEditPositivePrefix,
            ),
          ],
        ),
        const SizedBox(height: VisionMetrics.space12),
        _SettingsActionButton(
          icon: Icons.photo_library,
          label: l.settingsSelectDemoImages,
          trailing: '(${gallery.demoSafeCount})',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const DemoImagePicker()),
            );
          },
        ),
        const SizedBox(height: VisionMetrics.space16),
        Text(
          l.settingsTagSuggestionsHidden,
          style: TextStyle(
            color: t.textTertiary,
            fontSize: t.fontSize(9),
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Future<void> _showDemoPrefixSettings(
    PreferencesService prefs,
    VisionTokens t,
  ) async {
    final posCtrl = TextEditingController(text: prefs.demoPositivePrefix);
    final negCtrl = TextEditingController(text: prefs.demoNegativePrefix);
    final l = context.l;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surfaceHigh,
        title: Text(
          l.settingsDemoPrefixes.toUpperCase(),
          style: TextStyle(
            fontSize: t.fontSize(10),
            letterSpacing: 2,
            color: t.textSecondary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.settingsPositivePrefix.toUpperCase(),
              style: TextStyle(
                color: t.textTertiary,
                fontSize: t.fontSize(9),
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: VisionMetrics.space8),
            TextField(
              controller: posCtrl,
              autofocus: true,
              style: TextStyle(color: t.headerText, fontSize: t.fontSize(11)),
              decoration: InputDecoration(
                filled: true,
                fillColor: t.borderSubtle,
                hintStyle: TextStyle(color: t.textDisabled),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(VisionMetrics.radius4),
                  borderSide: BorderSide(color: t.borderMedium),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(VisionMetrics.radius4),
                  borderSide: BorderSide(color: t.borderMedium),
                ),
              ),
            ),
            const SizedBox(height: VisionMetrics.space16),
            Text(
              l.settingsNegativePrefix.toUpperCase(),
              style: TextStyle(
                color: t.textTertiary,
                fontSize: t.fontSize(9),
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: VisionMetrics.space8),
            TextField(
              controller: negCtrl,
              style: TextStyle(color: t.headerText, fontSize: t.fontSize(11)),
              decoration: InputDecoration(
                filled: true,
                fillColor: t.borderSubtle,
                hintStyle: TextStyle(color: t.textDisabled),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(VisionMetrics.radius4),
                  borderSide: BorderSide(color: t.borderMedium),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(VisionMetrics.radius4),
                  borderSide: BorderSide(color: t.borderMedium),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              ctx.l.commonCancel.toUpperCase(),
              style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(9)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              ctx.l.commonSave.toUpperCase(),
              style: TextStyle(color: t.accent, fontSize: t.fontSize(9)),
            ),
          ),
        ],
      ),
    );

    if (saved == true) {
      await prefs.setDemoPositivePrefix(posCtrl.text);
      await prefs.setDemoNegativePrefix(negCtrl.text);
      setState(() {});
    }
    posCtrl.dispose();
    negCtrl.dispose();
  }

  Widget _buildCreditsSection(VisionTokens t) {
    final l = context.l;
    const names = [
      'Brudda',
      'Uragan',
      'Glockamoli',
      'Perry Argoneco',
      'Deadly Ham',
      'baisumang',
      'andreiagmu',
    ];
    const linkedNames = {'andreiagmu': 'https://github.com/andreiagmu'};
    return SizedBox(
      width: double.infinity,
      child: AppPanel(
        variant: AppPanelVariant.raised,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.settingsSpecialThanks.toUpperCase(),
              style: TextStyle(
                color: t.secondaryText,
                fontSize: t.fontSize(10),
                letterSpacing: 2,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: VisionMetrics.space8),
            for (final name in names)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: linkedNames.containsKey(name)
                    ? InkWell(
                        onTap: () =>
                            _confirmOpenExternalLink(t, linkedNames[name]!),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: context.hitSize,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              name,
                              style: TextStyle(
                                color: t.accent,
                                fontSize: t.fontSize(11),
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      )
                    : Text(
                        name,
                        style: TextStyle(
                          color: t.headerText,
                          fontSize: t.fontSize(11),
                        ),
                      ),
              ),
            const SizedBox(height: VisionMetrics.space8),
            Text(
              l.settingsAnonTesters,
              style: TextStyle(
                color: t.textTertiary,
                fontSize: t.fontSize(10),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGithubButton(VisionTokens t) {
    final l = context.l;
    return _SettingsActionButton(
      icon: Icons.code,
      label: l.settingsGithubRepository,
      onTap: () {
        launchUrl(
          Uri.parse('https://github.com/ststoryweaver/NAIWeaver'),
          mode: LaunchMode.externalApplication,
        );
      },
    );
  }

  Widget _buildUpdateCheckButton(VisionTokens t) {
    final l = context.l;
    return _SettingsActionButton(
      icon: Icons.system_update,
      busy: _isCheckingUpdate,
      label: l.settingsCheckForUpdates,
      onTap: _isCheckingUpdate
          ? null
          : () async {
              setState(() => _isCheckingUpdate = true);
              try {
                final packageInfo = await PackageInfo.fromPlatform();
                final result = await UpdateService.checkForUpdate(
                  packageInfo.version,
                );

                if (!mounted) return;

                if (result.error != null) {
                  showErrorSnackBar(context, l.settingsUpdateCheckFailed);
                } else if (result.updateAvailable) {
                  _showUpdateDialog(t, result);
                } else {
                  showAppSnackBar(context, l.settingsUpToDate);
                }
              } finally {
                if (mounted) setState(() => _isCheckingUpdate = false);
              }
            },
    );
  }

  void _confirmOpenExternalLink(VisionTokens t, String url) {
    final l = context.l;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surfaceHigh,
        title: Text(
          l.settingsOpenLinkTitle.toUpperCase(),
          style: TextStyle(
            fontSize: t.fontSize(10),
            letterSpacing: 2,
            color: t.textSecondary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.settingsOpenLinkBody,
              style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(11)),
            ),
            const SizedBox(height: VisionMetrics.space8),
            Text(
              url,
              style: TextStyle(color: t.accent, fontSize: t.fontSize(11)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              l.commonCancel.toUpperCase(),
              style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(9)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            },
            child: Text(
              l.settingsOpenLinkConfirm.toUpperCase(),
              style: TextStyle(color: t.accent, fontSize: t.fontSize(9)),
            ),
          ),
        ],
      ),
    );
  }

  void _showUpdateDialog(VisionTokens t, UpdateCheckResult result) {
    final l = context.l;
    // On platforms that can auto-apply (Android/Windows) the action downloads &
    // installs in-app; elsewhere it falls back to opening the release page.
    final canApply = UpdateDownloadService.isSupported;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surfaceHigh,
        title: Text(
          l.settingsUpdateAvailable.toUpperCase(),
          style: TextStyle(
            fontSize: t.fontSize(10),
            letterSpacing: 2,
            color: t.textSecondary,
          ),
        ),
        content: Text(
          l.settingsUpdateAvailableDesc(result.latestVersion ?? ''),
          style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(11)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              l.commonClose.toUpperCase(),
              style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(9)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              startUpdate(context, result);
            },
            child: Text(
              (canApply ? l.settingsUpdateApply : l.settingsUpdateDownload)
                  .toUpperCase(),
              style: TextStyle(color: t.accent, fontSize: t.fontSize(9)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SetPinDialog extends StatefulWidget {
  final VisionTokens t;
  const _SetPinDialog({required this.t});

  @override
  State<_SetPinDialog> createState() => _SetPinDialogState();
}

class _SetPinDialogState extends State<_SetPinDialog> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final l = context.l;
    return AlertDialog(
      backgroundColor: t.surfaceHigh,
      title: Text(
        l.settingsSetPin.toUpperCase(),
        style: TextStyle(
          fontSize: t.fontSize(10),
          letterSpacing: 2,
          color: t.textSecondary,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _pinController,
            obscureText: true,
            maxLength: 8,
            keyboardType: TextInputType.number,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: t.fontSize(16),
              letterSpacing: 8,
            ),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: l.settingsPinDigitsHint,
              hintStyle: TextStyle(
                color: t.textDisabled,
                fontSize: t.fontSize(9),
                letterSpacing: 2,
              ),
              counterText: '',
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: t.borderMedium),
              ),
            ),
          ),
          const SizedBox(height: VisionMetrics.space16),
          TextField(
            controller: _confirmController,
            obscureText: true,
            maxLength: 8,
            keyboardType: TextInputType.number,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: t.fontSize(16),
              letterSpacing: 8,
            ),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: l.commonConfirm.toUpperCase(),
              hintStyle: TextStyle(
                color: t.textDisabled,
                fontSize: t.fontSize(9),
                letterSpacing: 2,
              ),
              counterText: '',
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: t.borderMedium),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: VisionMetrics.space12),
            Text(
              _error!,
              style: TextStyle(color: t.accentDanger, fontSize: t.fontSize(9)),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            l.commonCancel.toUpperCase(),
            style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(9)),
          ),
        ),
        TextButton(
          onPressed: () async {
            final pin = _pinController.text;
            final confirm = _confirmController.text;
            if (pin.length < 4 ||
                pin.length > 8 ||
                !RegExp(r'^\d{4,8}$').hasMatch(pin)) {
              setState(() => _error = l.settingsPinMustBeDigits);
              return;
            }
            if (pin != confirm) {
              setState(() => _error = l.settingsPinsDoNotMatch);
              return;
            }
            final prefs = context.read<PreferencesService>();
            final salt = generateSalt();
            final hash = hashPinPbkdf2(salt, pin);
            await prefs.setPinSalt(salt);
            await prefs.setPinHash(hash);
            await prefs.setPinHashVersion(2);
            await prefs.setPinEnabled(true);
            if (context.mounted) Navigator.pop(context, true);
          },
          child: Text(
            l.commonSet.toUpperCase(),
            style: TextStyle(color: t.accent, fontSize: t.fontSize(9)),
          ),
        ),
      ],
    );
  }
}

class _VerifyPinDialog extends StatefulWidget {
  final PreferencesService prefs;
  final VisionTokens t;
  const _VerifyPinDialog({required this.prefs, required this.t});

  @override
  State<_VerifyPinDialog> createState() => _VerifyPinDialogState();
}

class _VerifyPinDialogState extends State<_VerifyPinDialog> {
  final _pinController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final l = context.l;
    return AlertDialog(
      backgroundColor: t.surfaceHigh,
      title: Text(
        l.settingsEnterCurrentPin.toUpperCase(),
        style: TextStyle(
          fontSize: t.fontSize(10),
          letterSpacing: 2,
          color: t.textSecondary,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _pinController,
            obscureText: true,
            maxLength: 8,
            keyboardType: TextInputType.number,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: t.fontSize(16),
              letterSpacing: 8,
            ),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: l.settingsEnterPinHint.toUpperCase(),
              hintStyle: TextStyle(
                color: t.textDisabled,
                fontSize: t.fontSize(9),
                letterSpacing: 2,
              ),
              counterText: '',
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: t.borderMedium),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: VisionMetrics.space12),
            Text(
              _error!,
              style: TextStyle(color: t.accentDanger, fontSize: t.fontSize(9)),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            l.commonCancel.toUpperCase(),
            style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(9)),
          ),
        ),
        TextButton(
          onPressed: () {
            final pin = _pinController.text;
            final expectedHash = widget.prefs.pinHash;
            final salt = widget.prefs.pinSalt;
            final enteredHash = verifyPinHash(
              salt,
              pin,
              widget.prefs.pinHashVersion,
            );
            if (enteredHash == expectedHash) {
              Navigator.pop(context, true);
            } else {
              setState(() => _error = l.settingsIncorrectPin);
            }
          },
          child: Text(
            l.commonConfirm.toUpperCase(),
            style: TextStyle(color: t.accentDanger, fontSize: t.fontSize(9)),
          ),
        ),
      ],
    );
  }
}

/// Outcome of the USE SD CARD choice dialog.
enum _SdChoice { move, fresh }

/// Outlined action row used for links and one-off actions in the settings
/// list. A null [onTap] renders the disabled look.
class _SettingsActionButton extends StatelessWidget {
  const _SettingsActionButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.trailing,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final String? trailing;

  /// Shows a spinner in place of [icon] and dims the button.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final enabled = onTap != null && !busy;
    return Opacity(
      opacity: enabled || busy ? 1 : VisionMetrics.opacityDisabled,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(VisionMetrics.radius4),
        child: Container(
          constraints: BoxConstraints(minHeight: context.hitSize),
          padding: const EdgeInsets.symmetric(
            horizontal: VisionMetrics.space16,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: t.borderMedium),
            borderRadius: BorderRadius.circular(VisionMetrics.radius4),
            color: t.borderSubtle,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox(
                  width: VisionMetrics.iconMedium,
                  height: VisionMetrics.iconMedium,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: t.secondaryText,
                  ),
                )
              else if (icon != null)
                Icon(
                  icon,
                  color: t.secondaryText,
                  size: VisionMetrics.iconMedium,
                ),
              if (busy || icon != null)
                const SizedBox(width: VisionMetrics.space12),
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: t.secondaryText,
                    fontSize: t.fontSize(10),
                    letterSpacing: 1,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: VisionMetrics.space8),
                Text(
                  trailing!,
                  style: TextStyle(
                    color: t.textDisabled,
                    fontSize: t.fontSize(9),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
