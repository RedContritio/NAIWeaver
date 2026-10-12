import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/theme/vision_metrics.dart';
import '../../../../core/widgets/section_title.dart';
import '../../../../core/widgets/ui/app_panel.dart';
import '../../../../core/widgets/vision_slider.dart';
import '../../../../core/utils/timestamp_utils.dart';
import '../../../../core/widgets/comparison_slider.dart';
import '../../../gallery/services/tool_result_saver.dart';
import '../../../generation/providers/generation_notifier.dart';
import '../../widgets/tool_config_bottom_sheet.dart';
import '../../widgets/tool_source_picker.dart';
import '../../widgets/tool_workspace.dart';
import '../models/augment_tool.dart';
import '../providers/director_tools_notifier.dart';
import 'tool_selector.dart';
import 'emotion_mood_picker.dart';

class DirectorToolsEditor extends StatefulWidget {
  const DirectorToolsEditor({super.key});

  @override
  State<DirectorToolsEditor> createState() => _DirectorToolsEditorState();
}

class _DirectorToolsEditorState extends State<DirectorToolsEditor> {
  final TextEditingController _promptController = TextEditingController();
  final _promptKey = GlobalKey();
  final _promptFocus = FocusNode();

  /// Result bytes last written by [_saveResult]; anything else is unsaved.
  Uint8List? _savedResult;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _promptFocus.addListener(_onPromptFocusChanged);
  }

  @override
  void dispose() {
    _promptFocus.removeListener(_onPromptFocusChanged);
    _promptFocus.dispose();
    _promptController.dispose();
    super.dispose();
  }

  void _onPromptFocusChanged() {
    if (_promptFocus.hasFocus) {
      Future.delayed(const Duration(milliseconds: 400), _scrollToPrompt);
    }
  }

  void _scrollToPrompt() {
    if (!mounted || !_promptFocus.hasFocus) return;
    final ctx = _promptKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.2,
    );
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<DirectorToolsNotifier>();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: notifier.hasSource
          ? _buildWorkspace(context, notifier)
          : _buildPicker(context, notifier),
    );
  }

  Widget _buildPicker(BuildContext context, DirectorToolsNotifier notifier) {
    final l = context.l;
    return ToolSourcePicker(
      icon: Icons.auto_fix_high,
      title: l.directorToolsTitle,
      description: l.directorToolsDesc,
      useCurrentLabel: l.directorToolsUseCurrent,
      useCurrentDescription: l.directorToolsUseCurrentDesc,
      promptImport: ToolSourcePromptImport.none,
      onSelected: (selection) => notifier.setSourceImage(selection.bytes),
    );
  }

  Widget _buildWorkspace(BuildContext context, DirectorToolsNotifier notifier) {
    final l = context.l;
    return ToolRunShortcut(
      onRun: notifier.isProcessing ? null : () => _process(notifier),
      child: ToolSettingsLayout(
        header: ToolWorkspaceHeader(
          onBack: () => _backToPicker(notifier),
          processIcon: Icons.auto_fix_high,
          processLabel: l.directorToolsProcess,
          processingLabel: l.directorToolsProcessing,
          isProcessing: notifier.isProcessing,
          onProcess: () => _process(notifier),
          hasResult: notifier.hasResult,
          showSave: _hasUnsavedResult(notifier),
          onSave: _saving ? null : () => _saveResult(notifier),
        ),
        body: _buildImageArea(context, notifier),
        settingsTooltip: l.directorToolsSettingsTooltip,
        settingsBuilder: (settingsContext) => _buildConfigPanel(
          settingsContext,
          settingsContext.watch<DirectorToolsNotifier>(),
        ),
      ),
    );
  }

  Widget _buildImageArea(BuildContext context, DirectorToolsNotifier notifier) {
    final t = context.t;
    final l = context.l;
    final error = notifier.error;

    return Stack(
      children: [
        if (notifier.hasResult)
          ComparisonSlider(
            beforeBytes: notifier.sourceImageBytes!,
            afterBytes: notifier.resultBytes!,
            beforeLabel: l.comparisonBefore,
            afterLabel: l.comparisonAfter,
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

  Widget _buildConfigPanel(
    BuildContext context,
    DirectorToolsNotifier notifier,
  ) {
    final t = context.t;
    final l = context.l;
    const compact = SectionTitleVariant.compact;
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(VisionMetrics.radius4),
      borderSide: BorderSide(color: t.borderMedium),
    );

    return Padding(
      padding: const EdgeInsets.all(VisionMetrics.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SectionTitle(l.directorToolsSelectTool, t: t, variant: compact),
          ToolSelector(
            selected: notifier.selectedTool,
            onSelected: notifier.selectTool,
          ),
          const SizedBox(height: VisionMetrics.space16),

          // Info text about current tool
          Text(
            '${notifier.sourceWidth} x ${notifier.sourceHeight}',
            style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(10)),
          ),
          const SizedBox(height: VisionMetrics.space12),

          // Defry slider
          if (notifier.selectedTool.hasDefry) ...[
            SectionTitle(l.directorToolsDefry, t: t, variant: compact),
            Row(
              children: [
                Expanded(
                  child: VisionSlider.subtle(
                    value: notifier.defry.toDouble(),
                    onChanged: (v) => notifier.setDefry(v.round()),
                    t: t,
                    min: 0,
                    max: 5,
                    divisions: 5,
                  ),
                ),
                SizedBox(
                  width: VisionMetrics.space24 + VisionMetrics.space8,
                  child: Text(
                    '${notifier.defry}',
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: t.fontSize(10),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            const SizedBox(height: VisionMetrics.space8),
          ],

          // Mood picker (emotion only)
          if (notifier.selectedTool == AugmentTool.emotion) ...[
            SectionTitle(l.directorToolsMood, t: t, variant: compact),
            EmotionMoodPicker(
              selected: notifier.selectedMood,
              onSelected: notifier.setMood,
            ),
            const SizedBox(height: VisionMetrics.space12),
          ],

          // Prompt field (colorize/emotion)
          if (notifier.selectedTool.hasPrompt) ...[
            SectionTitle(l.directorToolsPrompt, t: t, variant: compact),
            TextField(
              key: _promptKey,
              focusNode: _promptFocus,
              controller: _promptController,
              maxLines: 2,
              onTap: _scrollToPrompt,
              style: TextStyle(fontSize: t.fontSize(10), color: t.textPrimary),
              decoration: InputDecoration(
                hintText: l.directorToolsPromptHint,
                hintStyle: TextStyle(
                  color: t.hintText,
                  fontSize: t.fontSize(9),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: VisionMetrics.space12,
                  vertical: VisionMetrics.space8,
                ),
                filled: true,
                fillColor: t.borderSubtle,
                border: fieldBorder,
                enabledBorder: fieldBorder,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _process(DirectorToolsNotifier notifier) async {
    final gen = context.read<GenerationNotifier>();
    notifier.setPrompt(_promptController.text);
    await notifier.process();
    if (mounted && notifier.hasResult && gen.state.autoSaveImages) {
      await _saveResult(notifier);
    }
  }

  bool _hasUnsavedResult(DirectorToolsNotifier notifier) =>
      notifier.hasResult && !identical(notifier.resultBytes, _savedResult);

  Future<void> _backToPicker(DirectorToolsNotifier notifier) async {
    if (_hasUnsavedResult(notifier) &&
        !await confirmDiscardUnsavedResult(context)) {
      return;
    }
    notifier.clear();
  }

  Future<void> _saveResult(DirectorToolsNotifier notifier) async {
    final result = notifier.resultBytes;
    if (result == null || _saving) return;
    setState(() => _saving = true);
    final toolName = notifier.selectedTool.apiValue.replaceAll('-', '');
    final outcome = await saveToolResult(
      context,
      bytes: result,
      fileName: 'DT_${toolName}_${generateTimestamp()}.png',
      sourceBytes: notifier.sourceImageBytes,
      savedMessage: context.l.directorToolsSaved,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (outcome.succeeded) _savedResult = result;
    });
  }
}
