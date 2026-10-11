import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/utils/timestamp_utils.dart';
import '../../../../core/widgets/comparison_slider.dart';
import '../../../../core/widgets/vision_slider.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../gallery/services/tool_result_saver.dart';
import '../../../generation/providers/generation_notifier.dart';
import '../../widgets/tool_config_bottom_sheet.dart';
import '../../widgets/tool_source_picker.dart';
import '../providers/enhance_notifier.dart';

class EnhanceEditor extends StatefulWidget {
  const EnhanceEditor({super.key});

  @override
  State<EnhanceEditor> createState() => _EnhanceEditorState();
}

class _EnhanceEditorState extends State<EnhanceEditor> {
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _negativePromptController =
      TextEditingController();
  bool _initialized = false;

  /// Result bytes last written by [_saveResult]; anything else is unsaved.
  Uint8List? _savedResult;
  bool _saving = false;

  @override
  void dispose() {
    _promptController.dispose();
    _negativePromptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<EnhanceNotifier>();

    // Sync prompt/UC from main generation when first loading source
    if (!_initialized && notifier.hasSource) {
      final gen = context.read<GenerationNotifier>();
      if (_promptController.text.isEmpty) {
        _promptController.text = gen.promptController.text;
        notifier.setPrompt(gen.promptController.text);
      }
      if (notifier.negativePrompt == EnhanceNotifier.defaultNegativePrompt) {
        final mainUC = gen.negativePromptController.text;
        if (mainUC.isNotEmpty) {
          _negativePromptController.text = mainUC;
          notifier.setNegativePrompt(mainUC);
        } else {
          _negativePromptController.text = notifier.negativePrompt;
        }
      } else {
        _negativePromptController.text = notifier.negativePrompt;
      }
      _initialized = true;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: notifier.hasSource
          ? _buildWorkspace(context, notifier)
          : _buildPicker(context, notifier),
    );
  }

  Widget _buildPicker(BuildContext context, EnhanceNotifier notifier) {
    final l = context.l;
    return ToolSourcePicker(
      icon: Icons.hd,
      title: l.enhanceTitle,
      description: l.enhanceDesc,
      useCurrentLabel: l.enhanceUseCurrent,
      useCurrentDescription: l.enhanceUseCurrentDesc,
      promptImport: ToolSourcePromptImport.mainPromptForCurrentGeneration,
      onSelected: (selection) {
        notifier.setSourceImage(selection.bytes);
        if (selection.prompt != null) {
          _promptController.text = selection.prompt!;
        }
        _negativePromptController.text = notifier.negativePrompt;
        _initialized = true;
      },
    );
  }

