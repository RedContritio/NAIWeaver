import 'dart:convert';
import 'dart:io';
import '../../../core/utils/file_picker_helper.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/services/path_service.dart';
import '../../../core/services/reference_library_service.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/utils/responsive.dart';
import '../models/director_reference.dart';
import '../providers/director_ref_notifier.dart';
import 'director_ref_chip.dart';
import 'director_ref_editor_sheet.dart';

class DirectorRefShelf extends StatelessWidget {
  const DirectorRefShelf({super.key});

  Future<void> _pickAndAdd(BuildContext context) async {
    final result = await pickImageFiles();
    if (result != null && result.files.single.path != null) {
      final bytes = await File(result.files.single.path!).readAsBytes();
      if (context.mounted) {
        context.read<DirectorRefNotifier>().addReference(bytes);
      }
    }
  }

  void _openEditor(BuildContext context, DirectorRefNotifier notifier, DirectorReference ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DirectorRefEditorSheet(
        reference: ref,
        onTypeChanged: (t) => notifier.updateType(ref.id, t),
        onStrengthChanged: (v) => notifier.updateStrength(ref.id, v),
        onFidelityChanged: (v) => notifier.updateFidelity(ref.id, v),
        onRemove: () => notifier.removeReference(ref.id),
      ),
    );
  }

  void _showRefMenu(BuildContext context) {
    final t = context.t;
    final l = context.l;
    final RenderBox button = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      color: t.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      items: [
        PopupMenuItem(
          value: 'library',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bookmark_outline, size: 14, color: t.accentRefCharacter),
              const SizedBox(width: 8),
              Text(l.refLoadSaved, style: TextStyle(
                fontSize: t.fontSize(9),
                letterSpacing: 1,
                fontWeight: FontWeight.bold,
                color: t.textPrimary,
              )),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'pick',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_photo_alternate_outlined, size: 14, color: t.accentRefCharacter),
              const SizedBox(width: 8),
              Text(l.refPickImage, style: TextStyle(
                fontSize: t.fontSize(9),
                letterSpacing: 1,
                fontWeight: FontWeight.bold,
                color: t.textPrimary,
              )),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'library') {
        _showSavedRefsSheet(context);
      } else if (value == 'pick') {
        _pickAndAdd(context);
      }
    });
  }

  void _showSavedRefsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SavedRefsSheet(
        onLoad: (saved) async {
          final notifier = context.read<DirectorRefNotifier>();
          await notifier.addReference(saved.reference.originalImageBytes);
          final refs = notifier.references;
          if (refs.isNotEmpty) {
            final last = refs.last;
            notifier.updateType(last.id, saved.reference.type);
            notifier.updateStrength(last.id, saved.reference.strength);
            notifier.updateFidelity(last.id, saved.reference.fidelity);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DirectorRefNotifier>(
      builder: (context, notifier, _) {
        final refs = notifier.references;

        final mobile = isMobile(context);
        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: Container(
            height: mobile ? 52 : 44,
            margin: const EdgeInsets.only(top: 2, bottom: 2),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ...refs.map((ref) => DirectorRefChip(
                  reference: ref,
                  onTap: () => _openEditor(context, notifier, ref),
                  onLongPress: () => notifier.removeReference(ref.id),
                )),
                _AddRefButton(
                  isProcessing: notifier.isProcessing,
                  onTap: () => _showRefMenu(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AddRefButton extends StatelessWidget {
  final bool isProcessing;
  final VoidCallback onTap;

  const _AddRefButton({required this.isProcessing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final mobile = isMobile(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: GestureDetector(
        onTap: isProcessing ? null : onTap,
        child: Container(
          height: mobile ? 44 : 36,
          width: mobile ? 52 : 42,
          decoration: BoxDecoration(
            color: t.accentRefCharacter.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: Text('REF', style: TextStyle(
            fontSize: t.fontSize(mobile ? 9 : 7),
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
            color: t.accentRefCharacter,
          )),
        ),
      ),
    );
  }
}

class SavedRefsSheet extends StatefulWidget {
  final Future<void> Function(SavedDirectorRef) onLoad;

  const SavedRefsSheet({super.key, required this.onLoad});

  @override
  State<SavedRefsSheet> createState() => _SavedRefsSheetState();
}

class _SavedRefsSheetState extends State<SavedRefsSheet> {
  List<SavedDirectorRef> _savedRefs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    final path = context.read<PathService>().referenceLibraryFilePath;
    final library = await ReferenceLibraryService.load(path);
    if (mounted) {
      setState(() {
        _savedRefs = library.directorRefs;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    final mobile = isMobile(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.4,
      ),
      decoration: BoxDecoration(
        color: t.surfaceHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Container(
              width: 32,
              height: 3,
              decoration: BoxDecoration(
                color: t.borderMedium,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              l.refSavedSection,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: t.fontSize(mobile ? 10 : 8),
                letterSpacing: 2,
                color: t.textPrimary,
              ),
            ),
          ),
          // Content
          if (_loading)
            Padding(
              padding: const EdgeInsets.all(24),
              child: CircularProgressIndicator(strokeWidth: 2, color: t.textMinimal),
            )
          else if (_savedRefs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                l.refNoSavedRefs,
                style: TextStyle(
                  color: t.textDisabled,
                  fontSize: t.fontSize(9),
                  letterSpacing: 1,
                ),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                itemCount: _savedRefs.length,
                itemBuilder: (context, index) {
                  final saved = _savedRefs[index];
                  return _SavedRefTile(
                    saved: saved,
                    onTap: () {
                      widget.onLoad(saved);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

class _SavedRefTile extends StatelessWidget {
  final SavedDirectorRef saved;
  final VoidCallback onTap;

  const _SavedRefTile({required this.saved, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final mobile = isMobile(context);
    final ref = saved.reference;

    Widget? preview;
    if (ref.processedBase64.isNotEmpty) {
      try {
        preview = Image.memory(
          base64Decode(ref.processedBase64),
          width: mobile ? 36 : 28,
          height: mobile ? 36 : 28,
          fit: BoxFit.cover,
        );
      } catch (_) {}
    }

    final typeLabel = switch (ref.type) {
      DirectorReferenceType.character => 'CHAR',
      DirectorReferenceType.style => 'STYLE',
      DirectorReferenceType.characterAndStyle => 'C&S',
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: mobile ? 36 : 28,
              height: mobile ? 36 : 28,
              decoration: BoxDecoration(
                color: t.accentRefCharacter.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              clipBehavior: Clip.antiAlias,
              child: preview ?? Icon(Icons.image, size: 14, color: t.accentRefCharacter),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    saved.name.toUpperCase(),
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: t.fontSize(mobile ? 10 : 8),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    typeLabel,
                    style: TextStyle(
                      color: t.textDisabled,
                      fontSize: t.fontSize(mobile ? 8 : 6),
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
