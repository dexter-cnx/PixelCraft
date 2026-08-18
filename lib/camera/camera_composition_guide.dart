import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CameraCompositionGuide { off, thirds }

extension CameraCompositionGuideX on CameraCompositionGuide {
  static const preferenceKey = 'camera.composition_guide';

  String get wireName => switch (this) {
    CameraCompositionGuide.off => 'off',
    CameraCompositionGuide.thirds => 'thirds',
  };

  String get label => switch (this) {
    CameraCompositionGuide.off => 'Off',
    CameraCompositionGuide.thirds => 'Thirds / Nines',
  };

  static CameraCompositionGuide parse(String? value) => switch (value) {
    'thirds' => CameraCompositionGuide.thirds,
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
    super.key,
  });

  final CameraCompositionGuide guide;

  @override
  Widget build(BuildContext context) {
    if (guide == CameraCompositionGuide.off) {
      return const SizedBox.shrink();
    }
    return const IgnorePointer(
      child: CustomPaint(
        painter: _ThirdsGuidePainter(),
        size: Size.infinite,
      ),
    );
  }
}

class _ThirdsGuidePainter extends CustomPainter {
  const _ThirdsGuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.42)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.72)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final dot = Paint()
      ..color = Colors.white.withValues(alpha: 0.82)
      ..style = PaintingStyle.fill;

    final xs = <double>[size.width / 3, size.width * 2 / 3];
    final ys = <double>[size.height / 3, size.height * 2 / 3];

    for (final x in xs) {
      canvas
        ..drawLine(Offset(x, 0), Offset(x, size.height), shadow)
        ..drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (final y in ys) {
      canvas
        ..drawLine(Offset(0, y), Offset(size.width, y), shadow)
        ..drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    for (final x in xs) {
      for (final y in ys) {
        canvas.drawCircle(Offset(x, y), 2.4, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ThirdsGuidePainter oldDelegate) => false;
}
