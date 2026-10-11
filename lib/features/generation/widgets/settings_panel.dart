import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/gateway/backend_gateway.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/gateway/backend_permissions.dart';
import '../../../core/gateway/backend_rules.dart';
import '../../../core/services/client_diagnostics.dart';
import '../../../core/services/preferences_service.dart';
import '../../../core/services/tag_service.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/tag_suggestion_helper.dart';
import '../../../core/widgets/tag_suggestion_overlay.dart';
import '../../../core/widgets/browser_native_text_area.dart';
import '../../../core/widgets/web_style_bridge.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/theme_notifier.dart';
import '../../../core/theme/vision_metrics.dart';
import '../../../core/theme/vision_tokens.dart';
import '../../../core/widgets/section_title.dart';
import '../../../core/widgets/text_input_dialog.dart';
import '../../../core/widgets/ui/app_panel.dart';
import '../../../core/widgets/ui/app_pill.dart';
import '../../../core/widgets/ui/app_states.dart';
import '../../../core/widgets/ui/app_tabs.dart';
import '../../../core/widgets/custom_resolution_dialog.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/editable_slider_value.dart';
import '../../../core/widgets/vision_slider.dart';
import '../../../core/services/styles.dart';
import '../../gallery/providers/gallery_notifier.dart';
import '../../director_ref/providers/director_ref_notifier.dart';
import '../../director_ref/widgets/director_ref_shelf.dart';
import '../../vibe_transfer/providers/vibe_transfer_notifier.dart';
import '../models/generation_quote.dart';
import '../providers/generation_notifier.dart';
import 'billing_text.dart';
import 'chip_actions.dart';
import 'generation_seed_control.dart';
import 'inline_character_editor.dart';
import 'vibe_transfer_shelf.dart';
import 'prompt_shortcuts.dart';

class ResolutionOption {
  final String label;
  final int width;
  final int height;
  final bool isCustom;

  const ResolutionOption(
    this.label,
    this.width,
    this.height, {
    this.isCustom = false,
  });

  String get value => "${width}x$height";
  String get displayLabel => "$label ${width}x$height";

  Map<String, dynamic> toJson() => {
    'label': label,
    'width': width,
    'height': height,
  };

  factory ResolutionOption.fromJson(Map<String, dynamic> json) =>
      ResolutionOption(
        json['label'] as String,
        json['width'] as int,
        json['height'] as int,
        isCustom: true,
      );
}

class AdvancedSettingsPanel extends StatelessWidget {
  static double collapsedExtent(BuildContext context) {
    return context.hitSize + MediaQuery.viewPaddingOf(context).bottom;
  }

  static List<ResolutionOption> resolutionOptions(BuildContext context) {
    final l = context.l;
    final builtIn = [
      ResolutionOption(l.resNormalPortrait.toUpperCase(), 832, 1216),
      ResolutionOption(l.resNormalLandscape.toUpperCase(), 1216, 832),
      ResolutionOption(l.resNormalSquare.toUpperCase(), 1024, 1024),
      ResolutionOption(l.resLargePortrait.toUpperCase(), 1024, 1536),
      ResolutionOption(l.resLargeLandscape.toUpperCase(), 1536, 1024),
      ResolutionOption(l.resLargeSquare.toUpperCase(), 1472, 1472),
      ResolutionOption(l.resWallpaperPortrait.toUpperCase(), 1088, 1920),
      ResolutionOption(l.resWallpaperLandscape.toUpperCase(), 1920, 1088),
    ];
    final prefs = Provider.of<PreferencesService>(context, listen: false);
    final custom = _loadCustomResolutions(prefs);
    return [...builtIn, ...custom];
  }

  /// The built-in and saved resolutions the gateway prices as free
  /// (`rules.free_sizes`).
  static List<ResolutionOption> freeResolutionOptions(
    BuildContext context,
    ImageRules? rules,
  ) {
    final freeSizes = rules?.freeSizes ?? const [];
    return resolutionOptions(context)
        .where(
          (opt) => freeSizes.any(
            (size) => size.width == opt.width && size.height == opt.height,
          ),
        )
        .toList();
  }

