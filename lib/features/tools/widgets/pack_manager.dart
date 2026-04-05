import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../../../core/utils/file_picker_helper.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/services/pack_service.dart';
import '../../../core/services/path_service.dart';
import '../../../core/services/preferences_service.dart';
import '../../../core/services/reference_library_service.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_tokens.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/services/presets.dart';
import '../../../core/services/styles.dart';
import '../../gallery/providers/gallery_notifier.dart';
import '../../generation/providers/generation_notifier.dart';
import '../providers/wildcard_notifier.dart';

class PackManager extends StatefulWidget {
  const PackManager({super.key});

  @override
  State<PackManager> createState() => _PackManagerState();
}

class _PackManagerState extends State<PackManager> {
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    final mobile = isMobile(context);

    return Padding(
      padding: EdgeInsets.all(mobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.packTitle,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: t.fontSize(mobile ? 14 : 11),
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l.packDesc,
            style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(mobile ? 12 : 9)),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _PackActionCard(
                  icon: Icons.file_upload_outlined,
                  label: l.packExportLabel,
                  description: l.packExportDesc,
                  color: t.accent,
                  onTap: () => _showExportDialog(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PackActionCard(
                  icon: Icons.file_download_outlined,
                  label: l.packImportLabel,
                  description: l.packImportDesc,
                  color: t.accentSuccess,
                  onTap: () => _importPack(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Divider(color: t.borderSubtle),
          const SizedBox(height: 16),
          Text(
            l.packGalleryExport,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: t.fontSize(mobile ? 14 : 11),
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l.packGalleryExportDesc,
            style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(mobile ? 12 : 9)),
          ),
          const SizedBox(height: 16),
          _PackActionCard(
            icon: Icons.photo_library_outlined,
            label: l.packExportGalleryZip,
            description: l.packExportGalleryZipDesc,
            color: t.accentEdit,
            onTap: () => _showGalleryExportDialog(context),
          ),
        ],
      ),
    );
  }

  Future<void> _showExportDialog(BuildContext context) async {
    final gen = context.read<GenerationNotifier>();
    final wildcard = context.read<WildcardNotifier>();
    final libPath = context.read<PathService>().referenceLibraryFilePath;

    // Load current data
    final presets = await PresetStorage.loadPresets(gen.presetsFilePath);
    final styles = await StyleStorage.loadStyles(gen.stylesFilePath);
    final library = await ReferenceLibraryService.load(libPath);

    // Load wildcard files
    final wcDir = Directory(wildcard.wildcardDir);
    final wcFiles = <File>[];
    if (await wcDir.exists()) {
      await for (final entity in wcDir.list()) {
        if (entity is File && p.extension(entity.path).toLowerCase() == '.txt') {
          wcFiles.add(entity);
        }
      }
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => _ExportDialog(
        presets: presets,
        styles: styles,
        wildcardFiles: wcFiles,
        savedRefs: library.directorRefs,
        savedVibes: library.vibeTransfers,
      ),
    );
  }

  void _showGalleryExportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const _GalleryExportDialog(),
    );
  }

  Future<void> _importPack(BuildContext context) async {
    final result = await pickCustomFiles(
      allowedExtensions: ['vpack'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final fileBytes = result.files.single.bytes;
    Uint8List bytes;
    if (fileBytes != null) {
      bytes = fileBytes;
    } else {
      final path = result.files.single.path;
      if (path == null) return;
      bytes = await File(path).readAsBytes();
    }

    PackContents contents;
    try {
      contents = PackService.importPack(bytes);
    } catch (e) {
      if (context.mounted) {
        showErrorSnackBar(context, context.l.packFailedRead(e.toString()));
      }
      return;
    }

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => _ImportDialog(contents: contents),
    );
  }
}

