import 'dart:math' as math;

import 'package:flutter/material.dart';

enum HistogramChannelView { rgb, red, green, blue }

class HistogramWidget extends StatefulWidget {
  const HistogramWidget({super.key, required this.bins});

  final List<int> bins;

  @override
  State<HistogramWidget> createState() => _HistogramWidgetState();
}

class _HistogramWidgetState extends State<HistogramWidget> {
  HistogramChannelView _view = HistogramChannelView.rgb;

  String get _label => switch (_view) {
        HistogramChannelView.rgb => 'RGB',
        HistogramChannelView.red => 'R',
        HistogramChannelView.green => 'G',
        HistogramChannelView.blue => 'B',
      };

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 92,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _HistogramPainter(
                widget.bins,
                Theme.of(context).colorScheme,
                _view,
              ),
              size: Size.infinite,
            ),
            Positioned(
              top: 6,
              right: 6,
              child: Material(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: .88),
                borderRadius: BorderRadius.circular(10),
                child: PopupMenuButton<HistogramChannelView>(
                  key: const ValueKey('histogram_channel_menu'),
                  tooltip: 'Histogram channel',
                  initialValue: _view,
                  onSelected: (view) => setState(() => _view = view),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: HistogramChannelView.rgb,
                      child: Text('RGB'),
                    ),
                    PopupMenuItem(
                      value: HistogramChannelView.red,
                      child: Text('Red'),
                    ),
                    PopupMenuItem(
                      value: HistogramChannelView.green,
                      child: Text('Green'),
                    ),
                    PopupMenuItem(
                      value: HistogramChannelView.blue,
                      child: Text('Blue'),
                    ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _label,
                          key: const ValueKey('histogram_channel_label'),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(width: 3),
                        const Icon(Icons.arrow_drop_down, size: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

class _HistogramPainter extends CustomPainter {
  _HistogramPainter(this.bins, this.colors, this.view);

  final List<int> bins;
  final ColorScheme colors;
  final HistogramChannelView view;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = colors.surfaceContainerHigh;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)),
      background,
    );
    if (bins.length < 768) return;

    final channels = switch (view) {
      HistogramChannelView.rgb => const <int>[0, 1, 2],
      HistogramChannelView.red => const <int>[0],
      HistogramChannelView.green => const <int>[1],
      HistogramChannelView.blue => const <int>[2],
    };
    final maxValue = channels
        .expand(
          (channel) => bins.skip(channel * 256).take(256),
        )
        .reduce(math.max)
        .clamp(1, 1 << 31)
        .toDouble();
    final channelColors = [Colors.red, Colors.green, Colors.blue];

    for (final channel in channels) {
      final path = Path()..moveTo(0, size.height);
      for (var i = 0; i < 256; i++) {
        final x = i / 255 * size.width;
        final y = size.height -
            (bins[channel * 256 + i] / maxValue * size.height);
        path.lineTo(x, y);
      }
      path.lineTo(size.width, size.height);
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = channelColors[channel].withValues(
            alpha: view == HistogramChannelView.rgb ? .26 : .48,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter oldDelegate) =>
      oldDelegate.bins != bins ||
      oldDelegate.view != view ||
      oldDelegate.colors != colors;
}
