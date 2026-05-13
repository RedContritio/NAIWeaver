import 'package:flutter/material.dart';

import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/theme/vision_tokens.dart';
import '../character_gen_data.dart';
import '../character_gen_service.dart';

/// The "Generate Character" form. Returns a [CharacterGenForm] on submit, null
/// on cancel. The era catalogue must already be loaded
/// ([CharacterEraCatalogue.load]); it falls back to a small built-in list.
class CharacterGenDialog extends StatefulWidget {
  final List<CharacterEra> eras;
  const CharacterGenDialog({super.key, required this.eras});

  static Future<CharacterGenForm?> show(BuildContext context) async {
    final eras = await CharacterEraCatalogue.load();
    if (!context.mounted) return null;
    return showDialog<CharacterGenForm>(
      context: context,
      builder: (_) => CharacterGenDialog(eras: eras),
    );
  }

  @override
  State<CharacterGenDialog> createState() => _CharacterGenDialogState();
}

class _CharacterGenDialogState extends State<CharacterGenDialog> {
  late String _gender;
  late CharacterVibe _vibe;
  late CharacterEra _era;
  final _location = TextEditingController();
  final _customVibe = TextEditingController();
  final _addiction = TextEditingController();
  bool _nsfw = false;
  CharacterImageStyle _imageStyle = CharacterImageStyle.anime;
  double _wardrobeCount = 5;

  @override
  void initState() {
    super.initState();
    _gender = 'any';
    _vibe = kCharacterVibes.first;
    _era = widget.eras.firstWhere(
      (e) => e.isModern,
      orElse: () => widget.eras.isNotEmpty ? widget.eras.last : kFallbackEras.first,
    );
  }

  @override
  void dispose() {
    _location.dispose();
    _customVibe.dispose();
    _addiction.dispose();
    super.dispose();
  }

  bool get _valid {
    if (_vibe.isCustom && _customVibe.text.trim().isEmpty) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AlertDialog(
      backgroundColor: t.surfaceHigh,
      scrollable: true,
      title: Text('GENERATE CHARACTER',
          style: TextStyle(
              color: t.textSecondary,
              fontSize: t.titleSize(11),
              letterSpacing: 3,
              fontWeight: FontWeight.bold)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -- Vibe ---------------------------------------------------------
            _label(t, 'VIBE'),
            _dropdown<CharacterVibe>(
              t,
              value: _vibe,
              items: kCharacterVibes,
              labelOf: (v) => v.name,
              onChanged: (v) => setState(() => _vibe = v ?? kCharacterVibes.first),
            ),
            if (_vibe.hint.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(_vibe.hint,
                    style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(9), fontStyle: FontStyle.italic)),
              ),
            if (_vibe.isCustom) ...[
              const SizedBox(height: 6),
              TextField(
                controller: _customVibe,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(12)),
                decoration: _deco(t, 'describe the vibe — e.g. "weary war veteran turned baker"'),
              ),
            ],
            if (_vibe.hasAddictionSubject) ...[
              const SizedBox(height: 6),
              _label(t, 'ADDICTION SUBJECT (optional)'),
              TextField(
                controller: _addiction,
                style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(12)),
                decoration: _deco(t, 'e.g. opium, gambling, a person, adrenaline — blank lets the model pick'),
              ),
            ],
            const SizedBox(height: 12),

            // -- Gender + era -------------------------------------------------
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label(t, 'GENDER'),
                      _dropdown<String>(
                        t,
                        value: _gender,
                        items: kCharacterGenderOptions,
                        labelOf: (g) => g == 'any' ? 'Any (model picks)' : g,
                        onChanged: (g) => setState(() => _gender = g ?? 'any'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label(t, 'ERA / TIME PERIOD'),
                      _dropdown<CharacterEra>(
                        t,
                        value: _era,
                        items: widget.eras,
                        labelOf: (e) => e.isModern ? e.label : '${e.label} (${_yearLabel(e.year)})',
                        onChanged: (e) => setState(() => _era = e ?? widget.eras.first),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!_era.isModern && _era.quote.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('“${_era.quote}”',
                    style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(9), fontStyle: FontStyle.italic)),
              ),
            const SizedBox(height: 12),

            // -- Location -----------------------------------------------------
            _label(t, 'LOCATION (optional)'),
            TextField(
              controller: _location,
              style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(12)),
              decoration: _deco(t, 'e.g. a coastal town in Portugal, Winterfell — blank lets the model pick'),
            ),
            const SizedBox(height: 12),

