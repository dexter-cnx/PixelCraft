import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
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

  static Future<CameraCompositionGuide> load() async {
    final settings = await loadSettings();
    await CameraGoldenSpiralFlipState.instance.ensureLoaded();
    return settings.enabled ? settings.guide : CameraCompositionGuide.off;
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

  Future<void> persist() async {
    if (this == CameraCompositionGuide.off) {
      await persistEnabled(false);
      return;
    }
    await persistStyle();
    await persistEnabled(true);
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

class CameraGoldenSpiralFlip {
  const CameraGoldenSpiralFlip({
    required this.horizontal,
    required this.vertical,
  });

  final bool horizontal;
  final bool vertical;
}

class CameraGoldenSpiralFlipState {
  CameraGoldenSpiralFlipState._();

  static final instance = CameraGoldenSpiralFlipState._();

  final value = ValueNotifier<CameraGoldenSpiralFlip>(
    const CameraGoldenSpiralFlip(horizontal: false, vertical: false),
  );

  Future<void>? _loading;

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    value.value = CameraGoldenSpiralFlip(
      horizontal:
          prefs.getBool(CameraCompositionGuideX.flipHorizontalPreferenceKey) ??
          false,
      vertical:
          prefs.getBool(CameraCompositionGuideX.flipVerticalPreferenceKey) ??
          false,
    );
  }

  Future<void> set({bool? horizontal, bool? vertical}) async {
    final current = value.value;
    final next = CameraGoldenSpiralFlip(
      horizontal: horizontal ?? current.horizontal,
      vertical: vertical ?? current.vertical,
    );
    value.value = next;
    await CameraCompositionGuideX.persistGoldenSpiralFlip(
      horizontal: next.horizontal,
      vertical: next.vertical,
    );
  }
}

class CameraCompositionGuideSettingsControl extends StatefulWidget {
  const CameraCompositionGuideSettingsControl({
    required this.value,
    required this.onChanged,
    this.frameAspectRatio,
    this.enabled = true,
    super.key,
  });

  final CameraCompositionGuide value;
  final ValueChanged<CameraCompositionGuide> onChanged;
  final double? frameAspectRatio;
  final bool enabled;

  @override
  State<CameraCompositionGuideSettingsControl> createState() =>
      _CameraCompositionGuideSettingsControlState();
}

class _CameraCompositionGuideSettingsControlState
    extends State<CameraCompositionGuideSettingsControl> {
  @override
  void initState() {
    super.initState();
    unawaited(CameraGoldenSpiralFlipState.instance.ensureLoaded());
  }

  bool get _isOn => widget.value != CameraCompositionGuide.off;

  CameraCompositionGuide get _activeGuide =>
      _isOn ? widget.value : CameraCompositionGuide.thirds;

  void _toggle(bool enabled) {
    if (!widget.enabled) return;
    widget.onChanged(enabled ? _activeGuide : CameraCompositionGuide.off);
  }

  Future<void> _showGuideDialog() async {
    if (!widget.enabled || !_isOn) return;
    var selected = _activeGuide;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF171717),
          title: Text(
            'camera.guide_choose'.tr(),
            style: const TextStyle(color: Colors.white),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final guide in const [
                    CameraCompositionGuide.thirds,
                    CameraCompositionGuide.goldenRatio,
                    CameraCompositionGuide.goldenSpiral,
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _GuidePreviewCard(
                        guide: guide,
                        selected: selected == guide,
                        frameAspectRatio: widget.frameAspectRatio,
                        onTap: () {
                          setDialogState(() => selected = guide);
                          widget.onChanged(guide);
                        },
                      ),
                    ),
                  if (selected == CameraCompositionGuide.goldenSpiral)
                    ValueListenableBuilder<CameraGoldenSpiralFlip>(
                      valueListenable: CameraGoldenSpiralFlipState.instance.value,
                      builder: (context, flip, _) => Column(
                        children: [
                          SwitchListTile.adaptive(
                            value: flip.horizontal,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'camera.guide_flip_horizontal'.tr(),
                              style: const TextStyle(color: Colors.white),
                            ),
                            onChanged: (value) => unawaited(
                              CameraGoldenSpiralFlipState.instance.set(
                                horizontal: value,
                              ),
                            ),
                          ),
                          SwitchListTile.adaptive(
                            value: flip.vertical,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'camera.guide_flip_vertical'.tr(),
                              style: const TextStyle(color: Colors.white),
                            ),
                            onChanged: (value) => unawaited(
                              CameraGoldenSpiralFlipState.instance.set(
                                vertical: value,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _isOn,
          onChanged: widget.enabled ? _toggle : null,
          title: Text(
            'camera.composition_guide'.tr(),
            style: const TextStyle(color: Colors.white),
          ),
          subtitle: Text(
            _isOn ? 'camera.guide_on'.tr() : 'camera.guide_off'.tr(),
            style: const TextStyle(color: Colors.white54),
          ),
        ),
        if (_isOn) ...[
          const SizedBox(height: 6),
          InkWell(
            onTap: _showGuideDialog,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 116,
              decoration: BoxDecoration(
                color: const Color(0xFF202020),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white24),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraCompositionGuideOverlay(
                    guide: _activeGuide,
                    frameAspectRatio: widget.frameAspectRatio,
                  ),
                  Positioned(
                    left: 12,
                    bottom: 9,
                    child: _GuideLabel(guide: _activeGuide),
                  ),
                  const Positioned(
                    right: 10,
                    top: 10,
                    child: Icon(Icons.edit_outlined, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'camera.composition_guide_hint'.tr(),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _GuidePreviewCard extends StatelessWidget {
  const _GuidePreviewCard({
    required this.guide,
    required this.selected,
    required this.frameAspectRatio,
    required this.onTap,
  });

  final CameraCompositionGuide guide;
  final bool selected;
  final double? frameAspectRatio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 104,
        decoration: BoxDecoration(
          color: const Color(0xFF202020),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFFFF6A00) : Colors.white24,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraCompositionGuideOverlay(
              guide: guide,
              frameAspectRatio: frameAspectRatio,
            ),
            Positioned(
              left: 10,
              bottom: 8,
              child: _GuideLabel(guide: guide),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideLabel extends StatelessWidget {
  const _GuideLabel({required this.guide});

  final CameraCompositionGuide guide;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Text(
          _guideLabel(guide),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

String _guideLabel(CameraCompositionGuide guide) => switch (guide) {
  CameraCompositionGuide.off => 'camera.guide_off'.tr(),
  CameraCompositionGuide.thirds => 'camera.guide_thirds'.tr(),
  CameraCompositionGuide.goldenRatio => 'camera.guide_golden_ratio'.tr(),
  CameraCompositionGuide.goldenSpiral => 'camera.guide_golden_spiral'.tr(),
};

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
    unawaited(CameraGoldenSpiralFlipState.instance.ensureLoaded());
    return ValueListenableBuilder<CameraGoldenSpiralFlip>(
      valueListenable: CameraGoldenSpiralFlipState.instance.value,
      builder: (context, flip, _) => IgnorePointer(
        child: CustomPaint(
          painter: _CompositionGuidePainter(
            guide: guide,
            frameAspectRatio: frameAspectRatio,
            flipHorizontal: flip.horizontal,
            flipVertical: flip.vertical,
          ),
          size: Size.infinite,
        ),
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
        final xs = [
          frame.left + frame.width / 3,
          frame.left + frame.width * 2 / 3,
        ];
        final ys = [
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
        final xs = [
          frame.left + frame.width * minor,
          frame.left + frame.width * major,
        ];
        final ys = [
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
        final goldenFrame = _inscribedGoldenRect(frame);
        canvas.save();
        canvas.clipRect(frame);
        canvas.translate(goldenFrame.center.dx, goldenFrame.center.dy);
        canvas.scale(flipHorizontal ? -1 : 1, flipVertical ? -1 : 1);
        canvas.translate(-goldenFrame.center.dx, -goldenFrame.center.dy);
        _drawGoldenRectangleGuide(canvas, goldenFrame, shadow);
        _drawGoldenRectangleGuide(canvas, goldenFrame, line);
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

  Rect _inscribedGoldenRect(Rect frame) {
    const phi = 1.618033988749895;
    final landscape = frame.width >= frame.height;
    if (landscape) {
      var width = frame.height * phi;
      var height = frame.height;
      if (width > frame.width) {
        width = frame.width;
        height = width / phi;
      }
      return Rect.fromCenter(
        center: frame.center,
        width: width,
        height: height,
      );
    }

    var width = frame.width;
    var height = width * phi;
    if (height > frame.height) {
      height = frame.height;
      width = height / phi;
    }
    return Rect.fromCenter(
      center: frame.center,
      width: width,
      height: height,
    );
  }

  void _drawGoldenRectangleGuide(Canvas canvas, Rect frame, Paint paint) {
    canvas.drawRect(frame, paint);

    var remaining = frame;
    final cuts = <_GoldenCut>[];
    var direction = frame.width >= frame.height ? 0 : 1;

    for (var index = 0; index < 9; index++) {
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
