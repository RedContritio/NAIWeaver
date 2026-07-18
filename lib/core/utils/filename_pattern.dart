/// Pure expansion of user-defined filename and save-path patterns (issue #27).
///
/// A pattern is literal text plus `<token>` / `<token:arg>` placeholders:
///
///   `<prompt>`         the prompt, sanitized and truncated exactly like the
///                      NAI-style default filename
///   `<seed>`           the generation seed
///   `<album>`          the album the image is being saved into; `<album:X>`
///                      substitutes `X` when there is no album
///   `<year>` `<month>` `<day>` `<hours>` `<minutes>` `<seconds>`
///                      zero-padded parts of the file-saved time
///   `<date>`           shorthand for `<year>-<month>-<day>`
///   `<time>`           shorthand for `<hours>-<minutes>-<seconds>`
///   `<digits:0000>`    per-folder sequence counter, zero-padded to the arg's
///                      width (`<digits>` is unpadded)
///
/// Unknown tokens pass through as literal text (their angle brackets sanitize
/// to `_`), so a typo is visible in the settings live preview instead of being
/// silently dropped.
///
/// Everything here is pure — the per-folder sequence number and the save time
/// are inputs, not lookups — so behavior is fully unit-testable.
library;

import 'nai_filename.dart';

/// The built-in default naming, expressed as a pattern. Shown as the hint for
/// an empty filename-pattern setting; an empty setting keeps using
/// [naiFilenameBase] directly, so existing users see no change.
const String kDefaultFilenamePattern = '<prompt> s-<seed>';

final RegExp _token = RegExp(r'<([a-zA-Z]+)(?::([^<>]*))?>');
final RegExp _zeros = RegExp(r'^0+$');

/// Inputs for one expansion: the generation being saved and where it lands.
class FilenamePatternContext {
  final String prompt;
  final String seed;

  /// File-saved time — the issue asks for save time, not generation time.
  final DateTime savedAt;

  /// Name of the album the image is saved into, or '' when none.
  final String albumName;

  /// 1-based per-folder sequence number for `<digits>` tokens.
  final int sequence;

  const FilenamePatternContext({
    required this.prompt,
    required this.seed,
    required this.savedAt,
    this.albumName = '',
    this.sequence = 1,
  });
}

String _pad2(int v) => v.toString().padLeft(2, '0');

String _expandTokens(String pattern, FilenamePatternContext ctx) {
  final d = ctx.savedAt;
  return pattern.replaceAllMapped(_token, (m) {
    final arg = m.group(2);
    switch (m.group(1)!.toLowerCase()) {
      case 'prompt':
        return naiSanitizeForFilename(ctx.prompt,
            maxLength: naiFilenamePromptMaxLength);
      case 'seed':
        return ctx.seed;
      case 'album':
        return ctx.albumName.isNotEmpty ? ctx.albumName : (arg ?? '');
      case 'year':
        return d.year.toString().padLeft(4, '0');
      case 'month':
        return _pad2(d.month);
      case 'day':
        return _pad2(d.day);
      case 'hours':
        return _pad2(d.hour);
      case 'minutes':
        return _pad2(d.minute);
      case 'seconds':
        return _pad2(d.second);
      case 'date':
        return '${d.year.toString().padLeft(4, '0')}-${_pad2(d.month)}-${_pad2(d.day)}';
      case 'time':
        return '${_pad2(d.hour)}-${_pad2(d.minute)}-${_pad2(d.second)}';
      case 'digits':
        final width = arg == null || arg.isEmpty
            ? 0
            : _zeros.hasMatch(arg)
                ? arg.length
                : int.tryParse(arg) ?? 0;
        final n = ctx.sequence.toString();
        return width > 0 ? n.padLeft(width, '0') : n;
      default:
        return m.group(0)!; // unknown token stays literal
    }
  });
}

/// Expands [pattern] into a filename base (no extension). The result is
/// sanitized as one filename segment — any character illegal in Windows
/// filenames, whether typed literally or produced by a token value (an album
/// named `a/b`, say), becomes `_`. Returns '' when the pattern expands to
/// nothing; callers should fall back to the default NAI-style name.
String expandFilenamePattern(String pattern, FilenamePatternContext ctx) {
  return naiSanitizeForFilename(_expandTokens(pattern, ctx));
}

/// Expands [pattern] into a relative save path. `/` or `\` in the pattern
/// separate folders; each segment is expanded and sanitized independently, and
/// segments that come out empty (a bare `<album>` with no album) or dot-only
/// (`.`/`..`, typed or smuggled through a token value) are dropped — a pattern
/// can never escape the base directory. Segments are joined with `/`, which
/// `package:path` normalizes on every platform. Returns '' when nothing
/// remains, meaning "save into the base directory itself".
String expandSavePathPattern(String pattern, FilenamePatternContext ctx) {
  final parts = <String>[];
  for (final segment in pattern.split(RegExp(r'[/\\]'))) {
    // Sanitizing strips trailing dots, so `.` and `..` collapse to '' here.
    final expanded = naiSanitizeForFilename(_expandTokens(segment, ctx));
    if (expanded.isEmpty) continue;
    parts.add(expanded);
  }
  return parts.join('/');
}
