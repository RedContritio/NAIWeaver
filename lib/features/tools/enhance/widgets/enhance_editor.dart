import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/theme/vision_metrics.dart';
import '../../../../core/theme/vision_tokens.dart';
import '../../../../core/utils/timestamp_utils.dart';
import '../../../../core/widgets/comparison_slider.dart';
import '../../../../core/widgets/section_title.dart';
import '../../../../core/widgets/ui/app_panel.dart';
import '../../../../core/widgets/ui/app_tabs.dart';
import '../../../../core/widgets/vision_slider.dart';
import '../../../gallery/services/tool_result_saver.dart';
import '../../../generation/providers/generation_notifier.dart';
import '../../widgets/tool_config_bottom_sheet.dart';
import '../../widgets/tool_source_picker.dart';
import '../../widgets/tool_workspace.dart';
import '../providers/enhance_notifier.dart';

/// Resolution scales the enhance request supports.
const _scales = [1.0, 1.5];

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
    final l = context.l;
    return ToolRunShortcut(
      onRun: notifier.isProcessing ? null : () => _process(notifier),
      child: ToolSettingsLayout(
        header: ToolWorkspaceHeader(
          onBack: () => _backToPicker(notifier),
          processIcon: Icons.auto_awesome,
          processLabel: l.enhanceProcess,
          processingLabel: l.enhanceProcessing,
          isProcessing: notifier.isProcessing,
          onProcess: () => _process(notifier),
          hasResult: notifier.hasResult,
          showSave: _hasUnsavedResult(notifier),
          onSave: _saving ? null : () => _saveResult(notifier),
        ),
        body: _buildImageArea(context, notifier),
        settingsTooltip: l.enhanceSettingsTooltip,
        settingsBuilder: (settingsContext) => _buildConfigPanel(
          settingsContext,
          settingsContext.watch<EnhanceNotifier>(),
        ),
      ),
    );
  }

  Widget _buildImageArea(BuildContext context, EnhanceNotifier notifier) {
    final t = context.t;
    final l = context.l;
    final error = notifier.error;

    return Stack(
      children: [
        if (notifier.hasResult)
          ComparisonSlider(
            beforeBytes: notifier.sourceImageBytes!,
            afterBytes: notifier.resultBytes!,
            beforeLabel: l.comparisonBefore.toUpperCase(),
            afterLabel: l.comparisonAfter.toUpperCase(),
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
        if (error != null)
          Positioned(
            bottom: VisionMetrics.space8,
            left: VisionMetrics.space8,
            right: VisionMetrics.space8,
            child: ErrorBanner(message: toolErrorMessage(l, error)),
          ),
      ],
    );
  }

  Widget _promptField({
    required VisionTokens t,
    required TextEditingController controller,
    required String hint,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(VisionMetrics.radius4),
      borderSide: BorderSide(color: t.borderMedium),
    );
    return TextField(
      controller: controller,
      maxLines: 2,
      style: TextStyle(fontSize: t.fontSize(10), color: t.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: t.hintText, fontSize: t.fontSize(9)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: VisionMetrics.space12,
          vertical: VisionMetrics.space8,
        ),
        filled: true,
        fillColor: t.borderSubtle,
        border: border,
        enabledBorder: border,
      ),
    );
  }

  Widget _buildConfigPanel(BuildContext context, EnhanceNotifier notifier) {
    final t = context.t;
    final l = context.l;
    const compact = SectionTitleVariant.compact;
    final config = notifier.config;
    final scaledWidth =
        ((notifier.sourceWidth * config.scale) / 64).round() * 64;
    final scaledHeight =
        ((notifier.sourceHeight * config.scale) / 64).round() * 64;

    return Padding(
      padding: const EdgeInsets.all(VisionMetrics.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SectionTitle(l.enhancePrompt, t: t, variant: compact),
          _promptField(
            t: t,
            controller: _promptController,
            hint: l.img2imgPromptHint,
          ),
          const SizedBox(height: VisionMetrics.space12),

          SectionTitle(l.enhanceNegative, t: t, variant: compact),
          _promptField(
            t: t,
            controller: _negativePromptController,
            hint: l.img2imgNegativeHint,
          ),
          const SizedBox(height: VisionMetrics.space16),

          SectionTitle(l.enhanceResolutionScale, t: t, variant: compact),
          AppSegmented<double>(
            options: [
              for (final scale in _scales)
                AppOption(value: scale, label: '${scale}x'),
            ],
            selected: config.scale,
            onChanged: notifier.setScale,
          ),
          const SizedBox(height: VisionMetrics.space16),

          _SliderRow(
            label: l.enhanceStrength,
            value: config.strength,
            onChanged: notifier.setStrength,
            t: t,
          ),
          const SizedBox(height: VisionMetrics.space8),

          _SliderRow(
            label: l.enhanceNoise,
            value: config.noise,
            onChanged: notifier.setNoise,
            t: t,
          ),
          const SizedBox(height: VisionMetrics.space16),

          Text(
            config.scale > 1.0
                ? '${notifier.sourceWidth}x${notifier.sourceHeight} → ${scaledWidth}x$scaledHeight'
                : '${notifier.sourceWidth}x${notifier.sourceHeight}',
            style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(10)),
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
  final VisionTokens t;

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
        SectionTitle(
          label,
          t: t,
          variant: SectionTitleVariant.compact,
          trailing: Text(
            value.toStringAsFixed(2),
            style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(10)),
          ),
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
