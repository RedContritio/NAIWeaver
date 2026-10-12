import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'app/bootstrap.dart';
import 'core/gateway/backend_gateway.dart';
import 'core/gateway/backend_permissions.dart';
import 'core/l10n/l10n_extensions.dart';
import 'core/services/backend_history_api.dart';
import 'core/services/preferences_service.dart';
import 'core/services/tag_service.dart';
import 'core/services/update_service.dart';
import 'core/theme/theme_extensions.dart';
import 'core/theme/theme_notifier.dart';
import 'core/theme/vision_metrics.dart';
import 'core/utils/app_snackbar.dart';
import 'core/utils/responsive.dart';
import 'core/widgets/confirm_dialog.dart';
import 'core/widgets/help_dialog.dart';
import 'core/widgets/syntax_highlight_controller.dart';
import 'core/widgets/text_input_dialog.dart';
import 'core/widgets/ui/app_tone.dart';
import 'core/widgets/update_prompt.dart';
import 'features/auth/backend_auth_notifier.dart';
import 'features/director_ref/providers/director_ref_notifier.dart';
import 'features/gallery/ui/gallery_screen.dart';
import 'features/generation/providers/generation_notifier.dart';
import 'features/generation/services/reference_access_monitor.dart';
import 'features/generation/widgets/billing_text.dart';
import 'features/generation/widgets/character_shelf.dart';
import 'features/generation/widgets/generation_app_bar.dart';
import 'features/generation/widgets/generation_mobile_sheet.dart';
import 'features/generation/widgets/generation_page_layout.dart';
import 'features/generation/widgets/generation_results_workspace.dart';
import 'features/generation/widgets/generation_seed_control.dart';
import 'features/generation/widgets/generation_status.dart';
import 'features/generation/widgets/prompt_composer.dart';
import 'features/generation/widgets/prompt_shortcuts.dart';
import 'features/generation/widgets/quote_confirm_dialog.dart';
import 'features/generation/widgets/settings_panel.dart';
import 'features/history/server_history_screen.dart';
import 'features/tools/cascade/providers/cascade_notifier.dart';
import 'features/tools/cascade/widgets/cascade_playback_view.dart';
import 'features/tools/tools_hub_screen.dart';
import 'features/vibe_transfer/providers/vibe_transfer_notifier.dart';

