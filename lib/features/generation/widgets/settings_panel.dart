import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/theme_notifier.dart';
import '../../../core/theme/vision_tokens.dart';
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
import 'generation_seed_control.dart';
import 'inline_character_editor.dart';
import 'vibe_transfer_shelf.dart';

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
    final headerHeight = isMobile(context) ? 48.0 : 40.0;
    return headerHeight + MediaQuery.viewPaddingOf(context).bottom;
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

        final mobile = isMobile(context);
        final headerH = mobile ? 48.0 : 40.0;
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
                  top: Radius.circular(12),
                ),
                border: Border.all(color: t.borderStrong),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.05),
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
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            if (!isExpanded)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
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
    final mobile = isMobile(context) || widget.forceCompact;
    final t = context.t;
    final sectionOrder = context.watch<ThemeNotifier>().sectionOrder;

    final compact = widget.inSidebar || widget.forceCompact;
    final hPad = compact ? 16.0 : 24.0;
    final sectionGap = compact ? 16.0 : 24.0;
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
              style: TextStyle(color: Colors.red, fontSize: t.fontSize(9)),
            ),
          );
        }
      }
    }
    sections.add(const SizedBox(height: 20));

    final padding = EdgeInsets.fromLTRB(
      hPad,
      8,
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

  Widget _buildReferenceImages(
    GenerationState state,
    bool mobile,
    VisionTokens t,
  ) {
    // The shelf switches only decide what is shown for editing; what is sent
    // never depends on them. Vibes already on the list stay visible (and can
    // be removed) without the permission to encode new ones.
    final showRef = state.showDirectorRefShelf;
    final showVibe =
        state.showVibeTransferShelf &&
        (hasBackendPermission(context, BackendPermission.imageEncodeVibe) ||
            context.watch<VibeTransferNotifier>().vibes.isNotEmpty);
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
          if (showRef && showVibe) const SizedBox(height: 8),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.accentDanger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: t.accentDanger.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.quoteFreeOnlyNotice,
            style: TextStyle(color: t.textSecondary, fontSize: t.fontSize(10)),
          ),
          for (final reason in quote.quote?.reasons ?? const <String>[])
            Text(
              '• ${quoteReasonText(l, reason)}',
              style: TextStyle(color: t.textTertiary, fontSize: t.fontSize(10)),
            ),
          if (quote.quote == null)
            Text(
              l.quoteInvalidTooltip(quote.invalidField ?? ''),
              style: TextStyle(color: t.textTertiary, fontSize: t.fontSize(10)),
            ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: notifier.adjustToFreeParameters,
            child: Text(
              l.quoteAdjustToFreeAction.toUpperCase(),
              style: TextStyle(color: t.accent, fontSize: t.fontSize(10)),
            ),
          ),
        ],
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
    return Container(
      key: key,
      constraints: BoxConstraints(minHeight: mobile ? 64 : 56),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: t.borderSubtle.withValues(alpha: 0.2),
        border: Border.all(color: t.borderSubtle),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(icon, size: mobile ? 18 : 15, color: color),
          const SizedBox(width: 8),
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
          const SizedBox(width: 8),
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: shelf),
          ),
        ],
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
    final labelStyle = TextStyle(
      fontWeight: FontWeight.w900,
      fontSize: t.fontSize(mobile ? 12 : 9),
      letterSpacing: 2,
      color: t.secondaryText,
    );
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
        Text(context.l.panelDimensions.toUpperCase(), style: labelStyle),
        const SizedBox(height: 12),
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            fillColor: t.borderSubtle,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
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
            ...resolutionOptions.asMap().entries.map<DropdownMenuItem<String>>((
              entry,
            ) {
              final opt = entry.value;
              final builtInCount = 8;
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
                      GestureDetector(
                        onTap: () {
                          final prefs = context.read<PreferencesService>();
                          AdvancedSettingsPanel.deleteCustomResolution(
                            prefs,
                            entry.key - builtInCount,
                          );
                          setState(() {});
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Icon(
                            Icons.close,
                            size: 14,
                            color: t.textMinimal,
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
                    Icon(Icons.add, size: 14, color: t.accent),
                    const SizedBox(width: 8),
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
        Text(context.l.panelBatchCount.toUpperCase(), style: labelStyle),
        const SizedBox(height: 12),
        Container(
          height: 42,
          decoration: BoxDecoration(
            color: t.borderSubtle,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 38,
                height: 38,
                child: IconButton(
                  onPressed: batchValue <= 1
                      ? null
                      : () => updateBatchCount(batchValue - 1),
                  icon: const Icon(Icons.remove, size: 16),
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
                width: 38,
                height: 38,
                child: IconButton(
                  onPressed: batchValue >= batchLimit
                      ? null
                      : () => updateBatchCount(batchValue + 1),
                  icon: const Icon(Icons.add, size: 16),
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
          const SizedBox(height: 16),
          seedField,
          const SizedBox(height: 16),
          batchField,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: dimensionsField),
        const SizedBox(width: 24),
        Expanded(flex: 1, child: seedField),
        const SizedBox(width: 24),
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
        children: [stepsSlider, const SizedBox(height: 16), scaleSlider],
      );
    }
    return Row(
      children: [
        Expanded(child: stepsSlider),
        const SizedBox(width: 32),
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
    final labelStyle = TextStyle(
      fontWeight: FontWeight.w900,
      fontSize: t.fontSize(mobile ? 12 : 9),
      letterSpacing: 2,
      color: t.secondaryText,
    );

    Widget samplerField = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l.panelSampler.toUpperCase(), style: labelStyle),
        const SizedBox(height: 12),
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            fillColor: t.borderSubtle,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (String? newValue) {
            if (newValue != null) notifier.updateSettings(sampler: newValue);
          },
          items: AdvancedSettingsPanel.samplers.map<DropdownMenuItem<String>>((
            String value,
          ) {
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

    Widget furryToggle = InkWell(
      onTap: () => notifier.updateSettings(furryMode: !state.furryMode),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: state.furryMode ? const Color(0xFFFF9800) : t.borderMedium,
          ),
          color: state.furryMode
              ? const Color(0xFFFF9800).withValues(alpha: 0.15)
              : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.pets,
              size: mobile ? 16 : 14,
              color: state.furryMode ? const Color(0xFFFF9800) : t.textDisabled,
            ),
            const SizedBox(width: 8),
            Text(
              'FURRY',
              style: TextStyle(
                color: state.furryMode
                    ? const Color(0xFFFF9800)
                    : t.textDisabled,
                fontSize: t.fontSize(mobile ? 10 : 9),
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );

    Widget curatedToggle = InkWell(
      onTap: () => notifier.updateSettings(useCurated: !state.useCurated),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: state.useCurated ? const Color(0xFF4CAF50) : t.borderMedium,
          ),
          color: state.useCurated
              ? const Color(0xFF4CAF50).withValues(alpha: 0.15)
              : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome,
              size: mobile ? 16 : 14,
              color: state.useCurated
                  ? const Color(0xFF4CAF50)
                  : t.textDisabled,
            ),
            const SizedBox(width: 8),
            Text(
              'CURATED',
              style: TextStyle(
                color: state.useCurated
                    ? const Color(0xFF4CAF50)
                    : t.textDisabled,
                fontSize: t.fontSize(mobile ? 10 : 9),
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );

    if (mobile || compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          samplerField,
          const SizedBox(height: 16),
          Row(
            children: [furryToggle, const SizedBox(width: 12), curatedToggle],
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 1, child: samplerField),
        const SizedBox(width: 24),
        furryToggle,
        const SizedBox(width: 12),
        curatedToggle,
      ],
    );
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
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: t.borderMedium),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: GestureDetector(
        onLongPress: widget.onEditStyle != null
            ? () => widget.onEditStyle!(style.name)
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
              if (style.negativeContent.isNotEmpty) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? t.background.withValues(alpha: 0.2)
                        : t.borderMedium,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    "NEG",
                    style: TextStyle(
                      fontSize: t.fontSize(6),
                      fontWeight: FontWeight.w900,
                      color: isSelected ? t.background : t.textTertiary,
                    ),
                  ),
                ),
              ],
              if (style.prefix.isNotEmpty || style.suffix.isNotEmpty) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? t.background.withValues(alpha: 0.2)
                        : t.borderMedium,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    "POS",
                    style: TextStyle(
                      fontSize: t.fontSize(6),
                      fontWeight: FontWeight.w900,
                      color: isSelected ? t.background : t.textTertiary,
                    ),
                  ),
                ),
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
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
          side: BorderSide(
            color: isSelected ? t.accent : t.textMinimal,
            width: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildStyles(
    GenerationNotifier notifier,
    GenerationState state,
    VisionTokens t,
  ) {
    final mobile = isMobile(context);
    final labelStyle = TextStyle(
      fontWeight: FontWeight.w900,
      fontSize: t.fontSize(mobile ? 12 : 9),
      letterSpacing: 2,
      color: t.secondaryText,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(context.l.panelStyles.toUpperCase(), style: labelStyle),
            Row(
              children: [
                if (state.styles.isNotEmpty)
                  IconButton(
                    icon: Icon(
                      _stylesExpanded ? Icons.unfold_less : Icons.unfold_more,
                      size: 14,
                      color: t.textDisabled,
                    ),
                    tooltip: context.l.settingsStylesToggle,
                    onPressed: () {
                      setState(() => _stylesExpanded = !_stylesExpanded);
                      context.read<PreferencesService>().setUiStylesExpanded(
                        _stylesExpanded,
                      );
                    },
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.only(right: 12),
                  ),
                IconButton(
                  icon: Icon(
                    Icons.settings_outlined,
                    size: 14,
                    color: t.textDisabled,
                  ),
                  onPressed: widget.onManageStyles,
                  tooltip: context.l.panelManageStyles.toUpperCase(),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.only(right: 12),
                ),
                _buildChipToggle(
                  context.l.panelEnabled.toUpperCase(),
                  state.isStyleEnabled,
                  (v) => notifier.updateSettings(isStyleEnabled: v),
                  t,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
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
            spacing: 8,
            runSpacing: 8,
            children: state.styles.map((style) {
              final isSelected = state.activeStyleNames.contains(style.name);
              return _buildStyleChip(style, isSelected, notifier, t);
            }).toList(),
          )
        else
          SizedBox(
            height: 32,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: state.styles.length,
              itemBuilder: (context, index) {
                final style = state.styles[index];
                final isSelected = state.activeStyleNames.contains(style.name);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buildStyleChip(style, isSelected, notifier, t),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildNegativePrompt(GenerationNotifier notifier, VisionTokens t) {
    final mobile = isMobile(context);
    // iOS Safari zooms focused form controls whose font size is below 16px.
    // Keep the native Web control at a mobile-safe size; the Flutter fallback
    // below retains the regular theme scale.
    final nativeFontSize = mobile && t.fontSize(11) < 16
        ? 16.0
        : t.fontSize(11);
    final nativeBackground = Color.alphaBlend(t.borderSubtle, t.surfaceHigh);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l.panelNegativePrompt.toUpperCase(),
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: t.fontSize(mobile ? 12 : 9),
            letterSpacing: 2,
            color: t.secondaryText,
          ),
        ),
        const SizedBox(height: 12),
        BrowserNativeTextArea(
          controller: notifier.negativePromptController,
          focusNode: _negativePromptFocus,
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
          selectionTextColor:
              ThemeData.estimateBrightnessForColor(t.accent) == Brightness.dark
              ? Colors.white
              : Colors.black,
          padding: const EdgeInsets.all(16),
          height: nativeFontSize * 1.4 * 3 + 32,
          onChanged: (_) => _onNegativePromptChanged(),
          fallback: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.stylus},
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
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(16),
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
    final mobile = isMobile(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              context.l.panelPresets.toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: t.fontSize(mobile ? 12 : 9),
                letterSpacing: 2,
                color: t.secondaryText,
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.add_circle_outline,
                size: 14,
                color: t.secondaryText,
              ),
              tooltip: context.l.mainSavePreset,
              onPressed: widget.onSavePreset,
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
        const SizedBox(height: 12),
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
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final preset = state.presets[index];
              return Container(
                decoration: BoxDecoration(
                  color: t.borderSubtle,
                  borderRadius: BorderRadius.circular(4),
                ),
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
                          size: 14,
                          color: t.textTertiary,
                        ),
                        tooltip: context.l.presetLoad,
                        onPressed: () => notifier.applyPreset(preset),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          size: 14,
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
    final labelStyle = TextStyle(
      fontWeight: FontWeight.w900,
      fontSize: t.fontSize(mobile ? 12 : 9),
      letterSpacing: 2,
      color: t.secondaryText,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l.panelSaveToAlbum.toUpperCase(), style: labelStyle),
        const SizedBox(height: 12),
        StatefulBuilder(
          builder: (context, setChipState) {
            final currentId = prefs.defaultSaveAlbumId;
            return SizedBox(
              height: mobile ? 42 : 34,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: gallery.albums.length + 1,
                itemBuilder: (context, index) {
                  // Last item is the "+" create-album chip
                  if (index == gallery.albums.length) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        avatar: Icon(
                          Icons.add,
                          size: mobile ? 14 : 12,
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
                        padding: EdgeInsets.symmetric(
                          horizontal: mobile ? 8 : 6,
                          vertical: 0,
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(2),
                        ),
                        side: BorderSide(color: t.textMinimal, width: 0.5),
                        onPressed: () =>
                            _showCreateAlbumDialog(context, gallery, prefs),
                      ),
                    );
                  }
                  final album = gallery.albums[index];
                  final isActive = album.id == currentId;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
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
                      padding: EdgeInsets.symmetric(
                        horizontal: mobile ? 8 : 6,
                        vertical: 0,
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(2),
                      ),
                      side: BorderSide(
                        color: isActive ? t.accentSuccess : t.textMinimal,
                        width: 0.5,
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

  void _showCreateAlbumDialog(
    BuildContext context,
    GalleryNotifier gallery,
    PreferencesService prefs,
  ) {
    final controller = TextEditingController();
    final t = context.read<ThemeNotifier>().tokens;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surfaceHigh,
        title: Text(
          ctx.l.panelNewAlbum.toUpperCase(),
          style: TextStyle(
            fontSize: t.fontSize(10),
            letterSpacing: 2,
            color: t.textSecondary,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(13)),
          decoration: InputDecoration(
            hintText: ctx.l.panelAlbumName.toUpperCase(),
            hintStyle: TextStyle(color: t.textMinimal, fontSize: t.fontSize(9)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: t.borderMedium),
            ),
          ),
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
            onPressed: () {
              if (controller.text.isNotEmpty) {
                gallery.createAlbum(controller.text.trim());
                final newAlbum = gallery.albums.last;
                prefs.setDefaultSaveAlbumId(newAlbum.id);
                Navigator.pop(ctx);
              }
            },
            child: Text(
              ctx.l.commonCreate.toUpperCase(),
              style: TextStyle(color: t.accent, fontSize: t.fontSize(9)),
            ),
          ),
        ],
      ),
    );
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
    final mobile = isMobile(context);
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
        const SizedBox(height: 4),
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
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: t.fontSize(9),
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
      selected: value,
      onSelected: onChanged,
      backgroundColor: t.borderSubtle,
      selectedColor: t.accent,
      checkmarkColor: t.background,
      labelStyle: TextStyle(color: value ? t.background : t.textTertiary),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
      side: BorderSide(color: value ? t.accent : t.textMinimal, width: 0.5),
    );
  }
}
