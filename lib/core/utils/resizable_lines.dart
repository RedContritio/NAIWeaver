/// Line-count math for drag-resizable text boxes (issue #15).
///
/// Kept pure (no Flutter imports) so the resize behavior is unit-testable.
library;

/// Bounds for the character prompt box height, in text lines.
const int kCharPromptMinLines = 2;
const int kCharPromptMaxLines = 15;
const int kCharPromptDefaultLines = 3;

/// Returns the line count a box should have after dragging its resize handle
/// [dragDy] logical pixels from where the drag started (positive = down),
/// given it started at [startLines] and one text line is [lineHeightPx] tall.
///
/// Rounding to the nearest line makes the handle snap line-by-line, and the
/// result is clamped to [minLines]..[maxLines].
int linesAfterDrag({
  required int startLines,
  required double dragDy,
  required double lineHeightPx,
  int minLines = kCharPromptMinLines,
  int maxLines = kCharPromptMaxLines,
}) {
  assert(lineHeightPx > 0);
  final deltaLines = (dragDy / lineHeightPx).round();
  return (startLines + deltaLines).clamp(minLines, maxLines);
}
