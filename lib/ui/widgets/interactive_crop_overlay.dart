import 'dart:math' as math;

import 'package:flutter/material.dart';

@immutable
class CropDraft {
  const CropDraft({
    this.x = 0,
    this.y = 0,
    this.width = 1,
    this.height = 1,
    this.aspectRatio,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final double? aspectRatio;

  Rect get normalizedRect => Rect.fromLTWH(x, y, width, height);

  CropDraft copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    double? aspectRatio,
    bool clearAspectRatio = false,
  }) => CropDraft(
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
        aspectRatio: clearAspectRatio ? null : aspectRatio ?? this.aspectRatio,
      );

  static CropDraft centeredForAspect(double? aspectRatio) {
    if (aspectRatio == null) return const CropDraft();
    var width = 1.0;
    var height = 1.0;
    if (aspectRatio >= 1) {
      height = 1 / aspectRatio;
    } else {
      width = aspectRatio;
    }
    return CropDraft(
      x: (1 - width) / 2,
      y: (1 - height) / 2,
      width: width,
      height: height,
      aspectRatio: aspectRatio,
    );
  }
}

enum _CropHandle { move, topLeft, topRight, bottomLeft, bottomRight }

class InteractiveCropOverlay extends StatefulWidget {
  const InteractiveCropOverlay({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  final CropDraft draft;
  final ValueChanged<CropDraft> onChanged;

  @override
  State<InteractiveCropOverlay> createState() => _InteractiveCropOverlayState();
}

class _InteractiveCropOverlayState extends State<InteractiveCropOverlay> {
  static const _minimumSize = 0.08;

  _CropHandle? _handle;
  Offset? _startPoint;
  CropDraft? _startDraft;

  void _start(_CropHandle handle, DragStartDetails details) {
    _handle = handle;
    _startPoint = details.localPosition;
    _startDraft = widget.draft;
  }

  void _update(DragUpdateDetails details, Size size) {
    final handle = _handle;
    final start = _startPoint;
    final initial = _startDraft;
    if (handle == null || start == null || initial == null) return;

    final dx = (details.localPosition.dx - start.dx) / math.max(size.width, 1);
    final dy = (details.localPosition.dy - start.dy) / math.max(size.height, 1);

    if (handle == _CropHandle.move) {
      widget.onChanged(initial.copyWith(
        x: (initial.x + dx).clamp(0.0, 1.0 - initial.width),
        y: (initial.y + dy).clamp(0.0, 1.0 - initial.height),
      ));
      return;
    }

    var left = initial.x;
    var top = initial.y;
    var right = initial.x + initial.width;
    var bottom = initial.y + initial.height;

    switch (handle) {
      case _CropHandle.topLeft:
        left += dx;
        top += dy;
      case _CropHandle.topRight:
        right += dx;
        top += dy;
      case _CropHandle.bottomLeft:
        left += dx;
        bottom += dy;
      case _CropHandle.bottomRight:
        right += dx;
        bottom += dy;
      case _CropHandle.move:
        break;
    }

    left = left.clamp(0.0, right - _minimumSize);
    right = right.clamp(left + _minimumSize, 1.0);
    top = top.clamp(0.0, bottom - _minimumSize);
    bottom = bottom.clamp(top + _minimumSize, 1.0);

    final ratio = initial.aspectRatio;
    if (ratio != null) {
      final anchor = switch (handle) {
        _CropHandle.topLeft => Offset(right, bottom),
        _CropHandle.topRight => Offset(left, bottom),
        _CropHandle.bottomLeft => Offset(right, top),
        _CropHandle.bottomRight => Offset(left, top),
        _CropHandle.move => Offset.zero,
      };
      var width = right - left;
      var height = bottom - top;
      if (width / height > ratio) {
        width = height * ratio;
      } else {
        height = width / ratio;
      }
      switch (handle) {
        case _CropHandle.topLeft:
          left = anchor.dx - width;
          top = anchor.dy - height;
        case _CropHandle.topRight:
          right = anchor.dx + width;
          top = anchor.dy - height;
        case _CropHandle.bottomLeft:
          left = anchor.dx - width;
          bottom = anchor.dy + height;
        case _CropHandle.bottomRight:
          right = anchor.dx + width;
          bottom = anchor.dy + height;
        case _CropHandle.move:
          break;
      }
      left = left.clamp(0.0, 1.0);
      top = top.clamp(0.0, 1.0);
      right = right.clamp(0.0, 1.0);
      bottom = bottom.clamp(0.0, 1.0);
    }

    widget.onChanged(CropDraft(
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
      aspectRatio: initial.aspectRatio,
    ));
  }

  void _end(DragEndDetails details) {
    _handle = null;
    _startPoint = null;
    _startDraft = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final rect = Rect.fromLTWH(
          widget.draft.x * size.width,
          widget.draft.y * size.height,
          widget.draft.width * size.width,
          widget.draft.height * size.height,
        );

        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _CropMaskPainter(rect)),
            ),
            Positioned.fromRect(
              rect: rect,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (details) => _start(_CropHandle.move, details),
                onPanUpdate: (details) => _update(details, size),
                onPanEnd: _end,
                child: const SizedBox.expand(),
              ),
            ),
            _handleWidget(rect.topLeft, _CropHandle.topLeft, size),
            _handleWidget(rect.topRight, _CropHandle.topRight, size),
            _handleWidget(rect.bottomLeft, _CropHandle.bottomLeft, size),
            _handleWidget(rect.bottomRight, _CropHandle.bottomRight, size),
          ],
        );
      },
    );
  }

  Widget _handleWidget(Offset center, _CropHandle handle, Size size) {
    const touchSize = 44.0;
    return Positioned(
      left: center.dx - touchSize / 2,
      top: center.dy - touchSize / 2,
      width: touchSize,
      height: touchSize,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) => _start(handle, details),
        onPanUpdate: (details) => _update(details, size),
        onPanEnd: _end,
        child: Center(
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black87, width: 1.5),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }
}

class _CropMaskPainter extends CustomPainter {
  const _CropMaskPainter(this.rect);

  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final hole = Path()..addRect(rect);
    final mask = Path.combine(PathOperation.difference, full, hole);
    canvas.drawPath(mask, Paint()..color = const Color(0x99000000));

    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(rect, border);

    final grid = Paint()
      ..color = const Color(0x99FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 1; i <= 2; i++) {
      final x = rect.left + rect.width * i / 3;
      final y = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), grid);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
    }
  }

  @override
  bool shouldRepaint(covariant _CropMaskPainter oldDelegate) => oldDelegate.rect != rect;
}
