import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CameraCompositionGuide { off, thirds, goldenRatio, goldenSpiral }

extension CameraCompositionGuideX on CameraCompositionGuide {
  static const enabledPreferenceKey = 'camera.composition_guide.enabled';
  static const stylePreferenceKey = 'camera.composition_guide.style';
  static const legacyPreferenceKey = 'camera.composition_guide';
  static const flipHorizontalPreferenceKey =
      'camera.composition_guide.golden_spiral.flip_horizontal';
  static const flipVerticalPreferenceKey =
      'camera.composition_guide.golden_spiral.flip_vertical';

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
    'golden_ratio' => CameraCompositionGuide.goldenRatio,
    'golden_spiral' => CameraCompositionGuide.goldenSpiral,
    'off' => CameraCompositionGuide.off,
    _ => CameraCompositionGuide.thirds,
  };

  static Future<CameraCompositionGuideSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(legacyPreferenceKey);
    final explicitEnabled = prefs.getBool(enabledPreferenceKey);
    final enabled = explicitEnabled ?? (legacy != null && legacy != 'off');
    var guide = parse(prefs.getString(stylePreferenceKey) ?? legacy);
    if (guide == CameraCompositionGuide.off) {
      guide = CameraCompositionGuide.thirds;
    }
    return CameraCompositionGuideSettings(
      enabled: enabled,
      guide: guide,
      flipHorizontal: prefs.getBool(flipHorizontalPreferenceKey) ?? false,
      flipVertical: prefs.getBool(flipVerticalPreferenceKey) ?? false,
    );
  }

  static Future<void> persistEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledPreferenceKey, enabled);
  }

  Future<void> persistStyle() async {
    if (this == CameraCompositionGuide.off) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(stylePreferenceKey, wireName);
  }

  static Future<void> persistGoldenSpiralFlip({
    required bool horizontal,
    required bool vertical,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(flipHorizontalPreferenceKey, horizontal);
    await prefs.setBool(flipVerticalPreferenceKey, vertical);
  }
}

class CameraCompositionGuideSettings {
  const CameraCompositionGuideSettings({
    required this.enabled,
    required this.guide,
    required this.flipHorizontal,
    required this.flipVertical,
  });

  final bool enabled;
  final CameraCompositionGuide guide;
  final bool flipHorizontal;
  final bool flipVertical;
}

class CameraCompositionGuideOverlay extends StatelessWidget {
  const CameraCompositionGuideOverlay({
    required this.guide,
    this.frameAspectRatio,
    this.flipHorizontal = false,
    this.flipVertical = false,
    super.key,
  });

  final CameraCompositionGuide guide;
  final double? frameAspectRatio;
  final bool flipHorizontal;
  final bool flipVertical;

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
          flipHorizontal: flipHorizontal,
          flipVertical: flipVertical,
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
    required this.flipHorizontal,
    required this.flipVertical,
  });

  final CameraCompositionGuide guide;
  final double? frameAspectRatio;
  final bool flipHorizontal;
  final bool flipVertical;

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
        canvas.save();
        canvas.clipRect(frame);
        canvas.translate(frame.center.dx, frame.center.dy);
        canvas.scale(flipHorizontal ? -1 : 1, flipVertical ? -1 : 1);
        canvas.translate(-frame.center.dx, -frame.center.dy);
        _drawGoldenRectangleGuide(canvas, frame, shadow);
        _drawGoldenRectangleGuide(canvas, frame, line);
        canvas.restore();
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

  void _drawGoldenRectangleGuide(Canvas canvas, Rect frame, Paint paint) {
    const phi = 1.618033988749895;
    final landscape = frame.width >= frame.height;
    final Rect goldenFrame;
    if (landscape) {
      final width = math.min(frame.width, frame.height * phi);
      goldenFrame = Rect.fromLTWH(
        frame.center.dx - width / 2,
        frame.top,
        width,
        frame.height,
      );
    } else {
      final height = math.min(frame.height, frame.width * phi);
      goldenFrame = Rect.fromLTWH(
        frame.left,
        frame.center.dy - height / 2,
        frame.width,
        height,
      );
    }

    canvas.drawRect(goldenFrame, paint);

    var remaining = goldenFrame;
    final cuts = <_GoldenCut>[];
    var direction = landscape ? 0 : 1;

    for (var index = 0; index < 8; index++) {
      if (remaining.width < 2 || remaining.height < 2) break;
      final side = math.min(remaining.width, remaining.height);
      late final Rect square;
      late final Rect next;
      final cutDirection = direction % 4;

      if (cutDirection == 0) {
        square = Rect.fromLTWH(remaining.left, remaining.top, side, side);
        next = Rect.fromLTRB(
          square.right,
          remaining.top,
          remaining.right,
          remaining.bottom,
        );
        if (next.width > 0) {
          canvas.drawLine(
            Offset(square.right, remaining.top),
            Offset(square.right, remaining.bottom),
            paint,
          );
        }
      } else if (cutDirection == 1) {
        square = Rect.fromLTWH(remaining.left, remaining.top, side, side);
        next = Rect.fromLTRB(
          remaining.left,
          square.bottom,
          remaining.right,
          remaining.bottom,
        );
        if (next.height > 0) {
          canvas.drawLine(
            Offset(remaining.left, square.bottom),
            Offset(remaining.right, square.bottom),
            paint,
          );
        }
      } else if (cutDirection == 2) {
        square = Rect.fromLTWH(
          remaining.right - side,
          remaining.top,
          side,
          side,
        );
        next = Rect.fromLTRB(
          remaining.left,
          remaining.top,
          square.left,
          remaining.bottom,
        );
        if (next.width > 0) {
          canvas.drawLine(
            Offset(square.left, remaining.top),
            Offset(square.left, remaining.bottom),
            paint,
          );
        }
      } else {
        square = Rect.fromLTWH(
          remaining.left,
          remaining.bottom - side,
          side,
          side,
        );
        next = Rect.fromLTRB(
          remaining.left,
          remaining.top,
          remaining.right,
          square.top,
        );
        if (next.height > 0) {
          canvas.drawLine(
            Offset(remaining.left, square.top),
            Offset(remaining.right, square.top),
            paint,
          );
        }
      }

      cuts.add(_GoldenCut(cutDirection, square));
      remaining = next;
      direction++;
    }

    final spiral = Path();
    var started = false;
    for (final cut in cuts) {
      final square = cut.square;
      late final Offset start;
      late final Offset end;
      late final Offset control;
      if (cut.direction == 0) {
        start = square.bottomLeft;
        end = square.topRight;
        control = square.topLeft;
      } else if (cut.direction == 1) {
        start = square.topLeft;
        end = square.bottomRight;
        control = square.topRight;
      } else if (cut.direction == 2) {
        start = square.topRight;
        end = square.bottomLeft;
        control = square.bottomRight;
      } else {
        start = square.bottomRight;
        end = square.topLeft;
        control = square.bottomLeft;
      }
      if (!started) {
        spiral.moveTo(start.dx, start.dy);
        started = true;
      }
      spiral.quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
    }
    canvas.drawPath(spiral, paint);
  }

  @override
  bool shouldRepaint(covariant _CompositionGuidePainter oldDelegate) =>
      oldDelegate.guide != guide ||
      oldDelegate.frameAspectRatio != frameAspectRatio ||
      oldDelegate.flipHorizontal != flipHorizontal ||
      oldDelegate.flipVertical != flipVertical;
}

class _GoldenCut {
  const _GoldenCut(this.direction, this.square);

  final int direction;
  final Rect square;
}
