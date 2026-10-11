import 'package:flutter/material.dart';

/// Two-tone checkerboard drawn behind images with transparent areas. The
/// colors come from the theme (for example `surfaceHigh` / `surfaceMid`).
class CheckerboardPainter extends CustomPainter {
  final Color light;
  final Color dark;
  final double cellSize;

  const CheckerboardPainter({
    required this.light,
    required this.dark,
    this.cellSize = 12,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final lightPaint = Paint()..color = light;
    final darkPaint = Paint()..color = dark;

    for (double y = 0; y < size.height; y += cellSize) {
      for (double x = 0; x < size.width; x += cellSize) {
        final isLight = ((x ~/ cellSize) + (y ~/ cellSize)) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x, y, cellSize, cellSize),
          isLight ? lightPaint : darkPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(CheckerboardPainter old) =>
      old.light != light || old.dark != dark || old.cellSize != cellSize;
}
