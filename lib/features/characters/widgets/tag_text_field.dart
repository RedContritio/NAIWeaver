import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/tag_service.dart';
import '../../../core/utils/tag_suggestion_helper.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/widgets/tag_suggestion_overlay.dart';
import '../providers/character_library_notifier.dart';

/// A multi-line tag text field with the shared danbooru tag autocomplete (plus
/// saved-character entries). Self-contained — manages its own suggestion list
/// and dropdown rather than going through a notifier. Used by the character
/// editor's tag buckets and the outfit editor's tag field.
class TagTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int minLines;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  const TagTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.minLines = 1,
    this.maxLines = 3,
    this.onChanged,
  });

  @override
  State<TagTextField> createState() => _TagTextFieldState();
}

class _TagTextFieldState extends State<TagTextField> {
  List<DanbooruTag> _suggestions = const [];
  Timer? _debounce;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _suggestions.isNotEmpty) {
        setState(() => _suggestions = const []);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged() {
    widget.onChanged?.call(widget.controller.text);
    if (!_focusNode.hasFocus) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      final tagService = context.read<TagService>();
      final charLib = context.read<CharacterLibraryNotifier>();
      final result = TagSuggestionHelper.getSuggestions(
        text: widget.controller.text,
        selection: widget.controller.selection,
        tagService: tagService,
        characterSuggestionsFor: (q) => charLib.suggestionTags(q),
      );
      setState(() => _suggestions = result.suggestions);
    });
  }

  void _onTagSelected(DanbooruTag tag) {
    TagSuggestionHelper.applyTag(widget.controller, tag);
    setState(() => _suggestions = const []);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label.toUpperCase(),
          style: TextStyle(
            color: t.textSecondary,
            fontSize: t.fontSize(9),
            letterSpacing: 2,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(12)),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: TextStyle(color: t.textMinimal, fontSize: t.fontSize(10)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: t.borderSubtle),
              borderRadius: BorderRadius.circular(4),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: t.accent),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        if (_suggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TagSuggestionOverlay(
              suggestions: _suggestions,
              onTagSelected: _onTagSelected,
            ),
          ),
      ],
    );
  }
}
