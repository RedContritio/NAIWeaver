import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_tokens.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/manager_list_tile.dart';
import '../../../core/widgets/manager_shell.dart';
import '../../../core/widgets/section_title.dart';
import '../../../core/widgets/ui/app_sheet.dart';
import '../../../core/widgets/ui/app_states.dart';
import '../../../core/widgets/ui/overlay_action_button.dart';
import '../../../core/widgets/vision_slider.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../generation/providers/generation_notifier.dart';
import '../../../core/services/tag_service.dart';
import '../providers/tag_library_notifier.dart';
import '../../../core/utils/tag_category_color.dart';
import 'tag_detail_sheet.dart';
import '../../../core/theme/vision_metrics.dart';

class TagLibraryManager extends StatelessWidget {
  const TagLibraryManager({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<TagLibraryNotifier>();
    final t = context.t;

    return Column(
      children: [
        _buildHeader(context, notifier, t),
        _buildFilters(context, notifier, t),
        Divider(height: 1, color: t.textMinimal),
        Expanded(child: _buildTagList(context, notifier, t)),
      ],
    );
  }

  Widget _buildHeader(
    BuildContext context,
    TagLibraryNotifier notifier,
    VisionTokens t,
  ) {
    final l = context.l;
    return Column(
      children: [
        ManagerHeader(
          title: l.tagLibTitle,
          actions: [
            ManagerIconButton(
              icon: Icons.settings,
              tooltip: l.tagLibPreviewSettings,
              onPressed: () => _showPreviewSettings(context, notifier),
            ),
            ManagerIconButton(
              icon: Icons.add,
              tooltip: l.tagLibAddTag,
              color: t.textPrimary,
              onPressed: () => _showAddTagDialog(context, notifier, t),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(
            VisionMetrics.space16,
            0,
            VisionMetrics.space16,
            VisionMetrics.space8,
          ),
          color: t.surfaceHigh,
          child: TextField(
            onChanged: notifier.setSearchQuery,
            style: TextStyle(color: t.textSecondary, fontSize: t.fontSize(11)),
            decoration: InputDecoration(
              hintText: l.tagLibSearchTags,
              hintStyle: TextStyle(
                color: t.borderMedium,
                fontSize: t.fontSize(9),
                letterSpacing: 2,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                vertical: VisionMetrics.space8,
              ),
              border: InputBorder.none,
              prefixIcon: Icon(
                Icons.search,
                size: VisionMetrics.iconSmall,
                color: t.borderMedium,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilters(
    BuildContext context,
    TagLibraryNotifier notifier,
    VisionTokens t,
  ) {
    final state = notifier.state;
    final categories = notifier.getCategories();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: VisionMetrics.space16,
        vertical: VisionMetrics.space8,
      ),
      color: t.surfaceMid,
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(
                  context: context,
                  label: context.l.tagLibAll,
                  isSelected:
                      state.selectedCategory == null &&
                      !state.showFavoritesOnly,
                  color: t.textPrimary,
                  onSelected: () {
                    if (state.showFavoritesOnly) notifier.toggleFavoritesOnly();
                    notifier.setCategory(null);
                  },
                  t: t,
                ),
                _buildFilterChip(
                  context: context,
                  label: context.l.tagLibFavorites,
                  isSelected: state.showFavoritesOnly,
                  color: t.accentDanger,
                  onSelected: () => notifier.toggleFavoritesOnly(),
                  t: t,
                ),
                _buildFilterChip(
                  context: context,
                  label: context.l.tagLibImages,
                  isSelected: state.showWithExamplesOnly,
                  color: t.accentEdit,
                  onSelected: () => notifier.toggleWithExamplesOnly(),
                  t: t,
                ),
                ...categories.map(
                  (cat) => _buildFilterChip(
                    context: context,
                    label: cat.toUpperCase(),
                    isSelected: state.selectedCategory == cat,
                    color: tagCategoryColor(t, cat),
                    onSelected: () => notifier.setCategory(cat),
                    t: t,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: VisionMetrics.space8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Text(
                  context.l.tagLibSort,
                  style: TextStyle(
                    color: t.textPrimary.withValues(
                      alpha: VisionMetrics.opacityPressed,
                    ),
                    fontSize: t.fontSize(8),
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(width: VisionMetrics.space8),
                _buildSortOption(
                  context,
                  notifier,
                  TagSort.countDesc,
                  context.l.tagLibSortCountDesc,
                  t,
                ),
                _buildSortOption(
                  context,
                  notifier,
                  TagSort.countAsc,
                  context.l.tagLibSortCountAsc,
                  t,
                ),
                _buildSortOption(
                  context,
                  notifier,
                  TagSort.alphaAsc,
                  context.l.tagLibSortAZ,
                  t,
                ),
                _buildSortOption(
                  context,
                  notifier,
                  TagSort.alphaDesc,
                  context.l.tagLibSortZA,
                  t,
                ),
                _buildSortOption(
                  context,
                  notifier,
                  TagSort.favoritesFirst,
                  context.l.tagLibSortFavsFirst,
                  t,
                ),
                const SizedBox(width: VisionMetrics.space16),
                Text(
                  context.l.tagLibTagCount(state.tags.length),
                  style: TextStyle(
                    color: t.textPrimary.withValues(
                      alpha: VisionMetrics.opacityPressed,
                    ),
                    fontSize: t.fontSize(8),
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required BuildContext context,
    required String label,
    required bool isSelected,
    required Color color,
    required VoidCallback onSelected,
    required VisionTokens t,
  }) {
    final activeColor = isSelected
        ? color
        : color.withValues(alpha: VisionMetrics.opacityPressed);
    return Padding(
      padding: const EdgeInsets.only(right: VisionMetrics.space8),
      child: InkWell(
        onTap: onSelected,
        child: Container(
          constraints: BoxConstraints(minHeight: context.hitSize),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: VisionMetrics.space8),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: VisionMetrics.opacityHover)
                : Colors.transparent,
            border: Border.all(
              color: isSelected
                  ? color.withValues(alpha: VisionMetrics.opacityDisabled)
                  : color.withValues(alpha: VisionMetrics.opacityHover),
            ),
            borderRadius: BorderRadius.circular(VisionMetrics.radius2),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: activeColor,
              fontSize: t.fontSize(8),
              letterSpacing: 1,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSortOption(
    BuildContext context,
    TagLibraryNotifier notifier,
    TagSort sort,
    String label,
    VisionTokens t,
  ) {
    final isSelected = notifier.state.sort == sort;
    return Padding(
      padding: const EdgeInsets.only(right: VisionMetrics.space12),
      child: InkWell(
        onTap: () => notifier.setSort(sort),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: context.hitSize),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? t.textPrimary : t.textDisabled,
                fontSize: t.fontSize(8),
                letterSpacing: 1,
                decoration: isSelected ? TextDecoration.underline : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTagList(
    BuildContext context,
    TagLibraryNotifier notifier,
    VisionTokens t,
  ) {
    final state = notifier.state;
    if (state.isLoading) {
      return const LoadingState();
    }

    final l = context.l;
    return ListView.builder(
      itemCount: state.tags.length,
      // Rows share one height, measured at the current font scale.
      prototypeItem: _TagRow(
        tag: DanbooruTag(tag: '', count: 0),
        color: t.textPrimary,
        onTapDetail: () {},
        onTapExample: () {},
        onToggleFavorite: () {},
        menuActions: const [],
      ),
      itemBuilder: (context, index) {
        final tag = state.tags[index];
        return _TagRow(
          tag: tag,
          color: tagCategoryColor(t, tag.typeName),
          onTapDetail: () => TagDetailSheet.show(context, tag),
          onTapExample: () => _showExamplesOverlay(context, tag),
          onToggleFavorite: () => notifier.toggleFavorite(tag),
          menuActions: [
            ManagerListAction(
              label: l.tagLibTestTag,
              icon: Icons.image_search,
              onSelected: () => _showQuickPreview(context, tag.tag),
            ),
            ManagerListAction(
              label: l.commonDelete,
              icon: Icons.delete_outline,
              destructive: true,
              onSelected: () => _confirmDelete(context, notifier, tag, t),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    TagLibraryNotifier notifier,
    dynamic tag,
    VisionTokens t,
  ) async {
    final l = context.l;
    final confirm = await showConfirmDialog(
      context,
      title: l.tagLibDeleteTag,
      message: l.tagLibRemoveConfirm(tag.tag),
      confirmLabel: l.commonDelete,
      confirmColor: t.accentDanger,
    );
    if (confirm == true) {
      notifier.deleteTag(tag);
    }
  }

  void _showQuickPreview(BuildContext context, String tag) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _QuickTagPreviewDialog(tag: tag),
    );
  }

  void _showPreviewSettings(BuildContext context, TagLibraryNotifier notifier) {
    showAppSheet<void>(
      context: context,
      builder: (context) => _TagPreviewSettingsPanel(notifier: notifier),
    );
  }

  void _showExamplesOverlay(BuildContext context, dynamic tag) {
    showDialog(
      context: context,
      builder: (context) => _TagExamplesOverlay(tag: tag),
    );
  }

  void _showAddTagDialog(
    BuildContext context,
    TagLibraryNotifier notifier,
    VisionTokens t,
  ) {
    showDialog<void>(
      context: context,
      builder: (_) => _AddTagDialog(notifier: notifier),
    );
  }
}

/// Add-tag form. It owns its controllers (released with the dialog) and
/// refuses a blank name instead of silently ignoring the press.
class _AddTagDialog extends StatefulWidget {
  const _AddTagDialog({required this.notifier});

  final TagLibraryNotifier notifier;

  @override
  State<_AddTagDialog> createState() => _AddTagDialogState();
}

class _AddTagDialogState extends State<_AddTagDialog> {
  final _nameController = TextEditingController();
  final _countController = TextEditingController(text: '0');
  String _category = 'general';
  String? _nameError;

  @override
  void dispose() {
    _nameController.dispose();
    _countController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = context.l.commonNameRequired);
      return;
    }
    widget.notifier.addTag(
      name,
      int.tryParse(_countController.text.trim()) ?? 0,
      _category,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    return AlertDialog(
      backgroundColor: t.surfaceHigh,
      title: Text(
        l.tagLibAddNewTag,
        style: TextStyle(
          fontSize: t.titleSize(10),
          letterSpacing: 2,
          color: t.textSecondary,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
            onSubmitted: (_) => _submit(),
            style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(13)),
            decoration: InputDecoration(
              hintText: l.tagLibTagName,
              hintStyle: TextStyle(
                color: t.textMinimal,
                fontSize: t.fontSize(9),
              ),
              errorText: _nameError,
            ),
          ),
          const SizedBox(height: VisionMetrics.space16),
          TextField(
            controller: _countController,
            keyboardType: TextInputType.number,
            style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(13)),
            decoration: InputDecoration(
              hintText: l.tagLibCount,
              hintStyle: TextStyle(
                color: t.textMinimal,
                fontSize: t.fontSize(9),
              ),
            ),
          ),
          const SizedBox(height: VisionMetrics.space16),
          DropdownButton<String>(
            value: _category,
            isExpanded: true,
            dropdownColor: t.background,
            style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(11)),
            items: ['general', 'character', 'copyright', 'meta', 'artist']
                .map(
                  (cat) => DropdownMenuItem(
                    value: cat,
                    child: Text(cat.toUpperCase()),
                  ),
                )
                .toList(),
            onChanged: (val) {
              if (val != null) setState(() => _category = val);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            l.commonCancel,
            style: TextStyle(color: t.textDisabled, fontSize: t.buttonSize(9)),
          ),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(
            l.tagLibAddTagBtn,
            style: TextStyle(color: t.textPrimary, fontSize: t.buttonSize(9)),
          ),
        ),
      ],
    );
  }
}

class _TagExamplesOverlay extends StatelessWidget {
  final dynamic tag;

  const _TagExamplesOverlay({required this.tag});

  @override
  Widget build(BuildContext context) {
    final notifier = context.read<TagLibraryNotifier>();
    final t = context.t;
    final color = tagCategoryColor(t, tag.typeName);

    return Dialog.fullscreen(
      backgroundColor: t.background.withValues(
        alpha: VisionMetrics.opacityOverlay,
      ),
      child: Column(
        children: [
          AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(
              tag.tag.toUpperCase(),
              style: TextStyle(
                color: color,
                fontSize: t.fontSize(12),
                letterSpacing: 4,
                fontWeight: FontWeight.w900,
              ),
            ),
            leading: IconButton(
              icon: Icon(Icons.close, color: t.textPrimary),
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(VisionMetrics.space24),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 400,
                mainAxisSpacing: 24,
                crossAxisSpacing: 24,
                childAspectRatio: 832 / 1216,
              ),
              itemCount: tag.examplePaths.length,
              itemBuilder: (context, index) {
                final path = tag.examplePaths[index];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: t.textMinimal),
                      ),
                      child: File(path).existsSync()
                          ? Image.file(File(path), fit: BoxFit.contain)
                          : Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: t.textMinimal,
                                size: 32,
                              ),
                            ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: OverlayActionButton(
                        icon: Icons.delete,
                        tooltip: context.l.tagLibDeleteExample,
                        color: t.accentDanger,
                        onPressed: () async {
                          final l = context.l;
                          final confirm = await showConfirmDialog(
                            context,
                            title: l.tagLibDeleteExample,
                            message: l.tagLibDeleteExampleConfirm,
                            confirmLabel: l.commonDelete,
                            confirmColor: t.accentDanger,
                          );
                          if (confirm == true) {
                            await notifier.deleteExample(tag.tag, path);
                            if (!context.mounted) return;
                            if (tag.examplePaths.length <= 1) {
                              Navigator.pop(context);
                            }
                          }
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class TagPreviewResponsiveLayout extends StatelessWidget {
  final Widget header;
  final Widget preview;
  final Widget footer;

  const TagPreviewResponsiveLayout({
    super.key,
    required this.header,
    required this.preview,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight = MediaQuery.sizeOf(context).height;
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : viewportHeight * 0.85;
        final dialogHeight = math.min(availableHeight, 640.0);
        final previewMaxHeight = (dialogHeight - 180).clamp(120.0, 450.0);

        // Sized by its content; the cap keeps tall previews scrollable.
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: dialogHeight),
          child: SizedBox(
            width: 400,
            child: Padding(
              padding: const EdgeInsets.all(VisionMetrics.space24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  header,
                  const SizedBox(height: VisionMetrics.space16),
                  Flexible(
                    child: SingleChildScrollView(
                      key: const ValueKey('quick-tag-preview-scroll-view'),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: 300,
                                maxHeight: previewMaxHeight,
                              ),
                              child: AspectRatio(
                                aspectRatio: 2 / 3,
                                child: preview,
                              ),
                            ),
                          ),
                          const SizedBox(height: VisionMetrics.space16),
                          footer,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _QuickTagPreviewDialog extends StatefulWidget {
  final String tag;

  const _QuickTagPreviewDialog({required this.tag});

  @override
  State<_QuickTagPreviewDialog> createState() => _QuickTagPreviewDialogState();
}

class _QuickTagPreviewDialogState extends State<_QuickTagPreviewDialog> {
  Uint8List? _imageBytes;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    final genNotifier = context.read<GenerationNotifier>();
    final libNotifier = context.read<TagLibraryNotifier>();
    final bytes = await genNotifier.generateQuickPreview(
      widget.tag,
      previewSettings: libNotifier.state.previewSettings,
    );

    if (mounted) {
      setState(() {
        _imageBytes = bytes;
        _isLoading = false;
        if (bytes == null) {
          _error = context.l.tagLibGenerationFailed;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;

    return Dialog(
      backgroundColor: t.surfaceHigh,
      child: TagPreviewResponsiveLayout(
        header: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                l.tagLibTesting(widget.tag.toUpperCase()),
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: t.fontSize(10),
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ManagerIconButton(
              icon: Icons.close,
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        preview: Container(
          decoration: BoxDecoration(
            color: t.background,
            border: Border.all(color: t.textMinimal),
          ),
          child: _isLoading
              ? LoadingState(label: l.tagLibGeneratingPreview)
              : _error != null
              ? ErrorState(message: _error!)
              : Image.memory(_imageBytes!, fit: BoxFit.contain),
        ),
        footer: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_imageBytes != null)
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () async {
                    await context.read<TagLibraryNotifier>().saveExample(
                      widget.tag,
                      _imageBytes!,
                    );
                    if (context.mounted) {
                      showAppSnackBar(context, context.l.tagLibExampleSaved);
                    }
                  },
                  icon: Icon(
                    Icons.save,
                    size: VisionMetrics.iconSmall,
                    color: t.accentSuccess,
                  ),
                  label: Text(
                    l.tagLibSaveAsExample,
                    style: TextStyle(
                      color: t.accentSuccess,
                      fontSize: t.fontSize(10),
                      letterSpacing: 2,
                    ),
                  ),
                  style: TextButton.styleFrom(backgroundColor: t.borderSubtle),
                ),
              ),
            const SizedBox(height: VisionMetrics.space16),
            Consumer<TagLibraryNotifier>(
              builder: (context, notifier, child) {
                final settings = notifier.state.previewSettings;
                return Text(
                  "P: ${settings.positivePrompt.toUpperCase()} | ${settings.width.toInt()}X${settings.height.toInt()} | STEPS: ${settings.steps} | SCALE: ${settings.scale}",
                  style: TextStyle(
                    color: t.textMinimal,
                    fontSize: t.fontSize(7),
                    letterSpacing: 1,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TagPreviewSettingsPanel extends StatefulWidget {
  final TagLibraryNotifier notifier;

  const _TagPreviewSettingsPanel({required this.notifier});

  @override
  State<_TagPreviewSettingsPanel> createState() =>
      _TagPreviewSettingsPanelState();
}

class _TagPreviewSettingsPanelState extends State<_TagPreviewSettingsPanel> {
  late TextEditingController _posController;
  late TextEditingController _negController;
  late TextEditingController _seedController;
  late TagPreviewSettings _current;

  @override
  void initState() {
    super.initState();
    _current = widget.notifier.state.previewSettings;
    _posController = TextEditingController(text: _current.positivePrompt);
    _negController = TextEditingController(text: _current.negativePrompt);
    _seedController = TextEditingController(
      text: _current.seed?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _posController.dispose();
    _negController.dispose();
    _seedController.dispose();
    super.dispose();
  }

  void _update(TagPreviewSettings next) {
    setState(() => _current = next);
    widget.notifier.updatePreviewSettings(next);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VisionMetrics.space24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(l.tagLibPreviewSettingsTitle, t: t),
          _buildTextField(l.tagLibPositivePromptBase, _posController, (val) {
            _update(_current.copyWith(positivePrompt: val));
          }, t),
          const SizedBox(height: VisionMetrics.space16),
          _buildTextField(
            l.tagLibNegativePrompt,
            _negController,
            (val) {
              _update(_current.copyWith(negativePrompt: val));
            },
            t,
            maxLines: 3,
          ),
          const SizedBox(height: VisionMetrics.space24),
          Row(
            children: [
              Expanded(
                child: _buildDropdown<String>(
                  l.tagLibSampler,
                  _current.sampler,
                  [
                    "k_euler_ancestral",
                    "k_euler",
                    "k_dpmpp_2s_ancestral",
                    "k_dpmpp_2m",
                    "k_dpmpp_sde",
                  ],
                  (val) => _update(_current.copyWith(sampler: val)),
                  t,
                ),
              ),
              const SizedBox(width: VisionMetrics.space16),
              Expanded(
                child: _buildNumberInput(
                  l.tagLibSteps,
                  _current.steps.toDouble(),
                  (val) => _update(_current.copyWith(steps: val.toInt())),
                  t: t,
                  min: 1,
                  max: 50,
                ),
              ),
            ],
          ),
          const SizedBox(height: VisionMetrics.space16),
          Row(
            children: [
              Expanded(
                child: _buildNumberInput(
                  l.tagLibWidth,
                  _current.width,
                  (val) => _update(_current.copyWith(width: val)),
                  t: t,
                  min: 64,
                  max: 2048,
                  step: 64,
                ),
              ),
              const SizedBox(width: VisionMetrics.space16),
              Expanded(
                child: _buildNumberInput(
                  l.tagLibHeight,
                  _current.height,
                  (val) => _update(_current.copyWith(height: val)),
                  t: t,
                  min: 64,
                  max: 2048,
                  step: 64,
                ),
              ),
            ],
          ),
          const SizedBox(height: VisionMetrics.space16),
          Row(
            children: [
              Expanded(
                child: _buildNumberInput(
                  l.tagLibScale,
                  _current.scale,
                  (val) => _update(_current.copyWith(scale: val)),
                  t: t,
                  min: 1,
                  max: 31,
                ),
              ),
              const SizedBox(width: VisionMetrics.space16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.tagLibSeed,
                      style: TextStyle(
                        color: t.textDisabled,
                        fontSize: t.fontSize(8),
                      ),
                    ),
                    const SizedBox(height: VisionMetrics.space4),
                    TextField(
                      onChanged: (val) {
                        final s = int.tryParse(val);
                        if (s == null) {
                          _update(_current.copyWith(clearSeed: true));
                        } else {
                          _update(_current.copyWith(seed: s));
                        }
                      },
                      controller: _seedController,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: t.fontSize(11),
                      ),
                      decoration: InputDecoration(
                        hintText: l.tagLibRandom,
                        hintStyle: TextStyle(
                          color: t.textMinimal,
                          fontSize: t.fontSize(9),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: VisionMetrics.space8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    Function(String) onChanged,
    VisionTokens t, {
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(8)),
        ),
        const SizedBox(height: VisionMetrics.space4),
        TextField(
          controller: controller,
          onChanged: onChanged,
          maxLines: maxLines,
          style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(11)),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              vertical: VisionMetrics.space8,
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: t.textMinimal),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNumberInput(
    String label,
    double value,
    Function(double) onChanged, {
    required VisionTokens t,
    double min = 0,
    double max = 100,
    double step = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "$label: ${value.toStringAsFixed(0)}",
          style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(8)),
        ),
        VisionSlider(
          value: value.clamp(min, max),
          onChanged: onChanged,
          min: min,
          max: max,
          divisions: ((max - min) / step).toInt(),
          activeColor: t.textPrimary,
          inactiveColor: t.textMinimal,
          thumbColor: t.textPrimary,
          thumbRadius: 4,
          overlayRadius: 10,
          trackHeight: 1,
        ),
      ],
    );
  }

  Widget _buildDropdown<T>(
    String label,
    T value,
    List<T> items,
    Function(T?) onChanged,
    VisionTokens t,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(8)),
        ),
        DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: t.background,
          underline: Container(height: 1, color: t.textMinimal),
          icon: Icon(
            Icons.arrow_drop_down,
            size: VisionMetrics.iconSmall,
            color: t.textDisabled,
          ),
          style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(11)),
          items: items
              .map(
                (i) => DropdownMenuItem(
                  value: i,
                  child: Text(i.toString().toUpperCase()),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Tag row: tap opens the details; preview and delete sit in the row menu.
class _TagRow extends StatelessWidget {
  final DanbooruTag tag;
  final Color color;
  final VoidCallback onTapDetail;
  final VoidCallback onTapExample;
  final VoidCallback onToggleFavorite;
  final List<ManagerListAction> menuActions;

  const _TagRow({
    required this.tag,
    required this.color,
    required this.onTapDetail,
    required this.onTapExample,
    required this.onToggleFavorite,
    required this.menuActions,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    final example = tag.examplePaths.isEmpty
        ? null
        : File(tag.examplePaths.first);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.textMinimal)),
      ),
      child: ManagerListTile(
        title: tag.tag,
        titleStyle: TextStyle(
          color: color,
          fontFamily: 'monospace',
          letterSpacing: 0,
        ),
        subtitle:
            '${tag.typeName.toUpperCase()}  ·  ${NumberFormat.compact().format(tag.count)}',
        subtitleStyle: TextStyle(
          color: color.withValues(alpha: VisionMetrics.opacityScrim),
        ),
        leading: SizedBox.square(
          dimension: kManagerTouchTarget,
          child: example == null
              ? null
              : InkResponse(
                  onTap: onTapExample,
                  child: Center(
                    child: Container(
                      width: VisionMetrics.iconLarge,
                      height: VisionMetrics.iconLarge,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color.withValues(
                            alpha: VisionMetrics.opacityScrim,
                          ),
                        ),
                        image: example.existsSync()
                            ? DecorationImage(
                                image: FileImage(example),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
        ),
        onTap: onTapDetail,
        inlineActions: [
          ManagerIconButton(
            icon: tag.isFavorite ? Icons.favorite : Icons.favorite_border,
            tooltip: tag.isFavorite
                ? l.commonRemoveFavorite
                : l.commonAddFavorite,
            color: tag.isFavorite ? color : t.textDisabled,
            onPressed: onToggleFavorite,
          ),
        ],
        menuActions: menuActions,
      ),
    );
  }
}
