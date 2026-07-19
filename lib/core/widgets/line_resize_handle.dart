import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';
import '../utils/resizable_lines.dart';

/// A slim grab bar under a text box that resizes it by whole text lines
/// (issue #15). Drag vertically; the new size is reported live through
/// [onLines] and once more through [onDone] when the finger/mouse lifts,
/// which is the moment to persist it.
class LineResizeHandle extends StatefulWidget {
  final int lines;
  final double lineHeightPx;
  final ValueChanged<int> onLines;
  final ValueChanged<int> onDone;

  const LineResizeHandle({
    super.key,
    required this.lines,
    required this.lineHeightPx,
    required this.onLines,
    required this.onDone,
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
    final t = context.t;
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
            dragDy: _dragDy,
            lineHeightPx: widget.lineHeightPx,
          );
          if (next != _current) {
            _current = next;
            widget.onLines(next);
          }
        },
        onVerticalDragEnd: (_) => widget.onDone(_current),
        onVerticalDragCancel: () => widget.onDone(_current),
        child: SizedBox(
          height: 14,
          width: double.infinity,
          child: Center(
            child: Container(
              width: 36,
              height: 3,
              decoration: BoxDecoration(
                color: t.borderMedium,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