void main() => runNaiWeaver(home: const SimpleGeneratorApp());

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
  ReferenceAccessMonitor? _accessMonitor;
  final GlobalKey<PromptComposerState> _composerKey =
      GlobalKey<PromptComposerState>(debugLabel: 'main-prompt-composer');
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
      _accessMonitor = context.read<ReferenceAccessMonitor>()
        ..addListener(_onReferenceAccessChanged);
      _onGenerationStateChanged(notifier);
      _maybeCheckForUpdate();
    });
  }

  @override
  void dispose() {
    _listenedGenerationNotifier?.removeListener(_generationListener);
    _accessMonitor?.removeListener(_onReferenceAccessChanged);
    _pulseController.dispose();
    super.dispose();
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

    // Control pulse animation
    if (state.isLoading) {
      if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
    } else {
      if (_pulseController.isAnimating) _pulseController.stop();
    }

    if (state.hasAuthError) {
      _showAuthError();
      notifier.clearAuthError();
    }

    if (state.errorMessage != null) {
      _showError(
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

    if (state.duplicateImageDetected) {
      final warning = AppTone.warning.color(context.tRead);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      showAppSnackBar(
        context,
        context.l.duplicateImageWarning.toUpperCase(),
        tone: AppTone.warning,
        action: SnackBarAction(
          label: context.l.duplicateImageRandomize.toUpperCase(),
          textColor: warning,
          onPressed: () => notifier.updateSettings(randomizeSeed: true),
        ),
      );
      notifier.clearDuplicateWarning();
    }
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

  /// A failed generation. [tone] comes from the structured gateway error (the
  /// point kind of a points shortage), never from the message text: a
  /// shortage of free points is a warning, everything else an error.
  void _showError(
    String message, {
    GenerationErrorTone tone = GenerationErrorTone.general,
    VoidCallback? onRandomizeSeed,
  }) {
    final appTone = switch (tone) {
      GenerationErrorTone.greenPoints => AppTone.warning,
      GenerationErrorTone.redPoints ||
      GenerationErrorTone.general => AppTone.error,
    };
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    showAppSnackBar(
      context,
      message,
      tone: appTone,
      action: onRandomizeSeed == null
          ? null
          : SnackBarAction(
              label: context.l.generationRandomizeSeed.toUpperCase(),
              textColor: AppTone.warning.color(context.tRead),
              onPressed: onRandomizeSeed,
            ),
    );
  }

  void _showAuthError() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    showAppSnackBar(
      context,
      context.l.mainAuthError.toUpperCase(),
      tone: AppTone.error,
      action: SnackBarAction(
        label: context.l.mainSettings.toUpperCase(),
        textColor: context.tRead.textPrimary,
        onPressed: () => _push(const ToolsHubScreen(initialToolId: 'settings')),
      ),
    );
  }

  void _push(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  void _cycleStyle(bool forward) {
    final notifier = context.read<GenerationNotifier>();
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

    final count = cyclableStyles.length;
    final nextIndex = forward
        ? (currentIndex + 1) % count
        // With no active style, backwards starts from the last one.
        : currentIndex < 0
        ? count - 1
        : (currentIndex - 1 + count) % count;

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

  /// Tells the user once that references and vibes were paused or resumed.
  void _onReferenceAccessChanged() {
    final monitor = _accessMonitor;
    final notice = monitor?.notice;
    if (monitor == null || notice == null) return;
    monitor.acknowledge();
    // The monitor changes while providers rebuild, not in a frame of its own.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final message = referenceAccessNoticeText(context.l, notice);
      notice.resumed
          ? showAppSnackBar(context, message)
          : showErrorSnackBar(context, message);
    });
  }

  GenerationLayoutSpec _layoutOf(BuildContext context) =>
      GenerationLayoutSpec.of(
        context,
        sidebarMode: context.read<ThemeNotifier>().sidebarLayoutMode,
      );

  /// Opens where the references and vibes are managed.
  void _openInputs(GenerationNotifier notifier) {
    final sheet = _mobileGenerationSheetKey.currentState;
    if (sheet != null) {
      unawaited(sheet.openTab(GenerationMobileTab.inputs));
      return;
    }
    if (!_layoutOf(context).isSidebar && !notifier.state.isSettingsExpanded) {
      notifier.toggleSettings();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = ExpandedSettingsContent.referenceSectionKey.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 250),
        );
      }
    });
  }

  void _startGeneration(GenerationNotifier notifier, int imageBatchLimit) {
    if (notifier.quote?.canSubmit == false) return;
    final mobileSheet = _mobileGenerationSheetKey.currentState;
    if (mobileSheet != null) unawaited(mobileSheet.collapse());
    final future = notifier.generate(
      batchLimit: imageBatchLimit,
      confirmQuote: (confirmation) => confirmQuoteChange(context, confirmation),
    );
    if (!useBackendGateway) return;
    future.whenComplete(() {
      if (!mounted) return;
      unawaited(context.read<BackendAuthNotifier>().refreshSession());
    });
  }

  void _selectResultImage(GenerationNotifier notifier, String id) {
    _composerKey.currentState?.unfocus();
    notifier.selectGeneratedImage(id);
  }

  // — Style and preset actions, shared by every layout —

  void _manageStyles() {
    final state = context.read<GenerationNotifier>().state;
    String? activeStyle;
    for (final name in state.activeStyleNames) {
      final style = state.styles
          .where((candidate) => candidate.name == name)
          .firstOrNull;
      if (style != null && !style.isDefault) {
        activeStyle = name;
        break;
      }
    }
    activeStyle ??= state.activeStyleNames.firstOrNull;
    _editStyle(activeStyle);
  }

  void _editStyle(String? styleName) => _push(
    ToolsHubScreen(initialToolId: 'styles', initialStyleName: styleName),
  );

  Future<void> _savePreset() async {
    final notifier = context.read<GenerationNotifier>();
    final l = context.l;
    final name = await showTextInputDialog(
      context,
      title: l.mainSavePreset.toUpperCase(),
      confirmLabel: l.commonSave,
      hintText: l.mainPresetName.toUpperCase(),
    );
    if (name != null) notifier.savePreset(name);
  }

  Future<void> _openServerHistory() async {
    final imported = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => ServerHistoryScreen(api: widget.historyApi),
      ),
    );
    if (imported != true || !mounted) return;
    final notifier = context.read<GenerationNotifier>();
    final sheet = _mobileGenerationSheetKey.currentState;
    if (sheet != null) {
      await sheet.openTab(GenerationMobileTab.prompt);
    } else if (notifier.state.isSettingsExpanded) {
      notifier.toggleSettings();
    }
  }

  Widget _settings({
    GenerationSettingsGroup group = GenerationSettingsGroup.all,
    bool inSidebar = false,
    bool forceCompact = false,
    bool ownsScrollView = true,
  }) => ExpandedSettingsContent(
    group: group,
    inSidebar: inSidebar,
    forceCompact: forceCompact,
    ownsScrollView: ownsScrollView,
    onManageStyles: _manageStyles,
    onEditStyle: _editStyle,
    onSavePreset: () => unawaited(_savePreset()),
  );

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<GenerationNotifier>();
    final cascade = context.watch<CascadeNotifier>().state.activeCascade;
    final themeNotifier = context.watch<ThemeNotifier>();
    final layout = GenerationLayoutSpec.of(
      context,
      sidebarMode: themeNotifier.sidebarLayoutMode,
    );
    final t = context.t;
    final highlight = SyntaxHighlightColors.fromTokens(t);
    notifier.promptController.colors = highlight;
    notifier.negativePromptController.colors = highlight;
    final imageGenerationAllowed = canGenerateImage(context);
    final imageBatchLimit = backendImageBatchLimit(context);
    final state = notifier.state;
    final isCascadeMode = cascade != null;

    final Widget body = switch (layout.mode) {
      GenerationLayoutMode.sidebar => _buildSidebarBody(
        context,
        layout,
        notifier,
        state,
        isCascadeMode,
        themeNotifier.sidebarPromptPosition == 'left',
      ),
      GenerationLayoutMode.sheet => _buildSheetBody(
        context,
        layout,
        notifier,
        state,
        isCascadeMode,
      ),
      GenerationLayoutMode.regular => _buildRegularBody(
        context,
        layout,
        notifier,
        state,
        isCascadeMode,
      ),
    };

    final Widget scaffold = GenerationShortcuts(
      onGenerate: () {
        if (imageGenerationAllowed && !notifier.state.isLoading) {
          _startGeneration(notifier, imageBatchLimit);
        }
      },
      onCycleStyle: _cycleStyle,
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
          appBar: GenerationAppBar(
            layout: layout,
            toolbarHeight: context.touchSize,
            onHelp: () => showHelpDialog(context),
            onGallery: () => _push(const GalleryScreen()),
            onServerHistory: () => unawaited(_openServerHistory()),
            onTools: () => _push(const ToolsHubScreen()),
          ),
          body: SafeArea(bottom: false, left: false, right: false, child: body),
        ),
      ),
    );

    return isDesktopPlatform()
        ? DropTarget(
            onDragDone: (details) async {
              if (details.files.isEmpty) return;
              try {
                await notifier.importImageMetadata(
                  File(details.files.first.path),
                );
              } catch (e) {
                if (!context.mounted) return;
                showErrorSnackBar(context, context.l.mainImportFailed('$e'));
              }
            },
            onDragEntered: (details) => notifier.setDragging(true),
            onDragExited: (details) => notifier.setDragging(false),
            child: scaffold,
          )
        : scaffold;
  }

  Widget _buildResults(
    GenerationLayoutSpec layout,
    GenerationNotifier notifier,
    GenerationState state,
  ) {
    return GenerationResultsWorkspace(
      notifier: notifier,
      state: state,
      mobile: layout.touch,
      pulseAnimation: _pulseAnimation,
      onSelectImage: (id) => _selectResultImage(notifier, id),
    );
  }

  // — Touch-sized windows: prompt, inputs and parameters in a bottom sheet —
  Widget _buildSheetBody(
    BuildContext context,
    GenerationLayoutSpec layout,
    GenerationNotifier notifier,
    GenerationState state,
    bool isCascadeMode,
  ) {
    final results = _buildResults(layout, notifier, state);
    if (isCascadeMode) {
      return GenerationPageLayout(
        results: results,
        footer: const CascadePlaybackView(),
      );
    }

    final t = context.t;
    final activeInputCount =
        context.watch<DirectorRefNotifier>().sentCount +
        context.watch<VibeTransferNotifier>().sentCount;

    return GenerationPageLayout(
      // Resolved inside the layout, where the sheet measures itself.
      overlayReservedHeightOf: GenerationMobileSheet.collapsedHeightOf,
      results: results,
      footer: const SizedBox.shrink(),
      overlay: Positioned.fill(
        child: GenerationMobileSheet(
          key: _mobileGenerationSheetKey,
          promptLabel: context.l.generationSheetPrompt.toUpperCase(),
          inputsLabel: context.l.generationSheetInputs.toUpperCase(),
          parametersLabel: context.l.generationSheetParameters.toUpperCase(),
          inputCount: activeInputCount,
          compactPrompt: ValueListenableBuilder<TextEditingValue>(
            valueListenable: notifier.promptController,
            builder: (context, value, _) {
              final prompt = value.text.trim();
              return Row(
                children: [
                  Icon(
                    Icons.edit_outlined,
                    size: VisionMetrics.iconMedium,
                    color: t.textDisabled,
                  ),
                  const SizedBox(width: VisionMetrics.space8),
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
          compactActions: _buildCompactGenerationAction(context, notifier),
          prompt: GenerationMobilePromptPage(
            prompt: _buildComposer(
              context,
              layout,
              notifier,
              state,
              PromptLayoutSlot.sheet,
            ),
            settings: _settings(
              group: GenerationSettingsGroup.prompt,
              forceCompact: true,
              ownsScrollView: false,
            ),
          ),
          inputs: _settings(
            group: GenerationSettingsGroup.inputs,
            forceCompact: true,
          ),
          parameters: _settings(
            group: GenerationSettingsGroup.parameters,
            forceCompact: true,
          ),
        ),
      ),
    );
  }

  // — Expanded windows: prompt footer plus the bottom settings panel —
  Widget _buildRegularBody(
    BuildContext context,
    GenerationLayoutSpec layout,
    GenerationNotifier notifier,
    GenerationState state,
    bool isCascadeMode,
  ) {
    return GenerationPageLayout(
      overlayReservedHeight: AdvancedSettingsPanel.collapsedExtent(context),
      results: _buildResults(layout, notifier, state),
      footer: isCascadeMode
          ? const CascadePlaybackView()
          : state.isSettingsExpanded
          ? const SizedBox.shrink()
          : _buildComposer(
              context,
              layout,
              notifier,
              state,
              PromptLayoutSlot.footer,
              showQuickSeed: true,
            ),
      overlay: AdvancedSettingsPanel(
        prompt: isCascadeMode
            ? null
            : _buildComposer(
                context,
                layout,
                notifier,
                state,
                PromptLayoutSlot.panel,
              ),
        onManageStyles: _manageStyles,
        onEditStyle: _editStyle,
        onSavePreset: () => unawaited(_savePreset()),
      ),
    );
  }

  // — Large windows: settings in a sidebar —
  Widget _buildSidebarBody(
    BuildContext context,
    GenerationLayoutSpec layout,
    GenerationNotifier notifier,
    GenerationState state,
    bool isCascadeMode,
    bool promptOnLeft,
  ) {
    final t = context.t;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compactSidebar =
        context.watch<ThemeNotifier>().sidebarWidthMode == 'compact';
    final sidebarWidth = compactSidebar
        ? (screenWidth * 0.28).clamp(300.0, 380.0)
        : (screenWidth * 0.38).clamp(420.0, 560.0);

    return Row(
      children: [
        SizedBox(
          width: sidebarWidth,
          child: Container(
            decoration: BoxDecoration(
              color: t.surfaceHigh,
              border: Border(right: BorderSide(color: t.borderStrong)),
            ),
            child: Column(
              children: [
                Expanded(child: _settings(inSidebar: true)),
                if (promptOnLeft && !isCascadeMode)
                  _buildComposer(
                    context,
                    layout,
                    notifier,
                    state,
                    PromptLayoutSlot.sidebar,
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: GenerationPageLayout(
            results: _buildResults(layout, notifier, state),
            footer: isCascadeMode
                ? const CascadePlaybackView()
                : promptOnLeft
                ? const SizedBox.shrink()
                : SafeArea(
                    top: false,
                    left: false,
                    right: false,
                    child: _buildComposer(
                      context,
                      layout,
                      notifier,
                      state,
                      PromptLayoutSlot.footer,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // — The main prompt, in whichever [slot] the layout puts it —
  Widget _buildComposer(
    BuildContext context,
    GenerationLayoutSpec layout,
    GenerationNotifier notifier,
    GenerationState state,
    PromptLayoutSlot slot, {
    bool showQuickSeed = false,
  }) {
    final t = context.t;
    final imageGenerationAllowed = canGenerateImage(context);
    final imageBatchLimit = backendImageBatchLimit(context);
    final defaultLines = switch (slot) {
      PromptLayoutSlot.panel || PromptLayoutSlot.sheet => 4,
      PromptLayoutSlot.sidebar => 5,
      PromptLayoutSlot.footer =>
        layout.touch ? t.promptMaxLines + 2 : t.promptMaxLines + 1,
    };
    return PromptComposer(
      key: _composerKey,
      controller: notifier.promptController,
      suggestions: state.tagSuggestions,
      slot: slot,
      defaultLines: defaultLines,
      shelf: slot.embedded
          ? null
          : Selector<GenerationNotifier, String>(
              selector: (_, n) => n.state.characterEditorMode,
              builder: (context, mode, _) => mode == 'compact'
                  ? const CharacterShelf()
                  : const SizedBox.shrink(),
            ),
      seedControl:
          showQuickSeed && context.read<PreferencesService>().showSeedControl
          ? GenerationSeedControl(
              controller: notifier.seedController,
              randomize: state.randomizeSeed,
              onRandomizeChanged: (randomize) =>
                  notifier.updateSettings(randomizeSeed: randomize),
              variant: GenerationSeedControlVariant.compact,
            )
          : null,
      onTextChanged: (text) => notifier.handleTagSuggestions(
        text,
        notifier.promptController.selection,
      ),
      onSuggestionAccepted: (tag) => _applyMainTagSuggestion(notifier, tag),
      onSuggestionsDismissed: notifier.clearTagSuggestions,
      onFocusGained: () {
        final sheet = _mobileGenerationSheetKey.currentState;
        if (sheet != null) {
          unawaited(sheet.openTab(GenerationMobileTab.prompt));
        }
      },
      action: PromptGenerationAction(
        estimateHeight: GenerationStatus.heightOf(
          compact: false,
          touch: layout.touch,
        ),
        estimate: imageGenerationAllowed
            ? GenerationStatus(
                compact: false,
                onOpenInputs: () => _openInputs(notifier),
              )
            : null,
        generateButton: GenerateButton(
          compact: false,
          onPressed: () {
            FocusScope.of(context).unfocus();
            _startGeneration(notifier, imageBatchLimit);
          },
        ),
      ),
    );
  }

  Widget _buildCompactGenerationAction(
    BuildContext context,
    GenerationNotifier notifier,
  ) {
    final imageGenerationAllowed = canGenerateImage(context);
    final imageBatchLimit = backendImageBatchLimit(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (imageGenerationAllowed) ...[
          SizedBox(
            width: 104,
            height: GenerationStatus.heightOf(compact: true, touch: true),
            child: GenerationStatus(
              compact: true,
              onOpenInputs: () => _openInputs(notifier),
            ),
          ),
          const SizedBox(width: VisionMetrics.space8),
        ],
        SizedBox(
          width: 42,
          height: 38,
          child: GenerateButton(
            compact: true,
            onPressed: () {
              FocusScope.of(context).unfocus();
              _startGeneration(notifier, imageBatchLimit);
            },
          ),
        ),
      ],
    );
  }
}