  Widget _buildWorkspace(BuildContext context, EnhanceNotifier notifier) {
    final mobile = isMobile(context);

    Widget imageArea = _buildImageArea(context, notifier);

    return Column(
      children: [
        _buildHeader(context, notifier),
        Expanded(
          child: mobile
              ? imageArea
              : Row(
                  children: [
                    Expanded(flex: 3, child: imageArea),
                    SizedBox(
                      width: 300,
                      child: SingleChildScrollView(
                        child: _buildConfigPanel(context, notifier),
                      ),
                    ),
                  ],
                ),
        ),
        if (mobile)
          ToolSettingsDock(
            tooltip: context.l.enhanceSettingsTooltip,
            onPressed: () => showToolConfigBottomSheet(
              context: context,
              listenable: notifier,
              contentBuilder: (_) => _buildConfigPanel(context, notifier),
            ),
          ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, EnhanceNotifier notifier) {
    final t = context.t;
    final l = context.l;
    final mobile = isMobile(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: t.surfaceHigh,
        border: Border(bottom: BorderSide(color: t.borderSubtle)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, size: 16, color: t.textDisabled),
            onPressed: () => _backToPicker(notifier),
            tooltip: l.img2imgBackToPicker,
          ),
          const Spacer(),
          if (_hasUnsavedResult(notifier)) ...[
            if (mobile)
              SizedBox(
                height: 36,
                child: IconButton(
                  onPressed: _saving ? null : () => _saveResult(notifier),
                  icon: const Icon(Icons.save_alt, size: 14),
                  tooltip: l.commonSave,
                  style: IconButton.styleFrom(
                    backgroundColor: t.accentSuccess,
                    foregroundColor: t.background,
                  ),
                ),
              )
            else
              SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : () => _saveResult(notifier),
                  icon: const Icon(Icons.save_alt, size: 14),
                  label: Text(l.commonSave),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: t.accentSuccess,
                    foregroundColor: t.background,
                    textStyle: TextStyle(
                      fontSize: t.fontSize(10),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            const SizedBox(width: 8),
          ],
          if (mobile && notifier.hasResult)
            SizedBox(
              height: 36,
              child: IconButton(
                onPressed: notifier.isProcessing
                    ? null
                    : () => _process(notifier),
                icon: notifier.isProcessing
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: t.background,
                        ),
                      )
                    : const Icon(Icons.auto_awesome, size: 14),
                style: IconButton.styleFrom(
                  backgroundColor: t.accent,
                  foregroundColor: t.background,
                ),
              ),
            )
          else
            SizedBox(
              height: 36,
              child: ElevatedButton.icon(
                onPressed: notifier.isProcessing
                    ? null
                    : () => _process(notifier),
                icon: notifier.isProcessing
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: t.background,
                        ),
                      )
                    : const Icon(Icons.auto_awesome, size: 14),
                label: Text(
                  notifier.isProcessing
                      ? (notifier.status.isNotEmpty
                            ? notifier.status.toUpperCase()
                            : l.enhanceProcessing)
                      : l.enhanceProcess,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.accent,
                  foregroundColor: t.background,
                  textStyle: TextStyle(
                    fontSize: t.fontSize(10),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  elevation: 0,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImageArea(BuildContext context, EnhanceNotifier notifier) {
    final t = context.t;
    final loc = AppLocalizations.of(context);

    return Stack(
      children: [
        if (notifier.hasResult)
          ComparisonSlider(
            beforeBytes: notifier.sourceImageBytes!,
            afterBytes: notifier.resultBytes!,
            beforeLabel: loc.comparisonBefore.toUpperCase(),
            afterLabel: loc.comparisonAfter.toUpperCase(),
          )
        else
          Container(
            color: t.background,
            child: Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: Image.memory(
                  notifier.sourceImageBytes!,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ),
        if (notifier.error != null)
          Positioned(
            bottom: 8,
            left: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.accentDanger.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: t.accentDanger.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                notifier.error!,
                style: TextStyle(
                  color: t.accentDanger,
                  fontSize: t.fontSize(9),
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildConfigPanel(BuildContext context, EnhanceNotifier notifier) {
    final t = context.t;
    final l = context.l;
    final labelSize = responsiveFont(context, 9, 11);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Prompt
          Text(
            l.enhancePrompt,
            style: TextStyle(
              color: t.secondaryText,
              fontSize: t.fontSize(labelSize),
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _promptController,
            maxLines: 2,
            style: TextStyle(fontSize: t.fontSize(10), color: t.textPrimary),
            decoration: InputDecoration(
              hintText: l.img2imgPromptHint,
              hintStyle: TextStyle(color: t.hintText, fontSize: t.fontSize(9)),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              filled: true,
              fillColor: t.borderSubtle,
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
          const SizedBox(height: 12),

          // Negative prompt
          Text(
            l.enhanceNegative,
            style: TextStyle(
              color: t.secondaryText,
              fontSize: t.fontSize(labelSize),
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _negativePromptController,
            maxLines: 2,
            style: TextStyle(fontSize: t.fontSize(10), color: t.textPrimary),
            decoration: InputDecoration(
              hintText: l.img2imgNegativeHint,
              hintStyle: TextStyle(color: t.hintText, fontSize: t.fontSize(9)),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              filled: true,
              fillColor: t.borderSubtle,
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
          const SizedBox(height: 16),

          // Resolution scale
          Text(
            'RESOLUTION SCALE',
            style: TextStyle(
              color: t.secondaryText,
              fontSize: t.fontSize(labelSize),
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final scale in [1.0, 1.5])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(
                      '${scale}x',
                      style: TextStyle(
                        fontSize: t.fontSize(9),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    selected: notifier.config.scale == scale,
                    onSelected: (_) => notifier.setScale(scale),
                    backgroundColor: t.borderSubtle,
                    selectedColor: t.accent,
                    checkmarkColor: t.background,
                    labelStyle: TextStyle(
                      color: notifier.config.scale == scale
                          ? t.background
                          : t.textTertiary,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(2),
                    ),
                    side: BorderSide(
                      color: notifier.config.scale == scale
                          ? t.accent
                          : t.textMinimal,
                      width: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Strength slider
          _SliderRow(
            label: l.enhanceStrength,
            value: notifier.config.strength,
            onChanged: notifier.setStrength,
            t: t,
          ),
          const SizedBox(height: 8),

          // Noise slider
          _SliderRow(
            label: l.enhanceNoise,
            value: notifier.config.noise,
            onChanged: notifier.setNoise,
            t: t,
          ),
          const SizedBox(height: 16),

          // Resolution display
          Text(
            notifier.config.scale > 1.0
                ? '${notifier.sourceWidth}x${notifier.sourceHeight} → ${((notifier.sourceWidth * notifier.config.scale) / 64).round() * 64}x${((notifier.sourceHeight * notifier.config.scale) / 64).round() * 64}'
                : '${notifier.sourceWidth}x${notifier.sourceHeight}',
            style: TextStyle(
              color: t.textMinimal,
              fontSize: t.fontSize(labelSize),
            ),
          ),
        ],
      ),
    );
  }

  void _syncStylesAndCharacters(
    EnhanceNotifier notifier,
    GenerationNotifier gen,
  ) {
    final genState = gen.state;
    final styleResult = GenerationNotifier.resolveStyles(
      isStyleEnabled: genState.isStyleEnabled,
      activeStyleNames: genState.activeStyleNames,
      styles: genState.styles,
      furryMode: genState.furryMode,
    );
    notifier.setStyleData(
      promptPrefix: styleResult.prefix,
      promptSuffix: styleResult.suffix,
      styleNegativeContent: styleResult.negative,
    );
    notifier.setCharacterData(
      characters: genState.characters,
      interactions: genState.interactions,
      useCoords: genState.characters.isNotEmpty
          ? !genState.autoPositioning
          : false,
    );
  }

  Future<void> _process(EnhanceNotifier notifier) async {
    final gen = context.read<GenerationNotifier>();
    notifier.setPrompt(_promptController.text);
    notifier.setNegativePrompt(_negativePromptController.text);
    _syncStylesAndCharacters(notifier, gen);
    await notifier.enhance();
    if (mounted && notifier.hasResult && gen.state.autoSaveImages) {
      await _saveResult(notifier);
    }
  }

  bool _hasUnsavedResult(EnhanceNotifier notifier) =>
      notifier.hasResult && !identical(notifier.resultBytes, _savedResult);

  Future<void> _backToPicker(EnhanceNotifier notifier) async {
    if (_hasUnsavedResult(notifier) &&
        !await confirmDiscardUnsavedResult(context)) {
      return;
    }
    notifier.clear();
  }

  Future<void> _saveResult(EnhanceNotifier notifier) async {
    final result = notifier.resultBytes;
    if (result == null || _saving) return;
    setState(() => _saving = true);
    final outcome = await saveToolResult(
      context,
      bytes: result,
      fileName: 'ENH_${generateTimestamp()}.png',
      sourceBytes: notifier.sourceImageBytes,
      savedMessage: context.l.enhanceSaved,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (outcome.succeeded) _savedResult = result;
    });
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final dynamic t;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: t.secondaryText,
                fontSize: t.fontSize(responsiveFont(context, 9, 11)),
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            Text(
              value.toStringAsFixed(2),
              style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(10)),
            ),
          ],
        ),
        VisionSlider.subtle(
          value: value,
          onChanged: onChanged,
          t: t,
          min: 0.0,
          max: 1.0,
          divisions: 20,
        ),
      ],
    );
  }
}