class _PackActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final VoidCallback onTap;

  const _PackActionCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final mobile = isMobile(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.all(mobile ? 20 : 16),
        decoration: BoxDecoration(
          color: t.surfaceHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: mobile ? 28 : 24),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: t.fontSize(mobile ? 12 : 10),
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(mobile ? 10 : 8)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Export Dialog ───────────────────────────────────────────

class _ExportDialog extends StatefulWidget {
  final List<GenerationPreset> presets;
  final List<PromptStyle> styles;
  final List<File> wildcardFiles;
  final List<SavedDirectorRef> savedRefs;
  final List<SavedVibeTransfer> savedVibes;

  const _ExportDialog({
    required this.presets,
    required this.styles,
    required this.wildcardFiles,
    this.savedRefs = const [],
    this.savedVibes = const [],
  });

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  final _nameController = TextEditingController(text: 'My Pack');
  final _descController = TextEditingController();
  late Set<int> _selectedPresets;
  late Set<int> _selectedStyles;
  late Set<int> _selectedWildcards;
  late Set<int> _selectedSavedRefs;
  late Set<int> _selectedSavedVibes;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _selectedPresets = Set.from(List.generate(widget.presets.length, (i) => i));
    _selectedStyles = Set.from(List.generate(widget.styles.length, (i) => i));
    _selectedWildcards = Set.from(List.generate(widget.wildcardFiles.length, (i) => i));
    _selectedSavedRefs = Set.from(List.generate(widget.savedRefs.length, (i) => i));
    _selectedSavedVibes = Set.from(List.generate(widget.savedVibes.length, (i) => i));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    final mobile = isMobile(context);

    return AlertDialog(
      backgroundColor: t.surfaceHigh,
      title: Text(l.packExportDialogTitle, style: TextStyle(fontSize: t.fontSize(mobile ? 14 : 10), letterSpacing: 2, color: t.textSecondary, fontWeight: FontWeight.w900)),
      content: SizedBox(
        width: mobile ? double.maxFinite : 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(mobile ? 14 : 12)),
                decoration: InputDecoration(
                  labelText: l.packName,
                  labelStyle: TextStyle(color: t.textDisabled, fontSize: t.fontSize(9), letterSpacing: 1),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: t.borderMedium)),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _descController,
                style: TextStyle(color: t.textSecondary, fontSize: t.fontSize(mobile ? 13 : 11)),
                decoration: InputDecoration(
                  labelText: l.packDescriptionOptional,
                  labelStyle: TextStyle(color: t.textDisabled, fontSize: t.fontSize(9), letterSpacing: 1),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: t.borderMedium)),
                ),
              ),
              const SizedBox(height: 20),
              if (widget.presets.isNotEmpty) ...[
                _sectionHeader(l.packPresetsSection(_selectedPresets.length, widget.presets.length), t,
                  allSelected: _selectedPresets.length == widget.presets.length,
                  onToggle: () => setState(() {
                    if (_selectedPresets.length == widget.presets.length) { _selectedPresets.clear(); }
                    else { _selectedPresets = Set.from(List.generate(widget.presets.length, (i) => i)); }
                  }),
                ),
                for (int i = 0; i < widget.presets.length; i++)
                  _checkTile(widget.presets[i].name, _selectedPresets.contains(i), (v) {
                    setState(() => v! ? _selectedPresets.add(i) : _selectedPresets.remove(i));
                  }, t, mobile),
                const SizedBox(height: 12),
              ],
              if (widget.styles.isNotEmpty) ...[
                _sectionHeader(l.packStylesSection(_selectedStyles.length, widget.styles.length), t,
                  allSelected: _selectedStyles.length == widget.styles.length,
                  onToggle: () => setState(() {
                    if (_selectedStyles.length == widget.styles.length) { _selectedStyles.clear(); }
                    else { _selectedStyles = Set.from(List.generate(widget.styles.length, (i) => i)); }
                  }),
                ),
                for (int i = 0; i < widget.styles.length; i++)
                  _checkTile(widget.styles[i].name, _selectedStyles.contains(i), (v) {
                    setState(() => v! ? _selectedStyles.add(i) : _selectedStyles.remove(i));
                  }, t, mobile),
                const SizedBox(height: 12),
              ],
              if (widget.wildcardFiles.isNotEmpty) ...[
                _sectionHeader(l.packWildcardsSection(_selectedWildcards.length, widget.wildcardFiles.length), t,
                  allSelected: _selectedWildcards.length == widget.wildcardFiles.length,
                  onToggle: () => setState(() {
                    if (_selectedWildcards.length == widget.wildcardFiles.length) { _selectedWildcards.clear(); }
                    else { _selectedWildcards = Set.from(List.generate(widget.wildcardFiles.length, (i) => i)); }
                  }),
                ),
                for (int i = 0; i < widget.wildcardFiles.length; i++)
                  _checkTile(p.basenameWithoutExtension(widget.wildcardFiles[i].path), _selectedWildcards.contains(i), (v) {
                    setState(() => v! ? _selectedWildcards.add(i) : _selectedWildcards.remove(i));
                  }, t, mobile),
                const SizedBox(height: 12),
              ],
              if (widget.savedRefs.isNotEmpty) ...[
                _sectionHeader(l.packSavedRefsSection(_selectedSavedRefs.length, widget.savedRefs.length), t,
                  allSelected: _selectedSavedRefs.length == widget.savedRefs.length,
                  onToggle: () => setState(() {
                    if (_selectedSavedRefs.length == widget.savedRefs.length) { _selectedSavedRefs.clear(); }
                    else { _selectedSavedRefs = Set.from(List.generate(widget.savedRefs.length, (i) => i)); }
                  }),
                ),
                for (int i = 0; i < widget.savedRefs.length; i++)
                  _checkTile(widget.savedRefs[i].name, _selectedSavedRefs.contains(i), (v) {
                    setState(() => v! ? _selectedSavedRefs.add(i) : _selectedSavedRefs.remove(i));
                  }, t, mobile),
                const SizedBox(height: 12),
              ],
              if (widget.savedVibes.isNotEmpty) ...[
                _sectionHeader(l.packSavedVibesSection(_selectedSavedVibes.length, widget.savedVibes.length), t,
                  allSelected: _selectedSavedVibes.length == widget.savedVibes.length,
                  onToggle: () => setState(() {
                    if (_selectedSavedVibes.length == widget.savedVibes.length) { _selectedSavedVibes.clear(); }
                    else { _selectedSavedVibes = Set.from(List.generate(widget.savedVibes.length, (i) => i)); }
                  }),
                ),
                for (int i = 0; i < widget.savedVibes.length; i++)
                  _checkTile(widget.savedVibes[i].name, _selectedSavedVibes.contains(i), (v) {
                    setState(() => v! ? _selectedSavedVibes.add(i) : _selectedSavedVibes.remove(i));
                  }, t, mobile),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.commonCancel, style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(9))),
        ),
        TextButton(
          onPressed: _exporting ? null : _export,
          child: _exporting
              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: t.accent))
              : Text(l.commonExport, style: TextStyle(color: t.accent, fontSize: t.fontSize(9), fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _sectionHeader(String text, VisionTokens t, {VoidCallback? onToggle, bool allSelected = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(text, style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(8), letterSpacing: 2, fontWeight: FontWeight.bold)),
          const Spacer(),
          if (onToggle != null)
            GestureDetector(
              onTap: onToggle,
              child: Text(
                allSelected ? 'NONE' : 'ALL',
                style: TextStyle(color: t.accent, fontSize: t.fontSize(8), letterSpacing: 1),
              ),
            ),
        ],
      ),
    );
  }

  Widget _checkTile(String name, bool checked, ValueChanged<bool?> onChanged, VisionTokens t, bool mobile) {
    return SizedBox(
      height: mobile ? 36 : 28,
      child: CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: checked,
        onChanged: onChanged,
        activeColor: t.accent,
        title: Text(name, style: TextStyle(color: t.textSecondary, fontSize: t.fontSize(mobile ? 12 : 10))),
      ),
    );
  }

  Future<void> _export() async {
    if (_nameController.text.trim().isEmpty) return;

    final saveDialogTitle = context.l.packSaveDialogTitle;

    setState(() => _exporting = true);

    try {
      final selectedPresets = _selectedPresets.map((i) => widget.presets[i]).toList();
      final selectedStyles = _selectedStyles.map((i) => widget.styles[i]).toList();

      final wildcards = <String, String>{};
      for (final i in _selectedWildcards) {
        final file = widget.wildcardFiles[i];
        wildcards[p.basename(file.path)] = await file.readAsString();
      }

      final selectedSavedRefs = _selectedSavedRefs.map((i) => widget.savedRefs[i]).toList();
      final selectedSavedVibes = _selectedSavedVibes.map((i) => widget.savedVibes[i]).toList();

      final packBytes = PackService.exportPack(
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        presets: selectedPresets,
        styles: selectedStyles,
        wildcards: wildcards,
        savedRefs: selectedSavedRefs,
        savedVibes: selectedSavedVibes,
      );

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: saveDialogTitle,
        fileName: '${_nameController.text.trim()}.vpack',
        bytes: packBytes,
      );

      if (savePath != null) {
        if (kIsWeb || !Platform.isAndroid) {
          await File(savePath).writeAsBytes(packBytes);
        }
        if (mounted) {
          Navigator.pop(context);
          showAppSnackBar(context, context.l.packExportSuccess);
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, context.l.packExportFailed(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

// ─── Import Dialog ───────────────────────────────────────────

class _ImportDialog extends StatefulWidget {
  final PackContents contents;

  const _ImportDialog({required this.contents});

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  late Set<int> _selectedPresets;
  late Set<int> _selectedStyles;
  late Set<String> _selectedWildcards;
  late Set<int> _selectedSavedRefs;
  late Set<int> _selectedSavedVibes;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _selectedPresets = Set.from(List.generate(widget.contents.presets.length, (i) => i));
    _selectedStyles = Set.from(List.generate(widget.contents.styles.length, (i) => i));
    _selectedWildcards = Set.from(widget.contents.wildcards.keys);
    _selectedSavedRefs = Set.from(List.generate(widget.contents.savedRefs.length, (i) => i));
    _selectedSavedVibes = Set.from(List.generate(widget.contents.savedVibes.length, (i) => i));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    final mobile = isMobile(context);
    final m = widget.contents.manifest;
    final total = _selectedPresets.length + _selectedStyles.length + _selectedWildcards.length + _selectedSavedRefs.length + _selectedSavedVibes.length;

    return AlertDialog(
      backgroundColor: t.surfaceHigh,
      title: Text(l.packImportDialogTitle2, style: TextStyle(fontSize: t.fontSize(mobile ? 14 : 10), letterSpacing: 2, color: t.textSecondary, fontWeight: FontWeight.w900)),
      content: SizedBox(
        width: mobile ? double.maxFinite : 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m.name, style: TextStyle(color: t.accent, fontSize: t.fontSize(mobile ? 16 : 13), fontWeight: FontWeight.bold)),
              if (m.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(m.description, style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(mobile ? 12 : 10))),
                ),
              const SizedBox(height: 16),
              if (widget.contents.presets.isNotEmpty) ...[
                _sectionHeader(l.packPresetsSection(_selectedPresets.length, widget.contents.presets.length), t),
                for (int i = 0; i < widget.contents.presets.length; i++)
                  _checkTile(widget.contents.presets[i].name, _selectedPresets.contains(i), (v) {
                    setState(() => v! ? _selectedPresets.add(i) : _selectedPresets.remove(i));
                  }, t, mobile),
                const SizedBox(height: 12),
              ],
              if (widget.contents.styles.isNotEmpty) ...[
                _sectionHeader(l.packStylesSection(_selectedStyles.length, widget.contents.styles.length), t),
                for (int i = 0; i < widget.contents.styles.length; i++)
                  _checkTile(widget.contents.styles[i].name, _selectedStyles.contains(i), (v) {
                    setState(() => v! ? _selectedStyles.add(i) : _selectedStyles.remove(i));
                  }, t, mobile),
                const SizedBox(height: 12),
              ],
              if (widget.contents.wildcards.isNotEmpty) ...[
                _sectionHeader(l.packWildcardsSection(_selectedWildcards.length, widget.contents.wildcards.length), t),
                for (final key in widget.contents.wildcards.keys)
                  _checkTile(p.basenameWithoutExtension(key), _selectedWildcards.contains(key), (v) {
                    setState(() => v! ? _selectedWildcards.add(key) : _selectedWildcards.remove(key));
                  }, t, mobile),
                const SizedBox(height: 12),
              ],
              if (widget.contents.savedRefs.isNotEmpty) ...[
                _sectionHeader(l.packSavedRefsSection(_selectedSavedRefs.length, widget.contents.savedRefs.length), t),
                for (int i = 0; i < widget.contents.savedRefs.length; i++)
                  _checkTile(widget.contents.savedRefs[i].name, _selectedSavedRefs.contains(i), (v) {
                    setState(() => v! ? _selectedSavedRefs.add(i) : _selectedSavedRefs.remove(i));
                  }, t, mobile),
                const SizedBox(height: 12),
              ],
              if (widget.contents.savedVibes.isNotEmpty) ...[
                _sectionHeader(l.packSavedVibesSection(_selectedSavedVibes.length, widget.contents.savedVibes.length), t),
                for (int i = 0; i < widget.contents.savedVibes.length; i++)
                  _checkTile(widget.contents.savedVibes[i].name, _selectedSavedVibes.contains(i), (v) {
                    setState(() => v! ? _selectedSavedVibes.add(i) : _selectedSavedVibes.remove(i));
                  }, t, mobile),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.commonCancel, style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(9))),
        ),
        TextButton(
          onPressed: _importing || total == 0 ? null : _import,
          child: _importing
              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: t.accentSuccess))
              : Text(l.packImportCount(total), style: TextStyle(color: t.accentSuccess, fontSize: t.fontSize(9), fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _sectionHeader(String text, VisionTokens t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(8), letterSpacing: 2, fontWeight: FontWeight.bold)),
    );
  }

  Widget _checkTile(String name, bool checked, ValueChanged<bool?> onChanged, VisionTokens t, bool mobile) {
    return SizedBox(
      height: mobile ? 36 : 28,
      child: CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: checked,
        onChanged: onChanged,
        activeColor: t.accent,
        title: Text(name, style: TextStyle(color: t.textSecondary, fontSize: t.fontSize(mobile ? 12 : 10))),
      ),
    );
  }

  Future<void> _import() async {
    setState(() => _importing = true);

    try {
      final gen = context.read<GenerationNotifier>();
      final wildcard = context.read<WildcardNotifier>();
      final pathService = context.read<PathService>();

      // Import presets (replace existing by name)
      if (_selectedPresets.isNotEmpty) {
        final existing = await PresetStorage.loadPresets(gen.presetsFilePath);
        for (final i in _selectedPresets) {
          final preset = widget.contents.presets[i];
          final existingIndex = existing.indexWhere((p) => p.name == preset.name);
          if (existingIndex >= 0) {
            existing[existingIndex] = preset;
          } else {
            existing.add(preset);
          }
        }
        await PresetStorage.savePresets(gen.presetsFilePath, existing);
      }

      // Import styles (replace existing by name)
      if (_selectedStyles.isNotEmpty) {
        final existing = await StyleStorage.loadStyles(gen.stylesFilePath);
        for (final i in _selectedStyles) {
          final style = widget.contents.styles[i];
          final existingIndex = existing.indexWhere((s) => s.name == style.name);
          if (existingIndex >= 0) {
            existing[existingIndex] = style;
          } else {
            existing.add(style);
          }
        }
        await StyleStorage.saveStyles(gen.stylesFilePath, existing);
      }

      // Import wildcards (overwrite existing files)
      if (_selectedWildcards.isNotEmpty) {
        for (final key in _selectedWildcards) {
          final content = widget.contents.wildcards[key]!;
          final targetPath = p.join(wildcard.wildcardDir, key);
          await File(targetPath).writeAsString(content);
        }
        await wildcard.wildcardService.refresh();
        await wildcard.refreshFiles();
      }

      // Import saved references (replace existing by name)
      if (_selectedSavedRefs.isNotEmpty || _selectedSavedVibes.isNotEmpty) {
        final libPath = pathService.referenceLibraryFilePath;
        final library = await ReferenceLibraryService.load(libPath);

        for (final i in _selectedSavedRefs) {
          final ref = widget.contents.savedRefs[i];
          final existingIndex = library.directorRefs.indexWhere((r) => r.name == ref.name);
          if (existingIndex >= 0) {
            library.directorRefs[existingIndex] = ref;
          } else {
            library.directorRefs.add(ref);
          }
        }

        for (final i in _selectedSavedVibes) {
          final vibe = widget.contents.savedVibes[i];
          final existingIndex = library.vibeTransfers.indexWhere((v) => v.name == vibe.name);
          if (existingIndex >= 0) {
            library.vibeTransfers[existingIndex] = vibe;
          } else {
            library.vibeTransfers.add(vibe);
          }
        }

        await ReferenceLibraryService.save(libPath, library);
      }

      // Refresh generation notifier to pick up new presets/styles
      gen.reloadPresetsAndStyles();

      if (mounted) {
        Navigator.pop(context);
        showAppSnackBar(context, context.l.packImportSuccess);
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, context.l.packImportFailed(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
}

// ─── Gallery Export Dialog ──────────────────────────────────

class _GalleryExportDialog extends StatefulWidget {
  const _GalleryExportDialog();

  @override
  State<_GalleryExportDialog> createState() => _GalleryExportDialogState();
}

class _GalleryExportDialogState extends State<_GalleryExportDialog> {
  late Set<String> _selectedAlbumIds;
  bool _includeUnsorted = true;
  bool _stripMetadata = false;
  bool _favoritesOnly = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    final gallery = context.read<GalleryNotifier>();
    _selectedAlbumIds = gallery.albums.map((a) => a.id).toSet();
    _stripMetadata = context.read<PreferencesService>().stripMetadataOnExport;
  }

  int _countImages(GalleryNotifier gallery) {
    var items = gallery.items;
    if (_favoritesOnly) {
      items = items.where((i) => i.isFavorite).toList();
    }

    final counted = <String>{};

    // Count album images
    for (final album in gallery.albums) {
      if (!_selectedAlbumIds.contains(album.id)) continue;
      for (final item in items) {
        if (album.imageBasenames.contains(item.basename)) {
          counted.add(item.basename);
        }
      }
    }

    // Count unsorted
    if (_includeUnsorted) {
      final allAlbumBasenames = <String>{};
      for (final album in gallery.albums) {
        allAlbumBasenames.addAll(album.imageBasenames);
      }
      for (final item in items) {
        if (!allAlbumBasenames.contains(item.basename)) {
          counted.add(item.basename);
        }
      }
    }

    return counted.length;
  }

  int _albumImageCount(GalleryNotifier gallery, String albumId) {
    final album = gallery.albums.where((a) => a.id == albumId).firstOrNull;
    if (album == null) return 0;
    var items = gallery.items;
    if (_favoritesOnly) {
      items = items.where((i) => i.isFavorite).toList();
    }
    return items.where((i) => album.imageBasenames.contains(i.basename)).length;
  }

  int _unsortedCount(GalleryNotifier gallery) {
    final allAlbumBasenames = <String>{};
    for (final album in gallery.albums) {
      allAlbumBasenames.addAll(album.imageBasenames);
    }
    var items = gallery.items;
    if (_favoritesOnly) {
      items = items.where((i) => i.isFavorite).toList();
    }
    return items.where((i) => !allAlbumBasenames.contains(i.basename)).length;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    final mobile = isMobile(context);
    final gallery = context.watch<GalleryNotifier>();
    final totalCount = _countImages(gallery);

    return AlertDialog(
      backgroundColor: t.surfaceHigh,
      title: Text(l.packExportGalleryTitle, style: TextStyle(fontSize: t.fontSize(mobile ? 14 : 10), letterSpacing: 2, color: t.textSecondary, fontWeight: FontWeight.w900)),
      content: SizedBox(
        width: mobile ? double.maxFinite : 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Albums
              if (gallery.albums.isNotEmpty) ...[
                _sectionHeader(l.packAlbums, t),
                for (final album in gallery.albums)
                  _checkTile(
                    '${album.name} (${_albumImageCount(gallery, album.id)})',
                    _selectedAlbumIds.contains(album.id),
                    (v) => setState(() => v! ? _selectedAlbumIds.add(album.id) : _selectedAlbumIds.remove(album.id)),
                    t,
                    mobile,
                  ),
                const SizedBox(height: 12),
              ],

              // Unsorted
              _checkTile(
                l.packUnsortedCount(_unsortedCount(gallery)),
                _includeUnsorted,
                (v) => setState(() => _includeUnsorted = v!),
                t,
                mobile,
              ),
              const SizedBox(height: 16),

              // Toggles
              _sectionHeader(l.packOptions, t),
              _checkTile(
                l.packStripMetadata,
                _stripMetadata,
                (v) => setState(() => _stripMetadata = v!),
                t,
                mobile,
              ),
              _checkTile(
                l.packFavoritesOnly,
                _favoritesOnly,
                (v) => setState(() => _favoritesOnly = v!),
                t,
                mobile,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.commonCancel, style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(9))),
        ),
        TextButton(
          onPressed: _exporting || totalCount == 0 ? null : _export,
          child: _exporting
              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: t.accentEdit))
              : Text(l.packExportCount(totalCount), style: TextStyle(color: t.accentEdit, fontSize: t.fontSize(9), fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _sectionHeader(String text, VisionTokens t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(8), letterSpacing: 2, fontWeight: FontWeight.bold)),
    );
  }

  Widget _checkTile(String name, bool checked, ValueChanged<bool?> onChanged, VisionTokens t, bool mobile) {
    return SizedBox(
      height: mobile ? 36 : 28,
      child: CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: checked,
        onChanged: onChanged,
        activeColor: t.accent,
        title: Text(name, style: TextStyle(color: t.textSecondary, fontSize: t.fontSize(mobile ? 12 : 10))),
      ),
    );
  }

  Future<void> _export() async {
    final exportDialogTitle = context.l.packExportGalleryZipDialog;

    setState(() => _exporting = true);

    try {
      final gallery = context.read<GalleryNotifier>();

      final zipBytes = await PackService.exportGalleryZip(
        albums: gallery.albums,
        allItems: gallery.items,
        selectedAlbumIds: _selectedAlbumIds,
        includeUnsorted: _includeUnsorted,
        stripMeta: _stripMetadata,
        favoritesOnly: _favoritesOnly,
      );

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: exportDialogTitle,
        fileName: 'gallery_export.zip',
        bytes: zipBytes,
      );

      if (savePath != null) {
        if (kIsWeb || !Platform.isAndroid) {
          await File(savePath).writeAsBytes(zipBytes);
        }
        if (mounted) {
          Navigator.pop(context);
          final count = _countImages(gallery);
          showAppSnackBar(context, context.l.packExportedToZip(count));
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, context.l.packExportFailed(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}
