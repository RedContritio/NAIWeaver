import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/theme/app_theme_config.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/theme_notifier.dart';
import '../../../core/theme/vision_tokens.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/manager_list_tile.dart';
import '../../../core/widgets/section_title.dart';
import '../../../core/widgets/text_input_dialog.dart';
import '../../../core/widgets/color_picker_dialog.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/manager_shell.dart';
import '../../../core/theme/vision_metrics.dart';

Map<String, String> _sectionDisplayNames(AppLocalizations l) => {
  'dimensions_seed': l.themeSectionDimSeed,
  'steps_scale': l.themeSectionStepsScale,
  'sampler_post': l.themeSectionSamplerPost,
  'characters': l.themeSectionCharacters,
  'reference_images': l.generationSheetInputs,
  'styles': l.themeSectionStyles,
  'negative_prompt': l.themeSectionNegPrompt,
  'presets': l.themeSectionPresets,
  'save_to_album': l.themeSectionSaveAlbum,
};

class ThemeBuilder extends StatefulWidget {
  const ThemeBuilder({super.key});

  @override
  State<ThemeBuilder> createState() => _ThemeBuilderState();
}

class _ThemeBuilderState extends State<ThemeBuilder> {
  String? _editingThemeId;
  bool _showingEditor = false;

  static const List<String> _fontOptions = [
    'JetBrains Mono',
    'Fira Code',
    'IBM Plex Mono',
    'Space Mono',
    'Roboto Mono',
    'Inter',
    'Space Grotesk',
  ];

  @override
  Widget build(BuildContext context) {
    final themeNotifier = context.watch<ThemeNotifier>();
    final t = themeNotifier.tokens;
    final l = context.l;
    final config = themeNotifier.activeConfig;

    return ManagerMasterDetailShell(
      showDetail: _showingEditor && _editingThemeId != null,
      masterWidth: 260,
      detailTitle: config.name,
      detailActions: _editorActions(themeNotifier, config, t),
      onCloseDetail: () {
        themeNotifier.clearPreview();
        setState(() => _showingEditor = false);
      },
      master: _buildList(themeNotifier, t),
      detail: _editingThemeId != null
          ? _buildEditor(themeNotifier, t)
          : Center(
              child: Text(
                l.themeSelectToEdit,
                style: TextStyle(
                  color: t.textDisabled,
                  fontSize: t.fontSize(10),
                  letterSpacing: 2,
                ),
              ),
            ),
    );
  }

