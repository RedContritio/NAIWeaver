import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/services/path_service.dart';
import '../../../core/services/reference_library_service.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/manager_list_tile.dart';
import '../../../core/widgets/manager_shell.dart';
import '../../../core/widgets/text_input_dialog.dart';

/// Body of a Tools → References tab, shared by precise references and vibes:
/// the current entries ([A]) with an add button, and the saved library ([S])
/// with load, delete and reorder.
class ReferenceLibraryManager<A, S> extends StatefulWidget {
  const ReferenceLibraryManager({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.countLabel,
    required this.onClearAll,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyDescription,
    required this.addLabel,
    required this.onAdd,
    required this.isProcessing,
    required this.slot,
    required this.saveTitle,
    required this.toSaved,
    required this.onLoadSaved,
    required this.savedName,
    required this.savedImage,
    required this.savedSummary,
    required this.accent,
    this.addDisabledReason,
  });

  static const addButtonKey = ValueKey<String>('reference-manager-add');
  static const disabledReasonKey = ValueKey<String>('reference-manager-add-disabled');

  final List<A> items;

  /// Builds the card of a current entry; `onSave` stores it in the library.
  final Widget Function(BuildContext context, A item, VoidCallback onSave) itemBuilder;
  final String countLabel;
  final VoidCallback? onClearAll;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyDescription;
  final String addLabel;
  final Future<void> Function() onAdd;
  final bool isProcessing;

  /// When set, adding is disabled and this explains why.
  final String? addDisabledReason;

  final ReferenceLibrarySlot<S> slot;
  final String saveTitle;
  final S Function(A item, String name) toSaved;
  final Future<void> Function(S saved) onLoadSaved;
  final String Function(S saved) savedName;
  final Uint8List Function(S saved) savedImage;
  final String Function(S saved) savedSummary;
  final Color accent;

  @override
  State<ReferenceLibraryManager<A, S>> createState() =>
      _ReferenceLibraryManagerState<A, S>();
}

