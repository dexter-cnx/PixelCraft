import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generate Pixel Craft launcher icon source', () async {
    const size = 1024.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final bounds = const ui.Rect.fromLTWH(0, 0, size, size);

    final background = ui.Paint()
      ..shader = const ui.LinearGradient(
        begin: ui.Alignment.topLeft,
        end: ui.Alignment.bottomRight,
        colors: [
          ui.Color(0xFF020817),
          ui.Color(0xFF0A1030),
          ui.Color(0xFF19082F),
        ],
      ).createShader(bounds);
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(bounds.deflate(20), const ui.Radius.circular(190)),
      background,
    );

    final border = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 22
      ..shader = const ui.LinearGradient(
        colors: [
          ui.Color(0xFF1DEBFF),
          ui.Color(0xFF2567FF),
          ui.Color(0xFF9B35FF),
          ui.Color(0xFFFF2ABF),
        ],
      ).createShader(bounds);
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(bounds.deflate(34), const ui.Radius.circular(172)),
      border,
    );

    final pixelGradient = const ui.LinearGradient(
      begin: ui.Alignment.topLeft,
      end: ui.Alignment.bottomRight,
      colors: [
        ui.Color(0xFF20F5F1),
        ui.Color(0xFF1976FF),
        ui.Color(0xFF7437F4),
        ui.Color(0xFFFF1AC7),
      ],
    );
    final pixelPaint = ui.Paint()..shader = pixelGradient.createShader(const ui.Rect.fromLTWH(150, 210, 330, 390));

    const cell = 44.0;
    const gap = 8.0;
    for (var row = 0; row < 6; row++) {
      for (var col = 0; col < 5; col++) {
        final keep = !(row == 0 && col > 2) && !(row == 1 && col == 4) && !(row == 5 && col == 4);
        if (!keep) continue;
        final x = 160 + col * (cell + gap);
        final y = 250 + row * (cell + gap);
        canvas.drawRRect(
          ui.RRect.fromRectAndRadius(
            ui.Rect.fromLTWH(x, y, cell, cell),
            const ui.Radius.circular(5),
          ),
          pixelPaint,
        );
      }
    }

    final scattered = <ui.Rect>[
      const ui.Rect.fromLTWH(410, 220, 32, 32),
      const ui.Rect.fromLTWH(462, 186, 26, 26),
      const ui.Rect.fromLTWH(516, 244, 20, 20),
      const ui.Rect.fromLTWH(552, 316, 28, 28),
      const ui.Rect.fromLTWH(486, 372, 20, 20),
      const ui.Rect.fromLTWH(574, 410, 14, 14),
      const ui.Rect.fromLTWH(442, 454, 22, 22),
    ];
    for (final rect in scattered) {
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(rect, const ui.Radius.circular(4)),
        pixelPaint,
      );
    }

    final strokePath = ui.Path()
      ..moveTo(180, 790)
      ..cubicTo(320, 890, 520, 900, 760, 770)
      ..cubicTo(850, 720, 900, 666, 926, 610)
      ..cubicTo(842, 654, 760, 678, 686, 724)
      ..cubicTo(490, 846, 310, 824, 180, 790)
      ..close();
    final strokePaint = ui.Paint()
      ..shader = const ui.LinearGradient(
        begin: ui.Alignment.centerLeft,
        end: ui.Alignment.centerRight,
        colors: [
          ui.Color(0xFF14DFFF),
          ui.Color(0xFF1675FF),
          ui.Color(0xFF7B39FF),
          ui.Color(0xFFFF22C6),
        ],
      ).createShader(const ui.Rect.fromLTWH(160, 590, 780, 330));
    canvas.drawPath(strokePath, strokePaint);

    final brushPath = ui.Path()
      ..moveTo(350, 760)
      ..cubicTo(388, 722, 422, 682, 446, 627)
      ..cubicTo(465, 584, 515, 569, 548, 590)
      ..cubicTo(582, 612, 582, 660, 552, 696)
      ..cubicTo(506, 752, 430, 782, 350, 760)
      ..close();
    final brushPaint = ui.Paint()
      ..shader = const ui.LinearGradient(
        begin: ui.Alignment.topLeft,
        end: ui.Alignment.bottomRight,
        colors: [
          ui.Color(0xFF23EBFF),
          ui.Color(0xFF2975FF),
          ui.Color(0xFF8F32FF),
          ui.Color(0xFFFF26BD),
        ],
      ).createShader(const ui.Rect.fromLTWH(330, 560, 270, 230));
    canvas.drawPath(brushPath, brushPaint);

    final handlePaint = ui.Paint()
      ..shader = const ui.LinearGradient(
        begin: ui.Alignment.bottomLeft,
        end: ui.Alignment.topRight,
        colors: [
          ui.Color(0xFF1A1D39),
          ui.Color(0xFF303760),
          ui.Color(0xFF111327),
        ],
      ).createShader(const ui.Rect.fromLTWH(500, 220, 290, 430));
    canvas.save();
    canvas.translate(540, 600);
    canvas.rotate(-math.pi / 4.2);
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        const ui.Rect.fromLTWH(-32, -350, 64, 380),
        const ui.Radius.circular(28),
      ),
      handlePaint,
    );
    final ferrulePaint = ui.Paint()
      ..shader = const ui.LinearGradient(
        colors: [ui.Color(0xFFE7E9F5), ui.Color(0xFF8D91A8), ui.Color(0xFFF6F6FF)],
      ).createShader(const ui.Rect.fromLTWH(-36, -4, 72, 70));
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        const ui.Rect.fromLTWH(-38, -24, 76, 70),
        const ui.Radius.circular(15),
      ),
      ferrulePaint,
    );
    canvas.restore();

    void drawStar(double cx, double cy, double radius, ui.Color color) {
      final path = ui.Path();
      for (var i = 0; i < 8; i++) {
        final angle = -math.pi / 2 + i * math.pi / 4;
        final r = i.isEven ? radius : radius * 0.18;
        final x = cx + math.cos(angle) * r;
        final y = cy + math.sin(angle) * r;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      canvas.drawPath(path, ui.Paint()..color = color);
    }

    drawStar(760, 270, 74, const ui.Color(0xFFFFFFFF));
    drawStar(660, 195, 28, const ui.Color(0xFF72D8FF));
    drawStar(838, 390, 24, const ui.Color(0xFFC85DFF));
    drawStar(706, 372, 18, const ui.Color(0xFF7388FF));

    final picture = recorder.endRecording();
    final image = await picture.toImage(1024, 1024);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Unable to encode app icon');

    final directory = Directory('assets/branding')..createSync(recursive: true);
    final file = File('${directory.path}/app_icon.png');
    file.writeAsBytesSync(data.buffer.asUint8List(), flush: true);
    expect(file.existsSync(), isTrue);
  });
}
