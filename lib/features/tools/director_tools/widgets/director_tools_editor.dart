import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/widgets/vision_slider.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/utils/timestamp_utils.dart';
import '../../../../core/widgets/comparison_slider.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../gallery/services/tool_result_saver.dart';
import '../../../generation/providers/generation_notifier.dart';
import '../../widgets/tool_config_bottom_sheet.dart';
import '../../widgets/tool_source_picker.dart';
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
            tooltip: context.l.directorToolsSettingsTooltip,
            onPressed: () => showToolConfigBottomSheet(
              context: context,
              contentBuilder: (sheetContext) => _buildConfigPanel(
                sheetContext,
                sheetContext.watch<DirectorToolsNotifier>(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, DirectorToolsNotifier notifier) {
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
                    : const Icon(Icons.auto_fix_high, size: 14),
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
                    : const Icon(Icons.auto_fix_high, size: 14),
                label: Text(
                  notifier.isProcessing
                      ? l.directorToolsProcessing
                      : l.directorToolsProcess,
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

  Widget _buildImageArea(BuildContext context, DirectorToolsNotifier notifier) {
    final t = context.t;
    final l = AppLocalizations.of(context);

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
        // Error overlay
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

  Widget _buildConfigPanel(
    BuildContext context,
    DirectorToolsNotifier notifier,
  ) {
    final t = context.t;
    final l = context.l;
    final labelSize = responsiveFont(context, 9, 11);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.directorToolsSelectTool,
            style: TextStyle(
              color: t.secondaryText,
              fontSize: t.fontSize(labelSize),
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          ToolSelector(
            selected: notifier.selectedTool,
            onSelected: notifier.selectTool,
          ),
          const SizedBox(height: 16),

          // Info text about current tool
          Text(
            '${notifier.sourceWidth} x ${notifier.sourceHeight}',
            style: TextStyle(
              color: t.textMinimal,
              fontSize: t.fontSize(labelSize),
            ),
          ),
          const SizedBox(height: 12),

          // Defry slider
          if (notifier.selectedTool.hasDefry) ...[
            Text(
              l.directorToolsDefry,
              style: TextStyle(
                color: t.secondaryText,
                fontSize: t.fontSize(labelSize),
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
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
                  width: 30,
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
            const SizedBox(height: 8),
          ],

          // Mood picker (emotion only)
          if (notifier.selectedTool == AugmentTool.emotion) ...[
            Text(
              l.directorToolsMood,
              style: TextStyle(
                color: t.secondaryText,
                fontSize: t.fontSize(labelSize),
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            EmotionMoodPicker(
              selected: notifier.selectedMood,
              onSelected: notifier.setMood,
            ),
            const SizedBox(height: 12),
          ],

          // Prompt field (colorize/emotion)
          if (notifier.selectedTool.hasPrompt) ...[
            Text(
              l.directorToolsPrompt,
              style: TextStyle(
                color: t.secondaryText,
                fontSize: t.fontSize(labelSize),
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
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
