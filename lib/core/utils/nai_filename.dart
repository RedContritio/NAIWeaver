/// Builds a NovelAI-style filename base from a prompt and seed, matching the
/// official NAI web UI convention (see issue #28):
///
///   prompt: `2::1girl::, long hair, artist:test, painting (medium)`
///   seed:   `12345678`
///   result: `2__1girl__, long hair, artist_test, painting (medium) s-12345678`
///
/// Only characters that are illegal in filenames are replaced — one `_` per
/// character, so `::` becomes `__` like NAI. Spaces, commas, parentheses,
/// braces, brackets, and letter case are all preserved. The Windows-illegal
/// set is used on every platform so filenames stay portable across sync and
/// export targets.
library;

/// Characters that cannot appear in Windows filenames (the strictest
/// platform), plus ASCII control characters.
final RegExp _illegalChars = RegExp(r'[<>:"/\\|?*\x00-\x1F]');

/// Windows also forbids trailing dots and spaces on filenames.
final RegExp _trailingDotsSpaces = RegExp(r'[. ]+$');

/// Maximum length of the prompt portion of the filename. NAI truncates long
/// prompts too; 100 keeps headroom under Windows' 260-char path limit once
/// the output directory, ` s-<seed>`, and `_(n).png` suffixes are added.
const int naiFilenamePromptMaxLength = 100;

/// Makes [text] safe to use as (part of) a filename: trims it, replaces each
/// Windows-illegal character with one `_`, optionally truncates to
/// [maxLength], and strips trailing dots/spaces. Shared by the NAI-style
/// default name below and the custom pattern expander (issue #27).
String naiSanitizeForFilename(String text, {int? maxLength}) {
  var sanitized = text.trim().replaceAll(_illegalChars, '_');
  if (maxLength != null && sanitized.length > maxLength) {
    sanitized = sanitized.substring(0, maxLength);
  }
  return sanitized.replaceAll(_trailingDotsSpaces, '');
}

/// Returns `<sanitized prompt> s-<seed>` for use as a filename base (no
/// extension). Falls back to `s-<seed>` if the prompt sanitizes to nothing,
/// or to the bare prompt if [seed] is empty.
String naiFilenameBase(String prompt, String seed) {
  final sanitized =
      naiSanitizeForFilename(prompt, maxLength: naiFilenamePromptMaxLength);
  if (seed.isEmpty) return sanitized;
  if (sanitized.isEmpty) return 's-$seed';
  return '$sanitized s-$seed';
}
