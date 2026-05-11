import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/services/text_gen_service.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_tokens.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/vision_slider.dart';
import '../providers/text_gen_notifier.dart';

/// The Text Generation tool panel (NovelAI text models).
///
/// A multiline input that the model *continues* (NAI text models don't follow
/// chat turns), a model picker, a collapsible Parameters section, Generate /
/// Cancel / Continue / Copy controls, a live-streaming output area, and a small
/// local history list.
class TextGenPanel extends StatefulWidget {
  const TextGenPanel({super.key});

  @override
  State<TextGenPanel> createState() => _TextGenPanelState();
}

class _TextGenPanelState extends State<TextGenPanel> {
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _stopController = TextEditingController();
  bool _paramsExpanded = false;
  bool _reasoningExpanded = false;
  bool _synced = false;

  @override
  void dispose() {
    _inputController.dispose();
    _modelController.dispose();
    _stopController.dispose();
    super.dispose();
  }

  void _syncFromNotifier(TextGenNotifier n) {
    if (_synced) return;
    _inputController.text = n.input;
    _modelController.text = n.model;
    _stopController.text = n.stopStringsRaw;
    _synced = true;
  }

  bool get _modelIsKnown => kKnownTextModels.contains(_modelController.text);

  @override
  Widget build(BuildContext context) {
    final n = context.watch<TextGenNotifier>();
    _syncFromNotifier(n);
    final mobile = isMobile(context);
    final t = context.t;

    final inputArea = _buildInputColumn(context, n, t);
    final outputArea = _buildOutputColumn(context, n, t);

    return Column(
      children: [
        _buildHeader(context, n, t),
        Expanded(
          child: mobile
              ? ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    inputArea,
                    const SizedBox(height: 16),
                    SizedBox(height: 320, child: outputArea),
                    const SizedBox(height: 16),
                    _buildHistory(context, n, t),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          inputArea,
                          const SizedBox(height: 16),
                          _buildHistory(context, n, t),
                        ],
                      ),
                    ),
                    VerticalDivider(width: 1, color: t.borderSubtle),
                    Expanded(flex: 1, child: outputArea),
                  ],
                ),
        ),
      ],
    );
  }

  // — Header: title + Generate/Cancel —
  Widget _buildHeader(BuildContext context, TextGenNotifier n, VisionTokens t) {
    final l = context.l;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: t.surfaceHigh,
        border: Border(bottom: BorderSide(color: t.borderSubtle)),
      ),
      child: Row(
        children: [
          Icon(Icons.notes, size: 16, color: t.textDisabled),
          const SizedBox(width: 8),
          Text(
            l.textGenTitle.toUpperCase(),
            style: TextStyle(
              color: t.secondaryText,
              fontSize: t.titleSize(11),
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
            ),
          ),
          const Spacer(),
          if (n.isGenerating)
            SizedBox(
              height: 32,
              child: ElevatedButton.icon(
                onPressed: () => n.cancel(),
                icon: const Icon(Icons.stop, size: 14),
                label: Text(l.textGenCancel),
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.accentDanger,
                  foregroundColor: t.background,
                  textStyle: TextStyle(
                      fontSize: t.fontSize(10),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                  elevation: 0,
                ),
              ),
            )
          else
            SizedBox(
              height: 32,
              child: ElevatedButton.icon(
                onPressed: () => _onGenerate(n),
                icon: const Icon(Icons.auto_awesome, size: 14),
                label: Text(l.textGenGenerate),
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.accent,
                  foregroundColor: t.background,
                  textStyle: TextStyle(
                      fontSize: t.fontSize(10),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                  elevation: 0,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // — Left column: input + model + parameters —
  Widget _buildInputColumn(
      BuildContext context, TextGenNotifier n, VisionTokens t) {
    final l = context.l;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(t, l.textGenInput),
        const SizedBox(height: 8),
        TextField(
          controller: _inputController,
          onChanged: n.setInput,
          maxLines: 8,
          minLines: 5,
          style: TextStyle(fontSize: t.fontSize(11), color: t.textPrimary),
          decoration: _fieldDecoration(t, l.textGenInputHint),
        ),
        const SizedBox(height: 6),
        Text(
          l.textGenInputNote,
          style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(9)),
        ),
        const SizedBox(height: 16),
        _label(t, l.textGenModel),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                initialValue: _modelIsKnown ? _modelController.text : '__custom__',
                isDense: true,
                style: TextStyle(fontSize: t.fontSize(10), color: t.textPrimary),
                dropdownColor: t.surfaceHigh,
                decoration: _fieldDecoration(t, ''),
                items: [
                  ...kKnownTextModels.map((m) => DropdownMenuItem(
                        value: m,
                        child: Text(m),
                      )),
                  DropdownMenuItem(
                    value: '__custom__',
                    child: Text(l.textGenModelCustom),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  if (v == '__custom__') {
                    setState(() {}); // reveal the free-text field
                    return;
                  }
                  _modelController.text = v;
                  n.setModel(v);
                  setState(() {});
                },
              ),
            ),
            if (!_modelIsKnown) ...[
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _modelController,
                  onChanged: n.setModel,
                  style:
                      TextStyle(fontSize: t.fontSize(10), color: t.textPrimary),
                  decoration: _fieldDecoration(t, kDefaultTextModel),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        _buildParametersSection(context, n, t),
      ],
    );
  }

  Widget _buildParametersSection(
      BuildContext context, TextGenNotifier n, VisionTokens t) {
    final l = context.l;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: _paramsExpanded,
        onExpansionChanged: (v) => setState(() => _paramsExpanded = v),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 4, bottom: 8),
        title: Text(
          l.textGenParameters.toUpperCase(),
          style: TextStyle(
            color: t.secondaryText,
            fontSize: t.fontSize(10),
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        children: [
          // Preset picker
          Row(
            children: [
              _label(t, l.textGenPreset),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: n.activePresetName,
                  isDense: true,
                  style:
                      TextStyle(fontSize: t.fontSize(10), color: t.textPrimary),
                  dropdownColor: t.surfaceHigh,
                  decoration: _fieldDecoration(t, ''),
                  items: TextGenParams.presetNames
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    n.loadPreset(v);
                    _stopController.text = n.stopStringsRaw;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SliderRow(
            label: l.textGenTemperature,
            value: n.params.temperature,
            min: 0.1,
            max: 2.5,
            divisions: 48,
            display: n.params.temperature.toStringAsFixed(2),
            onChanged: n.setTemperature,
            t: t,
          ),
          _IntSliderRow(
            label: l.textGenMaxLength,
            value: n.params.maxLength,
            min: 1,
            max: 600,
            onChanged: n.setMaxLength,
            t: t,
          ),
          _SliderRow(
            label: l.textGenTopP,
            value: n.params.topP,
            min: 0.0,
            max: 1.0,
            divisions: 100,
            display: n.params.topP.toStringAsFixed(2),
            onChanged: n.setTopP,
            t: t,
          ),
          _IntSliderRow(
            label: l.textGenTopK,
            value: n.params.topK,
            min: 0,
            max: 200,
            onChanged: n.setTopK,
            t: t,
          ),
          _SliderRow(
            label: l.textGenRepetitionPenalty,
            value: n.params.repetitionPenalty,
            min: 1.0,
            max: 3.0,
            divisions: 100,
            display: n.params.repetitionPenalty.toStringAsFixed(3),
            onChanged: n.setRepetitionPenalty,
            t: t,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _label(t, l.textGenPhraseRepPen),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: n.params.phraseRepPen,
                  isDense: true,
                  style:
                      TextStyle(fontSize: t.fontSize(10), color: t.textPrimary),
                  dropdownColor: t.surfaceHigh,
                  decoration: _fieldDecoration(t, ''),
                  items: kPhraseRepPenOptions
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) n.setPhraseRepPen(v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: n.params.generateUntilSentence,
            activeThumbColor: t.accent,
            title: Text(
              l.textGenGenerateUntilSentence,
              style: TextStyle(fontSize: t.fontSize(10), color: t.textPrimary),
            ),
            onChanged: n.setGenerateUntilSentence,
          ),
          if (isChatStyleModel(n.model)) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: n.params.enableThinking,
              activeThumbColor: t.accent,
              title: Text(
                l.textGenEnableThinking,
                style: TextStyle(fontSize: t.fontSize(10), color: t.textPrimary),
              ),
              subtitle: Text(
                l.textGenEnableThinkingNote,
                style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(9)),
              ),
              onChanged: n.setEnableThinking,
            ),
          ],
          const SizedBox(height: 8),
          _label(t, l.textGenStopStrings),
          const SizedBox(height: 6),
          Text(
            l.textGenStopStringsNote,
            style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(9)),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _stopController,
            onChanged: n.setStopStrings,
            maxLines: 3,
            minLines: 1,
            style: TextStyle(fontSize: t.fontSize(10), color: t.textPrimary),
            decoration: _fieldDecoration(t, l.textGenStopStringsHint),
          ),
        ],
      ),
    );
  }

  // — Right column: streaming output + actions —
  Widget _buildOutputColumn(
      BuildContext context, TextGenNotifier n, VisionTokens t) {
    final l = context.l;
    return Container(
      color: t.background,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _label(t, l.textGenOutput),
              if (n.isGenerating) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: t.accent),
                ),
              ],
              const Spacer(),
              IconButton(
                tooltip: l.textGenCopy,
                icon: Icon(Icons.copy, size: 14, color: t.textDisabled),
                onPressed: n.hasOutput
                    ? () {
                        Clipboard.setData(ClipboardData(text: n.output));
                        showAppSnackBar(context, l.textGenCopied);
                      }
                    : null,
              ),
              IconButton(
                tooltip: l.textGenContinue,
                icon: Icon(Icons.subdirectory_arrow_left,
                    size: 16, color: t.textDisabled),
                onPressed: (n.hasOutput && !n.isGenerating)
                    ? () {
                        n.appendOutputToInput();
                        _inputController.text = n.input;
                        _onGenerate(n);
                      }
                    : null,
              ),
              IconButton(
                tooltip: l.textGenClear,
                icon: Icon(Icons.clear, size: 14, color: t.textDisabled),
                onPressed: n.hasOutput ? () => n.clearOutput() : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (n.hasReasoning) ...[
            _buildReasoningSection(context, n, t),
            const SizedBox(height: 8),
          ],
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.surfaceHigh,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: t.borderSubtle),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  n.hasOutput
                      ? n.output
                      : (n.isGenerating ? '…' : l.textGenOutputEmpty),
                  style: TextStyle(
                    fontSize: t.fontSize(12),
                    height: 1.45,
                    color: n.hasOutput ? t.textPrimary : t.textMinimal,
                  ),
                ),
              ),
            ),
          ),
          if (n.lastError != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: t.accentDanger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: t.accentDanger.withValues(alpha: 0.4)),
              ),
              child: Text(
                n.lastError!,
                style:
                    TextStyle(color: t.accentDanger, fontSize: t.fontSize(10)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReasoningSection(
      BuildContext context, TextGenNotifier n, VisionTokens t) {
    final l = context.l;
    final reasoning = n.reasoning;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: t.surfaceMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () =>
                setState(() => _reasoningExpanded = !_reasoningExpanded),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.psychology_outlined,
                      size: 14, color: t.textMinimal),
                  const SizedBox(width: 8),
                  Text(
                    l.textGenReasoning.toUpperCase(),
                    style: TextStyle(
                      color: t.textMinimal,
                      fontSize: t.fontSize(9),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _reasoningExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 16,
                    color: t.textMinimal,
                  ),
                ],
              ),
            ),
          ),
          if (_reasoningExpanded)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: SingleChildScrollView(
                  child: SelectableText(
                    reasoning,
                    style: TextStyle(
                      color: t.textTertiary,
                      fontSize: t.fontSize(10),
                      height: 1.4,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHistory(
      BuildContext context, TextGenNotifier n, VisionTokens t) {
    final l = context.l;
    if (n.history.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(t, l.textGenHistory),
        const SizedBox(height: 8),
        ...n.history.take(10).map((e) {
          final preview = e.output.replaceAll('\n', ' ');
          final shown =
              preview.length > 80 ? '${preview.substring(0, 80)}…' : preview;
          return InkWell(
            onTap: () {
              n.restoreFromHistory(e);
              _inputController.text = n.input;
              _modelController.text = n.model;
              _stopController.text = n.stopStringsRaw;
              setState(() {});
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: t.surfaceHigh,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: t.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${e.model} · ${e.timestamp.hour.toString().padLeft(2, '0')}:${e.timestamp.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                        color: t.textMinimal,
                        fontSize: t.fontSize(8),
                        letterSpacing: 1),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    shown,
                    style: TextStyle(
                        color: t.textTertiary, fontSize: t.fontSize(10)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // — helpers —
  void _onGenerate(TextGenNotifier n) async {
    // Make sure the notifier has the latest field contents.
    n.setInput(_inputController.text);
    if (_modelController.text.trim().isNotEmpty) {
      n.setModel(_modelController.text);
    }
    n.setStopStrings(_stopController.text);
    await n.generate();
    if (mounted && n.lastError != null) {
      showErrorSnackBar(context, n.lastError!);
    }
  }

  Widget _label(VisionTokens t, String text) => Text(
        text.toUpperCase(),
        style: TextStyle(
          color: t.secondaryText,
          fontSize: t.fontSize(responsiveFont(context, 9, 11)),
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
        ),
      );

  InputDecoration _fieldDecoration(VisionTokens t, String hint) =>
      InputDecoration(
        hintText: hint.isEmpty ? null : hint,
        hintStyle: TextStyle(color: t.hintText, fontSize: t.fontSize(9)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: t.accent),
        ),
      );
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;
  final VisionTokens t;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
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
              label.toUpperCase(),
              style: TextStyle(
                color: t.secondaryText,
                fontSize: t.fontSize(9),
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            Text(display,
                style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(10))),
          ],
        ),
        VisionSlider.subtle(
          value: value.clamp(min, max),
          onChanged: onChanged,
          t: t,
          min: min,
          max: max,
          divisions: divisions,
        ),
      ],
    );
  }
}

class _IntSliderRow extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final VisionTokens t;

  const _IntSliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(min, max).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: t.secondaryText,
                fontSize: t.fontSize(9),
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            Text('$value',
                style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(10))),
          ],
        ),
        VisionSlider.subtle(
          value: v,
          onChanged: (d) => onChanged(d.round()),
          t: t,
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: (max - min).clamp(1, 1000),
        ),
      ],
    );
  }
}