            // -- NSFW + image style ------------------------------------------
            Row(
              children: [
                Expanded(
                  child: _toggleRow(t, 'NSFW TAGS', _nsfw, (v) => setState(() => _nsfw = v),
                      hint: 'also request the split nsfw_* tag buckets'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _label(t, 'IMAGE STYLE'),
            Row(
              children: [
                for (final s in CharacterImageStyle.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s.label, style: TextStyle(fontSize: t.fontSize(10))),
                      selected: _imageStyle == s,
                      onSelected: (_) => setState(() => _imageStyle = s),
                      selectedColor: t.accent.withValues(alpha: 0.25),
                      backgroundColor: t.surfaceMid,
                      labelStyle: TextStyle(color: _imageStyle == s ? t.accent : t.textTertiary),
                      side: BorderSide(color: _imageStyle == s ? t.accent : t.borderSubtle),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _imageStyle == CharacterImageStyle.realistic
                    ? 'realistic — also fills the natural-language description'
                    : 'anime — tag-based (what NAI image gen uses)',
                style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(9), fontStyle: FontStyle.italic),
              ),
            ),
            const SizedBox(height: 12),

            // -- Wardrobe count ----------------------------------------------
            _label(t, 'STARTER WARDROBE: ${_wardrobeCount.round()} OUTFIT(S)'),
            Slider(
              value: _wardrobeCount,
              min: 0,
              max: 12,
              divisions: 12,
              activeColor: t.accent,
              label: '${_wardrobeCount.round()}',
              onChanged: (v) => setState(() => _wardrobeCount = v),
            ),
            Text(
              'plus the "meet" outfit (always generated). On a free/Tablet-tier '
              'token, large counts are generated in small batches.',
              style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(8.5)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('CANCEL', style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(9))),
        ),
        ElevatedButton(
          onPressed: _valid ? _submit : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: t.accent.withValues(alpha: 0.2),
            foregroundColor: t.accent,
            elevation: 0,
          ),
          child: Text('✨ GENERATE', style: TextStyle(fontSize: t.fontSize(9), letterSpacing: 1)),
        ),
      ],
    );
  }

  void _submit() {
    Navigator.of(context).pop(CharacterGenForm(
      gender: _gender,
      vibe: _vibe,
      customVibe: _customVibe.text.trim(),
      addictionSubject: _addiction.text.trim(),
      era: _era,
      location: _location.text.trim(),
      nsfw: _nsfw,
      imageStyle: _imageStyle,
      wardrobeCount: _wardrobeCount.round(),
    ));
  }

  // -- small UI helpers ----------------------------------------------------

  Widget _label(VisionTokens t, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 2),
        child: Text(text,
            style: TextStyle(color: t.textTertiary, fontSize: t.fontSize(8), letterSpacing: 1.5)),
      );

  Widget _dropdown<T>(
    VisionTokens t, {
    required T value,
    required List<T> items,
    required String Function(T) labelOf,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: t.borderSubtle),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          dropdownColor: t.surfaceHigh,
          style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(11)),
          onChanged: onChanged,
          items: [
            for (final it in items)
              DropdownMenuItem<T>(
                value: it,
                child: Text(labelOf(it),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: t.fontSize(11))),
              ),
          ],
        ),
      ),
    );
  }

  Widget _toggleRow(VisionTokens t, String label, bool value, ValueChanged<bool> onChanged,
      {String? hint}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(color: t.textTertiary, fontSize: t.fontSize(8), letterSpacing: 1.5)),
              if (hint != null)
                Text(hint,
                    style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(8.5), fontStyle: FontStyle.italic)),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: t.accent,
        ),
      ],
    );
  }

  InputDecoration _deco(VisionTokens t, String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: t.textMinimal, fontSize: t.fontSize(10)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: t.borderSubtle), borderRadius: BorderRadius.circular(4)),
        focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: t.accent), borderRadius: BorderRadius.circular(4)),
      );

  static String _yearLabel(int year) {
    if (year < 0) return '${-year} BC';
    return 'AD $year';
  }
}