class _ReferenceLibraryManagerState<A, S>
    extends State<ReferenceLibraryManager<A, S>> {
  List<S> _saved = const [];

  String get _libraryPath => context.read<PathService>().referenceLibraryFilePath;

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    final library = await ReferenceLibraryService.load(_libraryPath);
    if (mounted) setState(() => _saved = widget.slot.read(library));
  }

  /// Applies [change] to the stored list and mirrors the result. Returns
  /// false, after saying so, when the library could not be written.
  Future<bool> _write(List<S> Function(List<S> entries) change) async {
    final library = await ReferenceLibraryService.update(
      _libraryPath,
      (library) => widget.slot.write(library, change(widget.slot.read(library))),
    );
    if (!mounted) return library != null;
    if (library == null) {
      showErrorSnackBar(context, context.l.refLibrarySaveFailed);
      return false;
    }
    setState(() => _saved = widget.slot.read(library));
    return true;
  }

  Future<void> _saveToLibrary(A item) async {
    final l = context.l;
    final name = await showTextInputDialog(
      context,
      title: widget.saveTitle,
      confirmLabel: l.commonSave,
      hintText: l.refNameHint,
    );
    if (name == null || !mounted) return;
    final entry = widget.toSaved(item, name);
    if (await _write((entries) => [...entries, entry]) && mounted) {
      showAppSnackBar(context, l.refLibrarySaved);
    }
  }

  Future<void> _deleteSaved(int index) =>
      _write((entries) => [...entries]..removeAt(index));

  /// [newIndex] already accounts for the removal at [oldIndex].
  Future<void> _reorderSaved(int oldIndex, int newIndex) async {
    List<S> move(List<S> entries) {
      final reordered = [...entries];
      reordered.insert(newIndex, reordered.removeAt(oldIndex));
      return reordered;
    }

    final previous = _saved;
    setState(() => _saved = move(_saved));
    if (!await _write(move) && mounted) setState(() => _saved = previous);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    final empty = widget.items.isEmpty && _saved.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ManagerCountToolbar(
          countLabel: widget.countLabel,
          clearLabel: l.refClearAll,
          onClear: widget.onClearAll,
          countStyle: TextStyle(
            color: t.textDisabled,
            fontSize: t.fontSize(9),
            letterSpacing: 1,
          ),
          clearStyle: TextStyle(
            color: t.accentDanger,
            fontSize: t.fontSize(9),
            letterSpacing: 1,
            fontWeight: FontWeight.bold,
          ),
        ),
        Divider(height: 1, color: t.textMinimal),
        Expanded(child: empty ? _buildEmptyState() : _buildList()),
      ],
    );
  }

  Widget _buildEmptyState() {
    final t = context.t;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.emptyIcon, size: 48, color: t.textMinimal),
            const SizedBox(height: 16),
            Text(
              widget.emptyTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.textDisabled,
                fontSize: t.fontSize(10),
                letterSpacing: 2,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.emptyDescription,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.textMinimal,
                fontSize: t.fontSize(11),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            _buildAddButton(prominent: true),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton({required bool prominent}) {
    final t = context.t;
    final reason = widget.addDisabledReason;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton.icon(
          key: ReferenceLibraryManager.addButtonKey,
          onPressed: reason == null && !widget.isProcessing ? widget.onAdd : null,
          icon: const Icon(Icons.add_photo_alternate, size: 14),
          label: Text(
            widget.addLabel,
            style: TextStyle(
              fontSize: t.fontSize(9),
              letterSpacing: 1,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: prominent ? t.accent : t.textMinimal,
            foregroundColor: prominent ? t.background : t.textSecondary,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            elevation: 0,
          ),
        ),
        if (reason != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              reason,
              key: ReferenceLibraryManager.disabledReasonKey,
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textTertiary, fontSize: t.fontSize(9)),
            ),
          ),
      ],
    );
  }

  Widget _buildList() {
    final t = context.t;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final item in widget.items)
          widget.itemBuilder(context, item, () => _saveToLibrary(item)),
        const SizedBox(height: 4),
        Center(child: _buildAddButton(prominent: false)),
        if (_saved.isNotEmpty) ...[
          const SizedBox(height: 24),
          Divider(height: 1, color: t.textMinimal),
          const SizedBox(height: 16),
          Text(
            context.l.refSavedSection,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: t.fontSize(10),
              letterSpacing: 3,
              color: t.textDisabled,
            ),
          ),
          const SizedBox(height: 12),
          PrimaryScrollController.none(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _saved.length,
              onReorderItem: _reorderSaved,
              proxyDecorator: (child, index, animation) => Material(
                color: Colors.transparent,
                elevation: 4,
                child: child,
              ),
              itemBuilder: (context, index) {
                final saved = _saved[index];
                return _SavedEntryTile(
                  key: ObjectKey(saved),
                  index: index,
                  name: widget.savedName(saved),
                  image: widget.savedImage(saved),
                  summary: widget.savedSummary(saved),
                  accent: widget.accent,
                  onLoad: () => widget.onLoadSaved(saved),
                  onDelete: () => _deleteSaved(index),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _SavedEntryTile extends StatelessWidget {
  const _SavedEntryTile({
    super.key,
    required this.index,
    required this.name,
    required this.image,
    required this.summary,
    required this.accent,
    required this.onLoad,
    required this.onDelete,
  });

  final int index;
  final String name;
  final Uint8List image;
  final String summary;
  final Color accent;
  final VoidCallback onLoad;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    final thumbSize = isMobile(context) ? 48.0 : 56.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(0, 6, 4, 6),
      decoration: BoxDecoration(
        color: t.borderSubtle,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: t.textMinimal, width: 0.5),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: SizedBox.square(
              dimension: kManagerTouchTarget,
              child: Icon(Icons.drag_handle, size: 16, color: t.textDisabled),
            ),
          ),
          Container(
            width: thumbSize,
            height: thumbSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: accent.withValues(alpha: 0.5), width: 0.5),
              image: DecorationImage(
                image: MemoryImage(image),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: t.fontSize(10),
                    fontWeight: FontWeight.bold,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: t.fontSize(8),
                    color: t.textTertiary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          ManagerIconButton(
            icon: Icons.add_circle_outline,
            tooltip: l.refLoadSaved,
            color: accent,
            onPressed: onLoad,
          ),
          ManagerIconButton(
            icon: Icons.delete_outline,
            tooltip: l.commonDelete,
            color: t.accentDanger,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
