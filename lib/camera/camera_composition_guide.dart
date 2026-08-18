import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CameraCompositionGuide { off, thirds, goldenRatio, goldenSpiral }

extension CameraCompositionGuideX on CameraCompositionGuide {
  static const preferenceKey = 'camera.composition_guide';

  String get wireName => switch (this) {
    CameraCompositionGuide.off => 'off',
    CameraCompositionGuide.thirds => 'thirds',
    CameraCompositionGuide.goldenRatio => 'golden_ratio',
    CameraCompositionGuide.goldenSpiral => 'golden_spiral',
  };

  String get label => switch (this) {
    CameraCompositionGuide.off => 'Off',
    CameraCompositionGuide.thirds => 'Thirds / Nines',
    CameraCompositionGuide.goldenRatio => 'Golden Ratio',
    CameraCompositionGuide.goldenSpiral => 'Golden Spiral',
  };

  static CameraCompositionGuide parse(String? value) => switch (value) {
    'thirds' => CameraCompositionGuide.thirds,
    'golden_ratio' => CameraCompositionGuide.goldenRatio,
    'golden_spiral' => CameraCompositionGuide.goldenSpiral,
    _ => CameraCompositionGuide.off,
  };

  Future<void> persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(preferenceKey, wireName);
  }

  static Future<CameraCompositionGuide> load() async {
    final prefs = await SharedPreferences.getInstance();
    return parse(prefs.getString(preferenceKey));
  }
}

class CameraCompositionGuideOverlay extends StatelessWidget {
  const CameraCompositionGuideOverlay({
    required this.guide,
    this.frameAspectRatio,
    super.key,
  });

  final CameraCompositionGuide guide;
  final double? frameAspectRatio;

  @override
  Widget build(BuildContext context) {
    if (guide == CameraCompositionGuide.off) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: CustomPaint(
        painter: _CompositionGuidePainter(
          guide: guide,
          frameAspectRatio: frameAspectRatio,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _CompositionGuidePainter extends CustomPainter {
  const _CompositionGuidePainter({
    required this.guide,
    required this.frameAspectRatio,
  });

  final CameraCompositionGuide guide;
  final double? frameAspectRatio;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final frame = _frameFor(size);
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.42)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.74)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    void drawSegment(Offset a, Offset b) {
      canvas
        ..drawLine(a, b, shadow)
        ..drawLine(a, b, line);
    }

    switch (guide) {
      case CameraCompositionGuide.off:
        return;
      case CameraCompositionGuide.thirds:
        final xs = <double>[
          frame.left + frame.width / 3,
          frame.left + frame.width * 2 / 3,
        ];
        final ys = <double>[
          frame.top + frame.height / 3,
          frame.top + frame.height * 2 / 3,
        ];
        for (final x in xs) {
          drawSegment(Offset(x, frame.top), Offset(x, frame.bottom));
        }
        for (final y in ys) {
          drawSegment(Offset(frame.left, y), Offset(frame.right, y));
        }
        final dot = Paint()
          ..color = Colors.white.withValues(alpha: 0.84)
          ..style = PaintingStyle.fill;
        for (final x in xs) {
          for (final y in ys) {
            canvas.drawCircle(Offset(x, y), 2.4, dot);
          }
        }
        return;
      case CameraCompositionGuide.goldenRatio:
        const minor = 0.3819660112501051;
        const major = 1 - minor;
        final xs = <double>[
          frame.left + frame.width * minor,
          frame.left + frame.width * major,
        ];
        final ys = <double>[
          frame.top + frame.height * minor,
          frame.top + frame.height * major,
        ];
        for (final x in xs) {
          drawSegment(Offset(x, frame.top), Offset(x, frame.bottom));
        }
        for (final y in ys) {
          drawSegment(Offset(frame.left, y), Offset(frame.right, y));
        }
        return;
      case CameraCompositionGuide.goldenSpiral:
        _drawGoldenSpiral(canvas, frame, shadow);
        _drawGoldenSpiral(canvas, frame, line);
        return;
    }
  }

  Rect _frameFor(Size size) {
    final aspect = frameAspectRatio;
    if (aspect == null || aspect <= 0) return Offset.zero & size;
    final available = size.width / size.height;
    if (available > aspect) {
      final width = size.height * aspect;
      return Rect.fromLTWH((size.width - width) / 2, 0, width, size.height);
    }
    final height = size.width / aspect;
    return Rect.fromLTWH(0, (size.height - height) / 2, size.width, height);
  }

  void _drawGoldenSpiral(Canvas canvas, Rect frame, Paint paint) {
    final landscape = frame.width >= frame.height;
    final center = Offset(
      landscape ? frame.left + frame.width * 0.382 : frame.center.dx,
      landscape ? frame.center.dy : frame.top + frame.height * 0.618,
    );
    final diagonal = math.sqrt(
      frame.width * frame.width + frame.height * frame.height,
    );
    const turns = 1.75;
    const samples = 240;
    final path = Path();
    for (var i = 0; i <= samples; i++) {
      final t = i / samples * turns * 2 * math.pi;
      final normalized = math.exp(0.306349 * t) /
          math.exp(0.306349 * turns * 2 * math.pi);
      final radius = diagonal * 0.64 * normalized;
      final angle = landscape ? t + math.pi : t + math.pi / 2;
      final point = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.save();
    canvas.clipRect(frame);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CompositionGuidePainter oldDelegate) =>
      oldDelegate.guide != guide ||
      oldDelegate.frameAspectRatio != frameAspectRatio;
}
