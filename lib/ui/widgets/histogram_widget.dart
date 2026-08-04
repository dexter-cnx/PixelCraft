import 'dart:math' as math;
import 'package:flutter/material.dart';

class HistogramWidget extends StatelessWidget {
  const HistogramWidget({super.key, required this.bins});
  final List<int> bins;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 92,
    child: CustomPaint(
      painter: _HistogramPainter(bins, Theme.of(context).colorScheme),
      size: Size.infinite,
    ),
  );
}

class _HistogramPainter extends CustomPainter {
  _HistogramPainter(this.bins, this.colors);
  final List<int> bins;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = colors.surfaceContainerHigh;
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)), background);
    if (bins.length < 768) return;
    final maxValue = bins.reduce(math.max).clamp(1, 1 << 31).toDouble();
    final channelColors = [Colors.red, Colors.green, Colors.blue];
    for (var channel = 0; channel < 3; channel++) {
      final path = Path()..moveTo(0, size.height);
      for (var i = 0; i < 256; i++) {
        final x = i / 255 * size.width;
        final y = size.height - (bins[channel * 256 + i] / maxValue * size.height);
        path.lineTo(x, y);
      }
      path.lineTo(size.width, size.height);
      path.close();
      canvas.drawPath(path, Paint()..color = channelColors[channel].withValues(alpha: .26));
    }
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter oldDelegate) => oldDelegate.bins != bins;
}
