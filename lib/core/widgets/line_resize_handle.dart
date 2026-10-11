import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';
import '../utils/resizable_lines.dart';

/// A slim grab bar next to a text box that resizes it by whole text lines
/// (issue #15). It sits below the box, or above it with [growUpward]. Drag
/// vertically; the new size is reported live through [onLines] and once more
/// through [onDone] when the finger/mouse lifts, which is the moment to
/// persist it. A tap, or a drag that ends on the starting size, reports
/// nothing.
class LineResizeHandle extends StatefulWidget {
  final int lines;
  final double lineHeightPx;
  final ValueChanged<int> onLines;
  final ValueChanged<int> onDone;
  final int minLines;
  final int maxLines;
  final Color? color;
  final bool growUpward;

  const LineResizeHandle({
    super.key,
    required this.lines,
    required this.lineHeightPx,
    required this.onLines,
    required this.onDone,
    this.minLines = kCharPromptMinLines,
    this.maxLines = kCharPromptMaxLines,
    this.color,
    this.growUpward = false,
  });

  @override
  State<LineResizeHandle> createState() => _LineResizeHandleState();
}

class _LineResizeHandleState extends State<LineResizeHandle> {
  int _startLines = 0;
  double _dragDy = 0;
  int _current = 0;

  @override
  Widget build(BuildContext context) {
    final handleColor = widget.color ?? context.t.borderMedium;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) {
          _startLines = widget.lines;
          _current = widget.lines;
          _dragDy = 0;
        },
        onVerticalDragUpdate: (details) {
          _dragDy += details.delta.dy;
          final next = linesAfterDrag(
            startLines: _startLines,
            dragDy: widget.growUpward ? -_dragDy : _dragDy,
            lineHeightPx: widget.lineHeightPx,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
          );
          if (next != _current) {
            _current = next;
            widget.onLines(next);
          }
        },
        // Only a drag that changed the size reports it. Inside a scrollable a
        // tap never becomes a drag and ends in onCancel, so there is
        // deliberately no cancel handler (an accepted drag, even one ended by
        // a cancelled pointer, finishes through onEnd). Without a competing
        // recognizer a tap is accepted as a zero-length drag, which the
        // unchanged size filters out.
        onVerticalDragEnd: (_) {
          if (_current != _startLines) widget.onDone(_current);
        },
        child: SizedBox(
          height: 14,
          width: double.infinity,
          child: Center(
            child: Container(
              width: 36,
              height: 3,
              decoration: BoxDecoration(
                color: handleColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