  static List<ResolutionOption> _loadCustomResolutions(
    PreferencesService prefs,
  ) {
    final raw = prefs.customResolutions;
    if (raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => ResolutionOption.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveCustomResolution(
    PreferencesService prefs,
    ResolutionOption option,
  ) async {
    final existing = _loadCustomResolutions(prefs);
    existing.add(option);
    await prefs.setCustomResolutions(
      jsonEncode(existing.map((e) => e.toJson()).toList()),
    );
  }

  /// Removes the saved resolution equal to [option] (label and size). Looking
  /// the entry up, rather than counting from the dropdown position, keeps this
  /// right when the list shown is filtered (a free-only account sees only the
  /// free sizes).
  static Future<void> deleteCustomResolutionOption(
    PreferencesService prefs,
    ResolutionOption option,
  ) async {
    final existing = _loadCustomResolutions(prefs);
    final index = existing.indexWhere(
      (e) =>
          e.label == option.label &&
          e.width == option.width &&
          e.height == option.height,
    );
    await deleteCustomResolution(prefs, index);
  }

  static Future<void> deleteCustomResolution(
    PreferencesService prefs,
    int index,
  ) async {
    final existing = _loadCustomResolutions(prefs);
    if (index >= 0 && index < existing.length) {
      existing.removeAt(index);
      await prefs.setCustomResolutions(
        jsonEncode(existing.map((e) => e.toJson()).toList()),
      );
    }
  }

  /// Creates an album named [rawName] and makes it the default save target.
  /// A blank (or whitespace-only) name is refused; the name is stored trimmed.
  /// Returns whether an album was created.
  static bool createAlbumFromInput(
    String rawName,
    GalleryNotifier gallery,
    PreferencesService prefs,
  ) {
    final name = rawName.trim();
    if (name.isEmpty) return false;
    gallery.createAlbum(name);
    prefs.setDefaultSaveAlbumId(gallery.albums.last.id);
    return true;
  }

  static const List<String> samplers = [
    "k_euler_ancestral",
    "k_euler",
    "k_dpmpp_2s_ancestral",
    "k_dpmpp_2m",
    "k_dpmpp_sde",
  ];

  /// Callback for navigating to the style manager.
  final VoidCallback onManageStyles;

  /// Callback for opening a specific style's settings.
  final void Function(String styleName)? onEditStyle;

  /// Callback for showing the save-preset dialog.
  final VoidCallback onSavePreset;

  /// Main prompt composer shown as the first item while the panel is expanded.
  final Widget? prompt;

  static const promptRegionKey = ValueKey<String>(
    'advanced-settings-prompt-region',
  );

  const AdvancedSettingsPanel({
    super.key,
    required this.onManageStyles,
    this.onEditStyle,
    required this.onSavePreset,
    this.prompt,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Selector<GenerationNotifier, bool>(
      selector: (_, n) => n.state.isSettingsExpanded,
      builder: (context, isExpanded, _) {
        final notifier = context.read<GenerationNotifier>();

        final mobile = isTouchSized(context);
        final headerH = context.hitSize;
        final collapsedH = collapsedExtent(context);
        final expandedH = math.max(
          MediaQuery.of(context).size.height * (mobile ? 0.75 : 0.6),
          collapsedH,
        );

        return AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          left: 0,
          right: 0,
          bottom: 0,
          height: isExpanded ? expandedH : collapsedH,
          child: GestureDetector(
            onVerticalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity < -300 && !isExpanded) notifier.toggleSettings();
              if (velocity > 300 && isExpanded) notifier.toggleSettings();
            },
            child: Container(
              decoration: BoxDecoration(
                color: t.surfaceHigh,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(VisionMetrics.radius12),
                ),
                border: Border.all(color: t.borderStrong),
                boxShadow: [
                  BoxShadow(
                    color: t.textPrimary.withValues(
                      alpha: VisionMetrics.opacityHover,
                    ),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: OverflowBox(
                alignment: Alignment.topCenter,
                maxHeight: expandedH,
                minHeight: collapsedH,
                child: Column(
                  children: [
                    // Grabber
                    InkWell(
                      onTap: notifier.toggleSettings,
                      child: Container(
                        width: double.infinity,
                        height: headerH,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 48,
                              height: 4,
                              decoration: BoxDecoration(
                                color: t.textDisabled,
                                borderRadius: BorderRadius.circular(
                                  VisionMetrics.radius2,
                                ),
                              ),
                            ),
                            if (!isExpanded)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: VisionMetrics.space4,
                                ),
                                child: Text(
                                  context.l.panelAdvancedSettings.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: t.fontSize(mobile ? 10 : 9),
                                    letterSpacing: 2,
                                    color: t.secondaryText,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // Scrollable Content — only watch full state when expanded
                    if (isExpanded)
                      Expanded(
                        child: ExpandedSettingsContent(
                          leading: prompt == null
                              ? null
                              : KeyedSubtree(
                                  key: promptRegionKey,
                                  child: prompt!,
                                ),
                          onManageStyles: onManageStyles,
                          onEditStyle: onEditStyle,
                          onSavePreset: onSavePreset,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Inner content of the expanded settings panel.
/// Uses context.watch so it rebuilds on state changes,
/// but only exists in the tree when the panel is expanded.
enum GenerationSettingsGroup { all, prompt, inputs, parameters }

class ExpandedSettingsContent extends StatefulWidget {
  /// The references and vibes section, wherever the settings are shown; the
  /// active-inputs indicator scrolls to it.
  static final referenceSectionKey = GlobalKey(
    debugLabel: 'generation-reference-section',
  );

  final VoidCallback onManageStyles;
  final void Function(String styleName)? onEditStyle;
  final VoidCallback onSavePreset;
  final bool inSidebar;
  final bool forceCompact;
  final bool ownsScrollView;
  final GenerationSettingsGroup group;
  final Widget? leading;

  const ExpandedSettingsContent({
    super.key,
    required this.onManageStyles,
    this.onEditStyle,
    required this.onSavePreset,
    this.inSidebar = false,
    this.forceCompact = false,
    this.ownsScrollView = true,
    this.group = GenerationSettingsGroup.all,
    this.leading,
  });

  @override
  State<ExpandedSettingsContent> createState() =>
      _ExpandedSettingsContentState();
}

class _ExpandedSettingsContentState extends State<ExpandedSettingsContent> {
  final _negativePromptFocus = FocusNode();
  bool _stylesExpanded = false;
  List<DanbooruTag> _negativeSuggestions = [];
  Timer? _negativeTagDebounce;

  /// Touch-sized controls: the window is compact or medium, or the settings
  /// are forced into the compact (bottom sheet) presentation. Set by [build]
  /// for the section builders.
  bool _touch = false;

  @override
  void initState() {
    super.initState();
    _stylesExpanded = Provider.of<PreferencesService>(
      context,
      listen: false,
    ).uiStylesExpanded;
    _negativePromptFocus.addListener(_onNegativeFocusChanged);
  }

  void _onNegativeFocusChanged() {
    ClientDiagnostics.instance.record('negative_prompt_focus_changed', {
      'has_focus': _negativePromptFocus.hasFocus,
      'suggestion_count': _negativeSuggestions.length,
      'view_insets_bottom': MediaQuery.maybeOf(context)?.viewInsets.bottom,
    });
    if (!_negativePromptFocus.hasFocus && _negativeSuggestions.isNotEmpty) {
      setState(() => _negativeSuggestions = []);
    }
  }

  void _onNegativePromptChanged() {
    _negativeTagDebounce?.cancel();
    _negativeTagDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      if (context.read<GalleryNotifier>().demoMode) return;
      final notifier = context.read<GenerationNotifier>();
      final result = TagSuggestionHelper.getSuggestions(
        text: notifier.negativePromptController.text,
        selection: notifier.negativePromptController.selection,
        tagService: notifier.tagService,
        supportFavorites: true,
        wildcardService: notifier.wildcardService,
      );
      setState(() => _negativeSuggestions = result.suggestions);
    });
  }

  @override
  void dispose() {
    _negativeTagDebounce?.cancel();
    _negativePromptFocus.removeListener(_onNegativeFocusChanged);
    _negativePromptFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<GenerationNotifier>();
    final state = notifier.state;
    // Touch-sized windows (compact and medium) get the large controls, whether
    // the settings sit in the bottom sheet, the panel or the sidebar.
    final mobile = isTouchSized(context) || widget.forceCompact;
    _touch = mobile;
    final t = context.t;
    final sectionOrder = context.watch<ThemeNotifier>().sectionOrder;

    final compact = widget.inSidebar || widget.forceCompact;
    final hPad = compact ? VisionMetrics.space16 : VisionMetrics.space24;
    final sectionGap = compact ? VisionMetrics.space16 : VisionMetrics.space24;
    final showLocalGalleryControls = !(useBackendGateway && kIsWeb);

    final builders = <String, Widget Function()>{
      'dimensions_seed': () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (notifier.quote?.canAdjustToFree ?? false)
            _buildFreeParametersNotice(notifier, notifier.quote!, t),
          _buildDimensionsSeed(notifier, state, mobile, t, compact: compact),
        ],
      ),
      'steps_scale': () =>
          _buildStepsScale(notifier, state, mobile, t, compact: compact),
      'sampler_post': () =>
          _buildSamplerPost(notifier, state, mobile, t, compact: compact),
      'characters': () => const InlineCharacterEditor(),
      if (canUsePaidImageFeatures(context) ||
          context.watch<DirectorRefNotifier>().references.isNotEmpty ||
          context.watch<VibeTransferNotifier>().vibes.isNotEmpty)
        'reference_images': () => _buildReferenceImages(state, mobile, t),
      'styles': () => _buildStyles(notifier, state, t),
      'negative_prompt': () => _buildNegativePrompt(notifier, t),
      'presets': () => _buildPresets(notifier, state, t),
      if (showLocalGalleryControls)
        'save_to_album': () => _buildSaveToAlbum(context, t, mobile),
    };

    final allowedSectionIds = switch (widget.group) {
      GenerationSettingsGroup.all => null,
      GenerationSettingsGroup.prompt => const {
        'characters',
        'styles',
        'negative_prompt',
      },
      GenerationSettingsGroup.inputs => const {'reference_images'},
      GenerationSettingsGroup.parameters => const {
        'dimensions_seed',
        'steps_scale',
        'sampler_post',
        'presets',
        'save_to_album',
      },
    };

    final sections = <Widget>[if (widget.leading != null) widget.leading!];
    for (final id in sectionOrder) {
      if (allowedSectionIds != null && !allowedSectionIds.contains(id)) {
        continue;
      }
      final builder = builders[id];
      if (builder != null) {
        if (sections.isNotEmpty) sections.add(SizedBox(height: sectionGap));
        try {
          sections.add(builder());
        } catch (e) {
          sections.add(
            Text(
              'Error in $id: $e',
              style: TextStyle(color: t.accentDanger, fontSize: t.fontSize(9)),
            ),
          );
        }
      }
    }
    if (widget.group == GenerationSettingsGroup.inputs &&
        !_referenceInputsVisible(state)) {
      final noPermission = !builders.containsKey('reference_images');
      sections.add(
        EmptyState(
          icon: Icons.photo_library_outlined,
          title: context.l.panelInputsEmptyTitle,
          message: noPermission
              ? context.l.panelInputsEmptyMessage
              : context.l.panelInputsHiddenMessage,
        ),
      );
    }
    sections.add(const SizedBox(height: VisionMetrics.space24));

    final padding = EdgeInsets.fromLTRB(
      hPad,
      VisionMetrics.space8,
      hPad,
      40 +
          MediaQuery.of(context).padding.bottom +
          MediaQuery.of(context).viewInsets.bottom,
    );
    if (!widget.ownsScrollView) {
      return Padding(
        padding: padding,
        child: Column(mainAxisSize: MainAxisSize.min, children: sections),
      );
    }
    return ListView(padding: padding, children: sections);
  }

  /// Which reference shelves are shown. The shelf switches only decide what
  /// is shown for editing; what is sent never depends on them. Vibes already
  /// on the list stay visible (and can be removed) without the permission to
  /// encode new ones.
  (bool ref, bool vibe) _referenceShelves(GenerationState state) {
    final showRef = state.showDirectorRefShelf;
    final showVibe =
        state.showVibeTransferShelf &&
        (hasBackendPermission(context, BackendPermission.imageEncodeVibe) ||
            context.watch<VibeTransferNotifier>().vibes.isNotEmpty);
    return (showRef, showVibe);
  }

  /// Whether the inputs tab has anything to show: the section is offered to
  /// the account (paid tools, or entries already on the lists) and at least
  /// one shelf is switched on.
  bool _referenceInputsVisible(GenerationState state) {
    final offered =
        canUsePaidImageFeatures(context) ||
        context.watch<DirectorRefNotifier>().references.isNotEmpty ||
        context.watch<VibeTransferNotifier>().vibes.isNotEmpty;
    if (!offered) return false;
    final (showRef, showVibe) = _referenceShelves(state);
    return showRef || showVibe;
  }

  Widget _buildReferenceImages(
    GenerationState state,
    bool mobile,
    VisionTokens t,
  ) {
    final (showRef, showVibe) = _referenceShelves(state);
    if (!showRef && !showVibe) return const SizedBox.shrink();

    return KeyedSubtree(
      key: ExpandedSettingsContent.referenceSectionKey,
      child: Column(
        key: const ValueKey<String>('advanced-reference-images'),
        children: [
          if (showRef)
            _buildReferenceInputRow(
              key: const ValueKey<String>('advanced-precise-reference-row'),
              label: context.l.refPreciseReferences,
              icon: Icons.person_search_outlined,
              color: t.accentRefCharacter,
              shelf: const DirectorRefShelf(),
              mobile: mobile,
              t: t,
            ),
          if (showRef && showVibe) const SizedBox(height: VisionMetrics.space8),
          if (showVibe)
            _buildReferenceInputRow(
              key: const ValueKey<String>('advanced-vibe-transfer-row'),
              label: context.l.refVibeTransfer,
              icon: Icons.auto_awesome_outlined,
              color: t.accentVibeTransfer,
              shelf: const VibeTransferShelf(),
              mobile: mobile,
              t: t,
            ),
        ],
      ),
    );
  }

  /// Shown to an account that can only generate for free while its settings
  /// would cost red points: nothing is changed until the user asks.
  Widget _buildFreeParametersNotice(
    GenerationNotifier notifier,
    GenerationQuote quote,
    VisionTokens t,
  ) {
    final l = context.l;
    return Padding(
      padding: const EdgeInsets.only(bottom: VisionMetrics.space12),
      child: AppPanel(
        variant: AppPanelVariant.raised,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.quoteFreeOnlyNotice,
              style: TextStyle(
                color: t.textSecondary,
                fontSize: t.fontSize(10),
              ),
            ),
            for (final reason in quote.quote?.reasons ?? const <String>[])
              Text(
                '• ${quoteReasonText(l, reason)}',
                style: TextStyle(
                  color: t.textTertiary,
                  fontSize: t.fontSize(10),
                ),
              ),
            if (quote.quote == null)
              Text(
                l.quoteInvalidTooltip(quote.invalidField ?? ''),
                style: TextStyle(
                  color: t.textTertiary,
                  fontSize: t.fontSize(10),
                ),
              ),
            const SizedBox(height: VisionMetrics.space8),
            TextButton(
              onPressed: notifier.adjustToFreeParameters,
              child: Text(
                l.quoteAdjustToFreeAction.toUpperCase(),
                style: TextStyle(color: t.accent, fontSize: t.fontSize(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReferenceInputRow({
    required Key key,
    required String label,
    required IconData icon,
    required Color color,
    required Widget shelf,
    required bool mobile,
    required VisionTokens t,
  }) {
    return KeyedSubtree(
      key: key,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: mobile ? 64 : 56),
        child: AppPanel(
          variant: AppPanelVariant.inset,
          padding: const EdgeInsets.symmetric(
            horizontal: VisionMetrics.space12,
            vertical: VisionMetrics.space8,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: mobile
                    ? VisionMetrics.iconMedium
                    : VisionMetrics.iconSmall,
                color: color,
              ),
              const SizedBox(width: VisionMetrics.space8),
              SizedBox(
                width: mobile ? 92 : 118,
                child: Text(
                  label.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: t.fontSize(mobile ? 10 : 8),
                    letterSpacing: 0.8,
                    color: t.secondaryText,
                  ),
                ),
              ),
              const SizedBox(width: VisionMetrics.space8),
              Expanded(
                child: Align(alignment: Alignment.centerLeft, child: shelf),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDimensionsSeed(
    GenerationNotifier notifier,
    GenerationState state,
    bool mobile,
    VisionTokens t, {
    bool compact = false,
  }) {
    final batchLimit = backendImageBatchLimit(context);
    final batchValue = math.max(1, math.min(state.batchCount, batchLimit));
    final freeOnly = isFreeOnlyImageUser(context);
    final resolutionOptions = freeOnly
        ? AdvancedSettingsPanel.freeResolutionOptions(
            context,
            notifier.imageRules,
          )
        : AdvancedSettingsPanel.resolutionOptions(context);
    final selectedResolution =
        resolutionOptions.any(
          (opt) =>
              opt.width == state.width.toInt() &&
              opt.height == state.height.toInt(),
        )
        ? "${state.width.toInt()}x${state.height.toInt()}"
        : null;

    void updateBatchCount(int value) {
      notifier.updateSettings(
        batchCount: math.max(1, math.min(value, batchLimit)),
      );
    }

    Widget dimensionsField = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(context.l.panelDimensions.toUpperCase(), t: t),
        DropdownButtonFormField<String>(
          // ignore: deprecated_member_use
          value: selectedResolution,
          dropdownColor: t.surfaceHigh,
          hint: Text(
            selectedResolution == null && !freeOnly
                ? "${state.width.toInt()}x${state.height.toInt()} (${context.l.panelCustom.toUpperCase()})"
                : "${state.width.toInt()}x${state.height.toInt()}",
            style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(11)),
          ),
          style: TextStyle(
            color: t.textPrimary,
            fontSize: t.fontSize(11),
            letterSpacing: 1,
          ),
          decoration: InputDecoration(
            contentPadding: EdgeInsets.symmetric(
              horizontal: VisionMetrics.space12,
              vertical: mobile ? VisionMetrics.space12 : VisionMetrics.space8,
            ),
            fillColor: t.borderSubtle,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: VisionMetrics.borderRadius4,
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (String? newValue) async {
            if (freeOnly && newValue == '__custom__') return;
            if (newValue == '__custom__') {
              final result = await showCustomResolutionDialog(context);
              if (result != null) {
                notifier.updateSettings(
                  width: result.width.toDouble(),
                  height: result.height.toDouble(),
                );
                if (mounted) setState(() {});
              }
              return;
            }
            if (newValue != null) {
              final parts = newValue.split('x');
              notifier.updateSettings(
                width: double.parse(parts[0]),
                height: double.parse(parts[1]),
              );
            }
          },
          items: [
            ...resolutionOptions.map<DropdownMenuItem<String>>((opt) {
              return DropdownMenuItem<String>(
                value: opt.value,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        opt.displayLabel,
                        style: TextStyle(fontSize: t.fontSize(10)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (opt.isCustom)
                      Tooltip(
                        message: context.l.commonDelete,
                        child: GestureDetector(
                          onTap: () => _deleteCustomResolution(opt),
                          child: Padding(
                            padding: const EdgeInsets.only(
                              left: VisionMetrics.space8,
                            ),
                            child: Icon(
                              Icons.close,
                              size: VisionMetrics.iconSmall,
                              color: t.textMinimal,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
            if (!freeOnly)
              DropdownMenuItem<String>(
                value: '__custom__',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add,
                      size: VisionMetrics.iconSmall,
                      color: t.accent,
                    ),
                    const SizedBox(width: VisionMetrics.space8),
                    Text(
                      context.l.resCustomEntry.toUpperCase(),
                      style: TextStyle(
                        fontSize: t.fontSize(10),
                        color: t.accent,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );

    final seedField = GenerationSeedControl(
      controller: notifier.seedController,
      randomize: state.randomizeSeed,
      onRandomizeChanged: (randomize) =>
          notifier.updateSettings(randomizeSeed: randomize),
    );

    Widget batchField = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(context.l.panelBatchCount.toUpperCase(), t: t),
        Container(
          decoration: BoxDecoration(
            color: t.borderSubtle,
            borderRadius: VisionMetrics.borderRadius4,
          ),
          child: Row(
            children: [
              SizedBox(
                width: context.hitSize,
                height: context.hitSize,
                child: IconButton(
                  onPressed: batchValue <= 1
                      ? null
                      : () => updateBatchCount(batchValue - 1),
                  tooltip: context.l.panelBatchCount,
                  icon: const Icon(
                    Icons.remove,
                    size: VisionMetrics.iconMedium,
                  ),
                  color: t.textSecondary,
                  disabledColor: t.textDisabled,
                  padding: EdgeInsets.zero,
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '$batchValue/$batchLimit',
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: t.fontSize(11),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: context.hitSize,
                height: context.hitSize,
                child: IconButton(
                  onPressed: batchValue >= batchLimit
                      ? null
                      : () => updateBatchCount(batchValue + 1),
                  tooltip: context.l.panelBatchCount,
                  icon: const Icon(Icons.add, size: VisionMetrics.iconMedium),
                  color: t.textSecondary,
                  disabledColor: t.textDisabled,
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (mobile || compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          dimensionsField,
          const SizedBox(height: VisionMetrics.space16),
          seedField,
          const SizedBox(height: VisionMetrics.space16),
          batchField,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: dimensionsField),
        const SizedBox(width: VisionMetrics.space24),
        Expanded(flex: 1, child: seedField),
        const SizedBox(width: VisionMetrics.space24),
        Expanded(flex: 1, child: batchField),
      ],
    );
  }

  Widget _buildStepsScale(
    GenerationNotifier notifier,
    GenerationState state,
    bool mobile,
    VisionTokens t, {
    bool compact = false,
  }) {
    final freeOnly = isFreeOnlyImageUser(context);
    // The gateway's limits for this account; a direct NovelAI account has
    // NovelAI's own (28 free, 50 at most).
    final rules = notifier.imageRules;
    final freeSteps = rules?.freeMaxSteps ?? 28;
    final maxSteps = rules?.maxSteps ?? 50;
    final stepsLimit = freeOnly ? freeSteps : maxSteps;
    Widget stepsSlider = _buildCompactSlider(
      context,
      context.l.panelSteps.toUpperCase(),
      state.steps,
      1,
      stepsLimit.toDouble(),
      1,
      (v) => notifier.updateSettings(steps: v),
      t,
      warnAbove: freeSteps.toDouble(),
      hardMax: stepsLimit.toDouble(),
    );
    Widget scaleSlider = _buildCompactSlider(
      context,
      context.l.panelScale.toUpperCase(),
      state.scale,
      1.0,
      30.0,
      0.5,
      (v) => notifier.updateSettings(scale: v),
      t,
      hardMax: 100.0,
      warnAbove: 30,
    );

    if (mobile || compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          stepsSlider,
          const SizedBox(height: VisionMetrics.space16),
          scaleSlider,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: stepsSlider),
        const SizedBox(width: VisionMetrics.space24),
        Expanded(child: scaleSlider),
      ],
    );
  }

  Widget _buildSamplerPost(
    GenerationNotifier notifier,
    GenerationState state,
    bool mobile,
    VisionTokens t, {
    bool compact = false,
  }) {
    // Through the gateway only the samplers it accepts are offered; the one in
    // use stays listed so the field never shows a value it has no item for.
    final accepted = notifier.imageRules?.allowedSamplers ?? const <String>[];
    final offered = notifier.service.viaGateway && accepted.isNotEmpty
        ? accepted
        : AdvancedSettingsPanel.samplers;
    final samplers = offered.contains(state.sampler)
        ? offered
        : [state.sampler, ...offered];

    Widget samplerField = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(context.l.panelSampler.toUpperCase(), t: t),
        DropdownButtonFormField<String>(
          // ignore: deprecated_member_use
          value: state.sampler,
          dropdownColor: t.surfaceHigh,
          style: TextStyle(
            color: t.textPrimary,
            fontSize: t.fontSize(11),
            letterSpacing: 1,
          ),
          decoration: InputDecoration(
            contentPadding: EdgeInsets.symmetric(
              horizontal: VisionMetrics.space12,
              vertical: mobile ? VisionMetrics.space12 : VisionMetrics.space8,
            ),
            fillColor: t.borderSubtle,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: VisionMetrics.borderRadius4,
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (String? newValue) {
            if (newValue != null) notifier.updateSettings(sampler: newValue);
          },
          items: samplers.map<DropdownMenuItem<String>>((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(
                value.toUpperCase(),
                style: TextStyle(fontSize: t.fontSize(10)),
              ),
            );
          }).toList(),
        ),
      ],
    );

    Widget furryToggle = _buildFlagToggle(
      icon: Icons.pets,
      label: 'FURRY',
      active: state.furryMode,
      color: t.accentFavorite,
      onTap: () => notifier.updateSettings(furryMode: !state.furryMode),
      mobile: mobile,
      t: t,
    );

    Widget curatedToggle = _buildFlagToggle(
      icon: Icons.auto_awesome,
      label: 'CURATED',
      active: state.useCurated,
      color: t.accentSuccess,
      onTap: () => notifier.updateSettings(useCurated: !state.useCurated),
      mobile: mobile,
      t: t,
    );

    if (mobile || compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          samplerField,
          const SizedBox(height: VisionMetrics.space16),
          Wrap(
            spacing: VisionMetrics.space12,
            runSpacing: VisionMetrics.space8,
            children: [furryToggle, curatedToggle],
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 1, child: samplerField),
        const SizedBox(width: VisionMetrics.space24),
        furryToggle,
        const SizedBox(width: VisionMetrics.space12),
        curatedToggle,
      ],
    );
  }

  /// A labelled on/off toggle that lights up in [color] while [active].
  Widget _buildFlagToggle({
    required IconData icon,
    required String label,
    required bool active,
    required Color color,
    required VoidCallback onTap,
    required bool mobile,
    required VisionTokens t,
  }) {
    final foreground = active ? color : t.textDisabled;
    final radius = BorderRadius.circular(VisionMetrics.radius4);
    return Material(
      color: active
          ? color.withValues(alpha: VisionMetrics.opacityPressed)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: active ? color : t.borderMedium),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: context.hitSize),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: VisionMetrics.space12,
              vertical: VisionMetrics.space8,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: mobile
                      ? VisionMetrics.iconMedium
                      : VisionMetrics.iconSmall,
                  color: foreground,
                ),
                const SizedBox(width: VisionMetrics.space8),
                Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: t.fontSize(mobile ? 10 : 9),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Deletes a saved custom resolution after the user confirms, then closes
  /// the open dropdown (its item list is stale from here on).
  Future<void> _deleteCustomResolution(ResolutionOption option) async {
    final l = context.l;
    final prefs = context.read<PreferencesService>();
    final confirmed = await showConfirmDialog(
      context,
      title: l.panelDeleteResolution,
      message: l.panelDeleteResolutionConfirm(option.displayLabel),
      confirmLabel: l.commonDelete,
      cancelLabel: l.commonCancel,
    );
    if (confirmed != true || !mounted) return;
    await AdvancedSettingsPanel.deleteCustomResolutionOption(prefs, option);
    if (!mounted) return;
    setState(() {});
    Navigator.of(context).maybePop();
  }

  Widget _buildStyleChip(
    PromptStyle style,
    bool isSelected,
    GenerationNotifier notifier,
    VisionTokens t,
  ) {
    final tooltipBuffer = StringBuffer(style.name);
    if (style.prefix.isNotEmpty) {
      tooltipBuffer.write('\n+ ${style.prefix}');
    }
    if (style.suffix.isNotEmpty) {
      tooltipBuffer.write('\n+ ${style.suffix}');
    }
    if (style.negativeContent.isNotEmpty) {
      tooltipBuffer.write('\nNEG: ${style.negativeContent}');
    }
    return Tooltip(
      message: tooltipBuffer.toString(),
      waitDuration: const Duration(milliseconds: 200),
      preferBelow: false,
      textStyle: TextStyle(color: t.textPrimary, fontSize: t.fontSize(9)),
      decoration: BoxDecoration(
        color: t.surfaceHigh,
        borderRadius: BorderRadius.circular(VisionMetrics.radius4),
        border: Border.all(color: t.borderMedium),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: VisionMetrics.space8,
        vertical: VisionMetrics.space4,
      ),
      child: GestureDetector(
        // Long press opens the same menu as on every other chip; styles can
        // only be edited from here (they are deleted in the style manager).
        onLongPress: widget.onEditStyle != null
            ? () => showChipActions(
                context,
                title: style.name,
                onEdit: () => widget.onEditStyle!(style.name),
              )
            : null,
        child: FilterChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  style.name.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: t.fontSize(8),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
              for (final badge in [
                if (style.negativeContent.isNotEmpty) 'NEG',
                if (style.prefix.isNotEmpty || style.suffix.isNotEmpty) 'POS',
              ]) ...[
                const SizedBox(width: VisionMetrics.space4),
                AppPill(text: badge, dense: true),
              ],
            ],
          ),
          selected: isSelected,
          onSelected: (_) {
            if (HardwareKeyboard.instance.isControlPressed &&
                widget.onEditStyle != null) {
              widget.onEditStyle!(style.name);
            } else {
              notifier.toggleStyle(style.name);
            }
          },
          backgroundColor: t.borderSubtle,
          selectedColor: t.accent,
          checkmarkColor: t.background,
          showCheckmark: false,
          labelStyle: TextStyle(
            color: isSelected ? t.background : t.textTertiary,
          ),
          padding: const EdgeInsets.symmetric(horizontal: VisionMetrics.space8),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(VisionMetrics.radius2),
          ),
          side: BorderSide(color: isSelected ? t.accent : t.textMinimal),
        ),
      ),
    );
  }

  Widget _buildStyles(
    GenerationNotifier notifier,
    GenerationState state,
    VisionTokens t,
  ) {
    final hit = context.hitSize;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          context.l.panelStyles.toUpperCase(),
          t: t,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.styles.isNotEmpty)
                IconButton(
                  icon: Icon(
                    _stylesExpanded ? Icons.unfold_less : Icons.unfold_more,
                    size: VisionMetrics.iconSmall,
                    color: t.textDisabled,
                  ),
                  tooltip: context.l.settingsStylesToggle,
                  onPressed: () {
                    setState(() => _stylesExpanded = !_stylesExpanded);
                    context.read<PreferencesService>().setUiStylesExpanded(
                      _stylesExpanded,
                    );
                  },
                  constraints: BoxConstraints(minWidth: hit, minHeight: hit),
                  padding: EdgeInsets.zero,
                ),
              IconButton(
                icon: Icon(
                  Icons.settings_outlined,
                  size: VisionMetrics.iconSmall,
                  color: t.textDisabled,
                ),
                onPressed: widget.onManageStyles,
                tooltip: context.l.panelManageStyles.toUpperCase(),
                constraints: BoxConstraints(minWidth: hit, minHeight: hit),
                padding: EdgeInsets.zero,
              ),
              _buildChipToggle(
                context.l.panelEnabled.toUpperCase(),
                state.isStyleEnabled,
                (v) => notifier.updateSettings(isStyleEnabled: v),
                t,
              ),
            ],
          ),
        ),
        if (state.styles.isEmpty)
          Text(
            context.l.panelNoStylesDefined.toUpperCase(),
            style: TextStyle(
              fontSize: t.fontSize(8),
              color: t.textMinimal,
              letterSpacing: 1,
            ),
          )
        else if (_stylesExpanded)
          Wrap(
            spacing: VisionMetrics.space8,
            runSpacing: VisionMetrics.space8,
            children: state.styles.map((style) {
              final isSelected = state.activeStyleNames.contains(style.name);
              return _buildStyleChip(style, isSelected, notifier, t);
            }).toList(),
          )
        else
          SizedBox(
            height: hit,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: state.styles.length,
              itemBuilder: (context, index) {
                final style = state.styles[index];
                final isSelected = state.activeStyleNames.contains(style.name);
                return Padding(
                  padding: const EdgeInsets.only(right: VisionMetrics.space8),
                  child: _buildStyleChip(style, isSelected, notifier, t),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildNegativePrompt(GenerationNotifier notifier, VisionTokens t) {
    // The native Web control renders at the bridge's mobile-safe size (iOS
    // Safari zooms focused controls below 16px, whatever the window size);
    // size the box from that same value.
    final nativeFontSize = t.fontSize(11);
    final renderedFontSize = supportsBrowserNativeTextArea
        ? browserInputFontSize(
            t.fontSize(11),
            textScaler: MediaQuery.textScalerOf(context),
            platform: defaultTargetPlatform,
          )
        : nativeFontSize;
    final nativeBackground = Color.alphaBlend(t.borderSubtle, t.surfaceHigh);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(context.l.panelNegativePrompt.toUpperCase(), t: t),
        PromptKeyScope(
          controller: notifier.negativePromptController,
          builder: (context, onKeyDown) => BrowserNativeTextArea(
            controller: notifier.negativePromptController,
            focusNode: _negativePromptFocus,
            onKeyDown: onKeyDown,
            onBlur: () {
              if (_negativeSuggestions.isNotEmpty && mounted) {
                setState(() => _negativeSuggestions = []);
              }
            },
            style: TextStyle(
              fontSize: nativeFontSize,
              color: t.textSecondary,
              height: 1.4,
            ),
            // Platform views are DOM layers. Use the pre-composited opaque fill
            // so translucency is never resolved against the browser's white
            // page background while the textarea is focused.
            backgroundColor: nativeBackground,
            selectionColor: t.accent.withValues(alpha: 0.72),
            selectionTextColor: _readableOn(
              t.accent,
              t.textPrimary,
              t.background,
            ),
            padding: const EdgeInsets.all(VisionMetrics.space16),
            height: renderedFontSize * 1.4 * 3 + 32,
            onChanged: (_) => _onNegativePromptChanged(),
            fallback: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.stylus,
                },
              ),
              child: TextField(
                focusNode: _negativePromptFocus,
                controller: notifier.negativePromptController,
                maxLines: 3,
                onChanged: (_) => _onNegativePromptChanged(),
                style: TextStyle(
                  fontSize: t.fontSize(11),
                  color: t.textSecondary,
                  height: 1.4,
                ),
                decoration: InputDecoration(
                  fillColor: t.borderSubtle,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(VisionMetrics.radius4),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(VisionMetrics.space16),
                ),
              ),
            ),
          ),
        ),
        if (_negativeSuggestions.isNotEmpty)
          TagSuggestionOverlay(
            suggestions: _negativeSuggestions,
            onTagSelected: (tag) {
              TagSuggestionHelper.applyTag(
                notifier.negativePromptController,
                tag,
              );
              setState(() => _negativeSuggestions = []);
            },
          ),
      ],
    );
  }

  Widget _buildPresets(
    GenerationNotifier notifier,
    GenerationState state,
    VisionTokens t,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          context.l.panelPresets.toUpperCase(),
          t: t,
          trailing: IconButton(
            icon: Icon(
              Icons.add_circle_outline,
              size: VisionMetrics.iconSmall,
              color: t.secondaryText,
            ),
            tooltip: context.l.mainSavePreset,
            onPressed: widget.onSavePreset,
            constraints: BoxConstraints(
              minWidth: context.hitSize,
              minHeight: context.hitSize,
            ),
            padding: EdgeInsets.zero,
          ),
        ),
        if (state.presets.isEmpty)
          Text(
            context.l.panelNoPresetsSaved.toUpperCase(),
            style: TextStyle(
              fontSize: t.fontSize(8),
              color: t.textMinimal,
              letterSpacing: 1,
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: state.presets.length,
            separatorBuilder: (context, index) =>
                const SizedBox(height: VisionMetrics.space8),
            itemBuilder: (context, index) {
              final preset = state.presets[index];
              return AppPanel(
                variant: AppPanelVariant.inset,
                padding: EdgeInsets.zero,
                child: ListTile(
                  dense: true,
                  title: Text(
                    preset.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: t.fontSize(10),
                      letterSpacing: 1,
                      color: t.textSecondary,
                    ),
                  ),
                  subtitle: Text(
                    "${preset.width.toInt()}x${preset.height.toInt()} • ${preset.sampler}",
                    style: TextStyle(
                      fontSize: t.fontSize(8),
                      color: t.textDisabled,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.download,
                          size: VisionMetrics.iconSmall,
                          color: t.textTertiary,
                        ),
                        tooltip: context.l.presetLoad,
                        onPressed: () => notifier.applyPreset(preset),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          size: VisionMetrics.iconSmall,
                          color: t.textMinimal,
                        ),
                        tooltip: context.l.commonDelete,
                        onPressed: () => _confirmDeletePreset(
                          context,
                          notifier,
                          index,
                          preset.name,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildSaveToAlbum(BuildContext context, VisionTokens t, bool mobile) {
    final gallery = context.watch<GalleryNotifier>();
    final prefs = context.read<PreferencesService>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(context.l.panelSaveToAlbum.toUpperCase(), t: t),
        StatefulBuilder(
          builder: (context, setChipState) {
            final currentId = prefs.defaultSaveAlbumId;
            return SizedBox(
              height: context.hitSize,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: gallery.albums.length + 1,
                itemBuilder: (context, index) {
                  // Last item is the "+" create-album chip
                  if (index == gallery.albums.length) {
                    return Padding(
                      padding: const EdgeInsets.only(
                        right: VisionMetrics.space8,
                      ),
                      child: ActionChip(
                        avatar: Icon(
                          Icons.add,
                          size: VisionMetrics.iconSmall,
                          color: t.textTertiary,
                        ),
                        label: Text(
                          context.l.panelNew.toUpperCase(),
                          style: TextStyle(
                            fontSize: t.fontSize(mobile ? 9 : 8),
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                            color: t.textTertiary,
                          ),
                        ),
                        backgroundColor: t.borderSubtle,
                        padding: const EdgeInsets.symmetric(
                          horizontal: VisionMetrics.space8,
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            VisionMetrics.radius2,
                          ),
                        ),
                        side: BorderSide(color: t.textMinimal),
                        onPressed: () =>
                            _showCreateAlbumDialog(context, gallery, prefs),
                      ),
                    );
                  }
                  final album = gallery.albums[index];
                  final isActive = album.id == currentId;
                  return Padding(
                    padding: const EdgeInsets.only(right: VisionMetrics.space8),
                    child: FilterChip(
                      label: Text(
                        album.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: t.fontSize(mobile ? 9 : 8),
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      selected: isActive,
                      onSelected: (_) {
                        prefs.setDefaultSaveAlbumId(isActive ? null : album.id);
                        setChipState(() {});
                      },
                      backgroundColor: t.borderSubtle,
                      selectedColor: t.accentSuccess,
                      checkmarkColor: t.background,
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        color: isActive ? t.background : t.textTertiary,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: VisionMetrics.space8,
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          VisionMetrics.radius2,
                        ),
                      ),
                      side: BorderSide(
                        color: isActive ? t.accentSuccess : t.textMinimal,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _showCreateAlbumDialog(
    BuildContext context,
    GalleryNotifier gallery,
    PreferencesService prefs,
  ) async {
    final l = context.l;
    final name = await showTextInputDialog(
      context,
      title: l.panelNewAlbum.toUpperCase(),
      confirmLabel: l.commonCreate,
      hintText: l.panelAlbumName.toUpperCase(),
    );
    if (name == null) return;
    AdvancedSettingsPanel.createAlbumFromInput(name, gallery, prefs);
  }

  Future<void> _confirmDeletePreset(
    BuildContext context,
    GenerationNotifier notifier,
    int index,
    String name,
  ) async {
    final t = context.t;
    final confirm = await showConfirmDialog(
      context,
      title: context.l.panelDeletePreset,
      message: context.l.panelDeletePresetConfirm(name),
      confirmLabel: context.l.commonDelete,
      confirmColor: t.accentDanger,
    );
    if (confirm == true) {
      notifier.deletePreset(index);
    }
  }

  Widget _buildCompactSlider(
    BuildContext context,
    String label,
    double value,
    double min,
    double max,
    double step,
    Function(double) onChanged,
    VisionTokens t, {
    double? warnAbove,
    double? hardMin,
    double? hardMax,
  }) {
    final mobile = _touch;
    final isWarning = warnAbove != null && value > warnAbove;
    final isInteger = step >= 1;
    // The slider itself stays on [min, max]; if the typed value exceeds the
    // soft max, pin the thumb to the end so the track stays valid.
    final sliderValue = value.clamp(min, max).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: t.fontSize(mobile ? 12 : 9),
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                color: t.secondaryText,
              ),
            ),
            EditableSliderValue(
              value: value,
              softMin: min,
              softMax: max,
              hardMin: hardMin,
              hardMax: hardMax,
              isInteger: isInteger,
              decimals: 1,
              onChanged: onChanged,
              style: TextStyle(
                fontSize: t.fontSize(mobile ? 13 : 10),
                fontWeight: FontWeight.bold,
                color: isWarning ? t.accentDanger : t.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: VisionMetrics.space4),
        VisionSlider(
          value: sliderValue,
          min: min,
          max: max,
          divisions: ((max - min) / step).toInt(),
          activeColor: isWarning ? t.accentDanger : t.accent,
          inactiveColor: t.textMinimal,
          thumbColor: isWarning ? t.accentDanger : t.accent,
          thumbRadius: mobile ? 8 : 4,
          overlayRadius: mobile ? 16 : 0,
          trackHeight: 1,
          onChanged: (v) => onChanged(
            isInteger ? v.roundToDouble() : double.parse(v.toStringAsFixed(1)),
          ),
        ),
      ],
    );
  }

  Widget _buildChipToggle(
    String label,
    bool value,
    Function(bool) onChanged,
    VisionTokens t,
  ) {
    return AppSegmented<bool>(
      options: [AppOption(value: true, label: label)],
      selected: value,
      onChanged: (_) => onChanged(!value),
    );
  }
}

/// Whichever of [a] and [b] reads better on top of [background].
Color _readableOn(Color background, Color a, Color b) {
  double contrast(Color x, Color y) {
    final lx = x.computeLuminance();
    final ly = y.computeLuminance();
    return (lx > ly ? lx + 0.05 : ly + 0.05) /
        (lx > ly ? ly + 0.05 : lx + 0.05);
  }

  return contrast(background, a) >= contrast(background, b) ? a : b;
}