  Widget _buildList(ThemeNotifier themeNotifier, VisionTokens t) {
    final l = context.l;
    final allThemes = themeNotifier.allThemes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            VisionMetrics.space16,
            VisionMetrics.space16,
            VisionMetrics.space16,
            VisionMetrics.space8,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l.themeList,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: t.fontSize(10),
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ManagerIconButton(
                icon: Icons.add,
                color: t.textSecondary,
                onPressed: () => _createNewTheme(themeNotifier, t),
                tooltip: l.themeNew,
              ),
            ],
          ),
        ),
        Divider(height: 1, color: t.borderSubtle),
        Expanded(
          child: ListView.builder(
            itemCount: allThemes.length,
            itemBuilder: (context, index) {
              final theme = allThemes[index];
              final isActive = themeNotifier.activeThemeId == theme.id;
              return InkWell(
                onTap: () {
                  themeNotifier.setActiveTheme(theme.id);
                  setState(() {
                    _editingThemeId = theme.id;
                    _showingEditor = true;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: VisionMetrics.space16,
                    vertical: VisionMetrics.space12,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? t.accent.withValues(alpha: VisionMetrics.opacityHover)
                        : Colors.transparent,
                    border: Border(
                      left: BorderSide(
                        color: isActive ? t.accent : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              theme.name,
                              style: TextStyle(
                                color: isActive
                                    ? t.textPrimary
                                    : t.textSecondary,
                                fontSize: t.fontSize(11),
                                fontWeight: isActive
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: VisionMetrics.space8),
                            _buildColorStrip(theme, t),
                          ],
                        ),
                      ),
                      if (!theme.isBuiltIn)
                        ManagerIconButton(
                          icon: Icons.delete_outline,
                          tooltip: l.commonDelete,
                          onPressed: () => _showDeleteConfirm(
                            context,
                            themeNotifier,
                            theme,
                            t,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildColorStrip(AppThemeConfig theme, VisionTokens t) {
    final colors = [
      theme.background,
      theme.surfaceHigh,
      theme.textPrimary,
      theme.accent,
      theme.accentEdit,
    ];
    return Row(
      children: colors.map((c) {
        return Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(right: VisionMetrics.space4),
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(color: t.borderMedium),
          ),
        );
      }).toList(),
    );
  }

  /// Save / reset actions, shown in the editor header on every layout.
  List<Widget> _editorActions(
    ThemeNotifier themeNotifier,
    AppThemeConfig config,
    VisionTokens t,
  ) {
    final l = context.l;
    return [
      if (!config.isBuiltIn)
        TextButton(
          onPressed: () {
            if (themeNotifier.isPreviewing) {
              themeNotifier.commitPreview();
            }
          },
          child: Text(
            l.themeSave,
            style: TextStyle(
              color: t.accent,
              fontSize: t.fontSize(9),
              letterSpacing: 1,
            ),
          ),
        ),
      TextButton(
        onPressed: () {
          themeNotifier.clearPreview();
          themeNotifier.setActiveTheme(config.id);
        },
        child: Text(
          l.themeReset,
          style: TextStyle(
            color: t.textDisabled,
            fontSize: t.fontSize(9),
            letterSpacing: 1,
          ),
        ),
      ),
    ];
  }

  Widget _buildEditor(ThemeNotifier themeNotifier, VisionTokens t) {
    final l = context.l;
    final config = themeNotifier.activeConfig;

    return Column(
      children: [
        // Phones get this header (with a back button) from the shell.
        if (windowSizeClassOf(context) != WindowSizeClass.compact)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: VisionMetrics.space16,
              vertical: VisionMetrics.space8,
            ),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.borderSubtle)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    config.name,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: t.fontSize(11),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                ..._editorActions(themeNotifier, config, t),
              ],
            ),
          ),
        // Editor content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(VisionMetrics.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Preview
                _buildSectionHeader(l.themePreview, t),
                _buildPreviewCard(config, t),
                const SizedBox(height: VisionMetrics.space24),

                // Colors
                _buildSectionHeader(l.themeColors, t),
                _buildColorRow(
                  l.themeColorBackground,
                  config.background,
                  (c) => _updateConfig(
                    themeNotifier,
                    config.copyWith(background: c),
                  ),
                  t,
                ),
                _buildColorRow(
                  l.themeColorSurfaceHigh,
                  config.surfaceHigh,
                  (c) => _updateConfig(
                    themeNotifier,
                    config.copyWith(surfaceHigh: c),
                  ),
                  t,
                ),
                _buildColorRow(
                  l.themeColorSurfaceMid,
                  config.surfaceMid,
                  (c) => _updateConfig(
                    themeNotifier,
                    config.copyWith(surfaceMid: c),
                  ),
                  t,
                ),
                _buildColorRow(
                  l.themeColorTextPrimary,
                  config.textPrimary,
                  (c) => _updateConfig(
                    themeNotifier,
                    config.copyWith(textPrimary: c),
                  ),
                  t,
                ),
                _buildColorRow(
                  l.themeColorTextSecondary,
                  config.textSecondary,
                  (c) => _updateConfig(
                    themeNotifier,
                    config.copyWith(textSecondary: c),
                  ),
                  t,
                ),
                _buildColorRow(
                  l.themeColorTextTertiary,
                  config.textTertiary,
                  (c) => _updateConfig(
                    themeNotifier,
                    config.copyWith(textTertiary: c),
                  ),
                  t,
                ),
                _buildColorRow(
                  l.themeColorTextDisabled,
                  config.textDisabled,
                  (c) => _updateConfig(
                    themeNotifier,
                    config.copyWith(textDisabled: c),
                  ),
                  t,
                ),
                _buildColorRow(
                  l.themeColorTextMinimal,
                  config.textMinimal,
                  (c) => _updateConfig(
                    themeNotifier,
                    config.copyWith(textMinimal: c),
                  ),
                  t,
                ),
                _buildColorRow(
                  l.themeColorBorderStrong,
                  config.borderStrong,
                  (c) => _updateConfig(
                    themeNotifier,
                    config.copyWith(borderStrong: c),
                  ),
                  t,
                ),
                _buildColorRow(
                  l.themeColorBorderMedium,
                  config.borderMedium,
                  (c) => _updateConfig(
                    themeNotifier,
                    config.copyWith(borderMedium: c),
                  ),
                  t,
                ),
                _buildColorRow(
                  l.themeColorBorderSubtle,
                  config.borderSubtle,
                  (c) => _updateConfig(
                    themeNotifier,
                    config.copyWith(borderSubtle: c),
                  ),
                  t,
                ),
                _buildColorRow(
                  l.themeColorAccent,
                  config.accent,
                  (c) =>
                      _updateConfig(themeNotifier, config.copyWith(accent: c)),
                  t,
                ),
                _buildColorRow(
                  l.themeColorAccentEdit,
                  config.accentEdit,
                  (c) => _updateConfig(
                    themeNotifier,
                    config.copyWith(accentEdit: c),
                  ),
                  t,
                ),
                _buildColorRow(
                  l.themeColorAccentSuccess,
                  config.accentSuccess,
                  (c) => _updateConfig(
                    themeNotifier,
                    config.copyWith(accentSuccess: c),
                  ),
                  t,
                ),
                _buildColorRow(
                  l.themeColorAccentDanger,
                  config.accentDanger,
                  (c) => _updateConfig(
                    themeNotifier,
                    config.copyWith(accentDanger: c),
                  ),
                  t,
                ),
                _buildColorRow(
                  l.themeColorLogo,
                  config.logoColor,
                  (c) => _updateConfig(
                    themeNotifier,
                    config.copyWith(logoColor: c),
                  ),
                  t,
                ),
                _buildColorRow(
                  l.themeColorCascade,
                  config.accentCascade,
                  (c) => _updateConfig(
                    themeNotifier,
                    config.copyWith(accentCascade: c),
                  ),
                  t,
                ),
                _buildColorRow(
                  l.themeColorBgRemoval,
                  config.accentBgRemoval,
                  (c) => _updateConfig(
                    themeNotifier,
                    config.copyWith(accentBgRemoval: c),
                  ),
                  t,
                ),
                _buildColorRow(
                  l.themeColorUpscale,
                  config.accentUpscale,
                  (c) => _updateConfig(
                    themeNotifier,
                    config.copyWith(accentUpscale: c),
                  ),
                  t,
                ),
                const SizedBox(height: VisionMetrics.space24),

                // References
                _buildSectionHeader(l.themeReferences, t),
                _buildColorRow(
                  l.themeColorVibeTransfer,
                  config.accentVibeTransfer,
                  (c) => _updateConfig(
                    themeNotifier,
                    config.copyWith(accentVibeTransfer: c),
                  ),
                  t,
                ),
                _buildColorRow(
                  l.themeColorRefCharacter,
                  config.accentRefCharacter,
                  (c) => _updateConfig(
                    themeNotifier,
                    config.copyWith(accentRefCharacter: c),
                  ),
                  t,
                ),
                _buildColorRow(
                  l.themeColorRefStyle,
                  config.accentRefStyle,
                  (c) => _updateConfig(
                    themeNotifier,
                    config.copyWith(accentRefStyle: c),
                  ),
                  t,
                ),
                _buildColorRow(
                  l.themeColorRefCharStyle,
                  config.accentRefCharStyle,
                  (c) => _updateConfig(
                    themeNotifier,
                    config.copyWith(accentRefCharStyle: c),
                  ),
                  t,
                ),
                _buildColorRow(
                  l.themeColorFavorite,
                  config.accentFavorite,
                  (c) => _updateConfig(
                    themeNotifier,
                    config.copyWith(accentFavorite: c),
                  ),
                  t,
                ),
                _buildColorRow(
                  l.themeColorCharacter,
                  config.accentCharacter,
                  (c) => _updateConfig(
                    themeNotifier,
                    config.copyWith(accentCharacter: c),
                  ),
                  t,
                ),
                _buildColorRow(
                  l.themeColorPositive,
                  config.positiveIndicator,
                  (c) => _updateConfig(
                    themeNotifier,
                    config.copyWith(positiveIndicator: c),
                  ),
                  t,
                ),
                _buildColorRow(
                  l.themeColorNegative,
                  config.negativeIndicator,
                  (c) => _updateConfig(
                    themeNotifier,
                    config.copyWith(negativeIndicator: c),
                  ),
                  t,
                ),
                const SizedBox(height: VisionMetrics.space24),

                // Font
                _buildSectionHeader(l.themeFont, t),
                _buildFontSelector(themeNotifier, config, t),
                const SizedBox(height: VisionMetrics.space24),

                // Text scale
                _buildSectionHeader(l.themeTextScale, t),
                _buildScaleSlider(themeNotifier, config, t),
                const SizedBox(height: VisionMetrics.space16),

                // Header scale (multiplier on top of text scale)
                _buildSectionHeader(l.themeHeaderScale, t),
                _buildHeaderScaleSlider(themeNotifier, config, t),
                const SizedBox(height: VisionMetrics.space16),

                // Title scale (panel/section titles)
                _buildSectionHeader(l.themeTitleScale, t),
                _buildTitleScaleSlider(themeNotifier, config, t),
                const SizedBox(height: VisionMetrics.space16),

                // Button scale (action button labels)
                _buildSectionHeader(l.themeButtonScale, t),
                _buildButtonScaleSlider(themeNotifier, config, t),
                const SizedBox(height: VisionMetrics.space24),

                // Prompt input
                _buildSectionHeader(l.themePromptInput, t),
                _buildPromptFontSizeSlider(themeNotifier, config, t),
                const SizedBox(height: VisionMetrics.space12),
                _buildPromptMaxLinesSlider(themeNotifier, config, t),
                const SizedBox(height: VisionMetrics.space24),

                // Bright mode
                _buildSectionHeader(l.themeBrightMode, t),
                _buildBrightModeToggle(themeNotifier, config, t),
                const SizedBox(height: VisionMetrics.space24),

                // Panel layout
                _buildSectionHeader(l.themePanelLayout, t),
                const SizedBox(height: VisionMetrics.space4),
                Text(
                  l.themePanelLayoutDesc,
                  style: TextStyle(
                    color: t.textTertiary,
                    fontSize: t.fontSize(9),
                  ),
                ),
                const SizedBox(height: VisionMetrics.space8),
                _buildSectionOrderList(themeNotifier, t),
                const SizedBox(height: VisionMetrics.space24),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, VisionTokens t) {
    return SectionTitle(title, t: t, variant: SectionTitleVariant.compact);
  }

  Widget _buildPreviewCard(AppThemeConfig config, VisionTokens t) {
    final l = context.l;
    return Container(
      padding: const EdgeInsets.all(VisionMetrics.space16),
      decoration: BoxDecoration(
        color: config.background,
        borderRadius: BorderRadius.circular(VisionMetrics.radius8),
        border: Border.all(color: config.borderMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Surface card
          Container(
            padding: const EdgeInsets.all(VisionMetrics.space12),
            decoration: BoxDecoration(
              color: config.surfaceHigh,
              borderRadius: BorderRadius.circular(VisionMetrics.radius4),
              border: Border.all(color: config.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.themePreviewHeader,
                  style: TextStyle(
                    color: config.textPrimary,
                    fontSize: t.fontSize(11),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: VisionMetrics.space4),
                Text(
                  l.themePreviewSecondary,
                  style: TextStyle(
                    color: config.textSecondary,
                    fontSize: t.fontSize(10),
                  ),
                ),
                const SizedBox(height: VisionMetrics.space4),
                Text(
                  l.themePreviewHint,
                  style: TextStyle(
                    color: config.textTertiary,
                    fontSize: t.fontSize(9),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: VisionMetrics.space12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: VisionMetrics.space16,
                  vertical: VisionMetrics.space8,
                ),
                decoration: BoxDecoration(
                  color: config.accent,
                  borderRadius: BorderRadius.circular(VisionMetrics.radius4),
                ),
                child: Text(
                  l.themePreviewGenerate,
                  style: TextStyle(
                    color: config.background,
                    fontSize: t.fontSize(10),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: VisionMetrics.space8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: VisionMetrics.space12,
                  vertical: VisionMetrics.space8,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: config.accentEdit),
                  borderRadius: BorderRadius.circular(VisionMetrics.radius4),
                ),
                child: Text(
                  l.themePreviewEdit,
                  style: TextStyle(
                    color: config.accentEdit,
                    fontSize: t.fontSize(10),
                  ),
                ),
              ),
              const SizedBox(width: VisionMetrics.space8),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: config.accentSuccess.withValues(
                    alpha: VisionMetrics.opacityPressed,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check,
                  size: VisionMetrics.iconSmall,
                  color: config.accentSuccess,
                ),
              ),
              const SizedBox(width: VisionMetrics.space4),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: config.accentDanger.withValues(
                    alpha: VisionMetrics.opacityPressed,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close,
                  size: VisionMetrics.iconSmall,
                  color: config.accentDanger,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildColorRow(
    String label,
    Color color,
    Function(Color) onChanged,
    VisionTokens t,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: VisionMetrics.space4),
      child: InkWell(
        onTap: () async {
          final result = await ColorPickerDialog.show(
            context,
            initialColor: color,
            label: label,
          );
          if (result != null) onChanged(result);
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: context.hitSize),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(VisionMetrics.radius4),
                  border: Border.all(color: t.borderMedium),
                ),
              ),
              const SizedBox(width: VisionMetrics.space12),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: t.fontSize(9),
                    letterSpacing: 1,
                  ),
                ),
              ),
              Text(
                '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                style: TextStyle(
                  color: t.textDisabled,
                  fontSize: t.fontSize(9),
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFontSelector(
    ThemeNotifier themeNotifier,
    AppThemeConfig config,
    VisionTokens t,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _fontOptions.map((font) {
        final isSelected = config.fontFamily == font;
        return InkWell(
          onTap: () =>
              _updateConfig(themeNotifier, config.copyWith(fontFamily: font)),
          borderRadius: BorderRadius.circular(VisionMetrics.radius4),
          child: Container(
            constraints: BoxConstraints(minHeight: context.hitSize),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(
              horizontal: VisionMetrics.space12,
              vertical: VisionMetrics.space8,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? t.accent.withValues(alpha: VisionMetrics.opacityHover)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(VisionMetrics.radius4),
              border: Border.all(color: isSelected ? t.accent : t.borderSubtle),
            ),
            child: Text(
              font,
              style: TextStyle(
                fontFamily: GoogleFonts.getFont(font).fontFamily,
                color: isSelected ? t.accent : t.textSecondary,
                fontSize: t.fontSize(10),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildScaleSlider(
    ThemeNotifier themeNotifier,
    AppThemeConfig config,
    VisionTokens t,
  ) {
    final l = context.l;
    return Column(
      children: [
        Row(
          children: [
            Text(
              l.themeSmall,
              style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(8)),
            ),
            Expanded(
              child: Slider(
                value: config.fontScale,
                min: 0.75,
                max: 1.5,
                divisions: 15,
                activeColor: t.accent,
                inactiveColor: t.borderMedium,
                onChanged: (val) => _updateConfig(
                  themeNotifier,
                  config.copyWith(fontScale: val),
                ),
              ),
            ),
            Text(
              l.themeLarge,
              style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(8)),
            ),
          ],
        ),
        Text(
          '${(config.fontScale * 100).round()}%',
          style: TextStyle(color: t.textSecondary, fontSize: t.fontSize(10)),
        ),
      ],
    );
  }

  Widget _buildHeaderScaleSlider(
    ThemeNotifier themeNotifier,
    AppThemeConfig config,
    VisionTokens t,
  ) {
    return _multiplierSlider(
      value: config.headerScale,
      onChanged: (v) =>
          _updateConfig(themeNotifier, config.copyWith(headerScale: v)),
      t: t,
    );
  }

  Widget _buildTitleScaleSlider(
    ThemeNotifier themeNotifier,
    AppThemeConfig config,
    VisionTokens t,
  ) {
    return _multiplierSlider(
      value: config.titleScale,
      onChanged: (v) =>
          _updateConfig(themeNotifier, config.copyWith(titleScale: v)),
      t: t,
    );
  }

  Widget _buildButtonScaleSlider(
    ThemeNotifier themeNotifier,
    AppThemeConfig config,
    VisionTokens t,
  ) {
    return _multiplierSlider(
      value: config.buttonScale,
      onChanged: (v) =>
          _updateConfig(themeNotifier, config.copyWith(buttonScale: v)),
      t: t,
    );
  }

  Widget _multiplierSlider({
    required double value,
    required ValueChanged<double> onChanged,
    required VisionTokens t,
  }) {
    final l = context.l;
    return Column(
      children: [
        Row(
          children: [
            Text(
              l.themeSmall,
              style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(8)),
            ),
            Expanded(
              child: Slider(
                value: value,
                min: 0.75,
                max: 2.0,
                divisions: 25,
                activeColor: t.accent,
                inactiveColor: t.borderMedium,
                onChanged: onChanged,
              ),
            ),
            Text(
              l.themeLarge,
              style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(8)),
            ),
          ],
        ),
        Text(
          '${(value * 100).round()}%',
          style: TextStyle(color: t.textSecondary, fontSize: t.fontSize(10)),
        ),
      ],
    );
  }

  Widget _buildBrightModeToggle(
    ThemeNotifier themeNotifier,
    AppThemeConfig config,
    VisionTokens t,
  ) {
    final l = context.l;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.themeBrightText,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: t.fontSize(11),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: VisionMetrics.space4),
              Text(
                l.themeBrightDesc,
                style: TextStyle(
                  color: t.textTertiary,
                  fontSize: t.fontSize(9),
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: config.brightMode,
          onChanged: (val) =>
              _updateConfig(themeNotifier, config.copyWith(brightMode: val)),
          activeThumbColor: t.accent,
          activeTrackColor: t.textDisabled,
          inactiveThumbColor: t.textMinimal,
          inactiveTrackColor: t.borderSubtle,
        ),
      ],
    );
  }

  Widget _buildPromptFontSizeSlider(
    ThemeNotifier themeNotifier,
    AppThemeConfig config,
    VisionTokens t,
  ) {
    final l = context.l;
    return Column(
      children: [
        Row(
          children: [
            Text(
              l.themeFontSize,
              style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(8)),
            ),
            Expanded(
              child: Slider(
                value: config.promptFontSize,
                min: 8,
                max: 24,
                divisions: 16,
                activeColor: t.accent,
                inactiveColor: t.borderMedium,
                onChanged: (val) => _updateConfig(
                  themeNotifier,
                  config.copyWith(promptFontSize: val),
                ),
              ),
            ),
            Text(
              '${config.promptFontSize.round()}',
              style: TextStyle(
                color: t.textSecondary,
                fontSize: t.fontSize(10),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPromptMaxLinesSlider(
    ThemeNotifier themeNotifier,
    AppThemeConfig config,
    VisionTokens t,
  ) {
    final l = context.l;
    return Column(
      children: [
        Row(
          children: [
            Text(
              l.themeHeightLabel,
              style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(8)),
            ),
            Expanded(
              child: Slider(
                value: config.promptMaxLines.toDouble(),
                min: 1,
                max: 8,
                divisions: 7,
                activeColor: t.accent,
                inactiveColor: t.borderMedium,
                onChanged: (val) => _updateConfig(
                  themeNotifier,
                  config.copyWith(promptMaxLines: val.round()),
                ),
              ),
            ),
            Text(
              l.themeLines(config.promptMaxLines),
              style: TextStyle(
                color: t.textSecondary,
                fontSize: t.fontSize(10),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionOrderList(ThemeNotifier themeNotifier, VisionTokens t) {
    final l = context.l;
    final order = themeNotifier.sectionOrder;
    final displayNames = _sectionDisplayNames(l);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PrimaryScrollController.none(
          child: ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: order.length,
            onReorder: themeNotifier.reorderSections,
            proxyDecorator: (child, index, animation) {
              return Material(
                color: t.surfaceHigh,
                borderRadius: BorderRadius.circular(VisionMetrics.radius4),
                elevation: 4,
                child: child,
              );
            },
            itemBuilder: (context, index) {
              final id = order[index];
              final name = displayNames[id] ?? id;
              return Container(
                key: ValueKey(id),
                padding: const EdgeInsets.symmetric(
                  horizontal: VisionMetrics.space8,
                ),
                margin: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: t.borderSubtle.withValues(
                    alpha: VisionMetrics.opacityDisabled,
                  ),
                  borderRadius: BorderRadius.circular(VisionMetrics.radius4),
                ),
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: index,
                      child: SizedBox.square(
                        dimension: VisionMetrics.minHitTarget,
                        child: Icon(
                          Icons.drag_handle,
                          size: VisionMetrics.iconMedium,
                          color: t.textDisabled,
                        ),
                      ),
                    ),
                    const SizedBox(width: VisionMetrics.space12),
                    Expanded(
                      child: Text(
                        name,
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: t.fontSize(10),
                          letterSpacing: 1,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: t.textDisabled,
                        fontSize: t.fontSize(9),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: VisionMetrics.space8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: themeNotifier.resetSectionOrder,
            child: Text(
              l.themeReset,
              style: TextStyle(
                color: t.textDisabled,
                fontSize: t.fontSize(9),
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showDeleteConfirm(
    BuildContext context,
    ThemeNotifier themeNotifier,
    AppThemeConfig theme,
    VisionTokens t,
  ) async {
    final l = context.l;
    final confirm = await showConfirmDialog(
      context,
      title: l.themeDeleteTitle,
      message: l.themeDeleteConfirm(theme.name),
      confirmLabel: l.commonDelete,
      confirmColor: t.accentDanger,
    );
    if (confirm == true) {
      themeNotifier.deleteUserTheme(theme.id);
    }
  }

  void _updateConfig(ThemeNotifier themeNotifier, AppThemeConfig config) {
    if (config.isBuiltIn) {
      // For built-in themes, preview only (no save)
      themeNotifier.previewConfig(config);
    } else {
      // For user themes, preview live and allow save
      themeNotifier.previewConfig(config);
    }
  }

  Future<void> _createNewTheme(
    ThemeNotifier themeNotifier,
    VisionTokens t,
  ) async {
    final l = context.l;
    final name = await showTextInputDialog(
      context,
      title: l.themeNewTitle,
      confirmLabel: l.commonCreate,
      hintText: l.themeThemeName,
      initialValue: l.themeCustomTheme,
    );

    if (name != null) {
      try {
        final newTheme = await themeNotifier.saveAsUserTheme(
          name,
          themeNotifier.activeConfig,
        );
        if (!mounted) return;
        setState(() {
          _editingThemeId = newTheme.id;
          _showingEditor = true;
        });
      } catch (e) {
        if (!mounted) return;
        showErrorSnackBar(context, l.themeCreateFailed(e.toString()));
      }
    }
  }
}
