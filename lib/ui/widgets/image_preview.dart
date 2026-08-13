import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/crop_commit_coordinator.dart';
import '../../state/editor_controller.dart';
import 'interactive_crop_overlay.dart';

class ImagePreview extends ConsumerStatefulWidget {
  const ImagePreview({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  ConsumerState<ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends ConsumerState<ImagePreview> {
  static const _minZoom = 0.75;
  static const _maxZoom = 6.0;
  static const _zoomStep = 1.25;

  final TransformationController _transformationController =
      TransformationController();
  CropDraft _cropDraft = const CropDraft();
  int _imageWidth = 1;
  int _imageHeight = 1;
  int _decodeGeneration = 0;
  bool _hasDecodedSize = false;
  bool _applyingCrop = false;
  double _zoom = 1;

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_onTransformChanged);
    _decodeImageSize();
  }

  @override
  void didUpdateWidget(covariant ImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) {
      // Pixel-only edits must not erase an in-progress crop just because the
      // preview bytes changed. _decodeImageSize resets the crop only when the
      // source geometry actually changes.
      _decodeImageSize();
    }
  }

  @override
  void dispose() {
    _transformationController
      ..removeListener(_onTransformChanged)
      ..dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final zoom = _transformationController.value.getMaxScaleOnAxis();
    if ((zoom - _zoom).abs() < 0.005 || !mounted) return;
    setState(() => _zoom = zoom);
  }

  void _setZoom(double value) {
    final zoom = value.clamp(_minZoom, _maxZoom).toDouble();
    final matrix = Matrix4.identity()
      ..setEntry(0, 0, zoom)
      ..setEntry(1, 1, zoom);
    _transformationController.value = matrix;
  }

  void _zoomIn() => _setZoom(_zoom * _zoomStep);

  void _zoomOut() => _setZoom(_zoom / _zoomStep);

  void _fitPreview() {
    _transformationController.value = Matrix4.identity();
  }

  Future<void> _decodeImageSize() async {
    final generation = ++_decodeGeneration;
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;
      frame.image.dispose();
      codec.dispose();
      if (!mounted || generation != _decodeGeneration) return;

      final geometryChanged =
          _hasDecodedSize && (width != _imageWidth || height != _imageHeight);
      setState(() {
        _imageWidth = width;
        _imageHeight = height;
        _hasDecodedSize = true;
        if (geometryChanged) {
          _cropDraft = const CropDraft();
          _fitPreview();
        }
      });
    } catch (_) {
      // Image.memory will surface decode failures through its own rendering path.
    }
  }

  Future<void> _applyCrop() async {
    if (_applyingCrop) return;
    final rect = _cropDraft.normalizedRect;
    if (rect.width >= 0.9999 && rect.height >= 0.9999) return;

    setState(() => _applyingCrop = true);
    try {
      await ref.read(cropCommitCoordinatorProvider).commit(
            x: rect.left,
            y: rect.top,
            width: rect.width,
            height: rect.height,
          );
      if (!mounted) return;
      setState(() => _cropDraft = const CropDraft());
    } finally {
      if (mounted) setState(() => _applyingCrop = false);
    }
  }

  void _setAspect(double? ratio) {
    final sourceAspect =
        _imageHeight > 0 ? _imageWidth / _imageHeight : 1.0;
    setState(
      () => _cropDraft = CropDraft.centeredForAspect(
        ratio,
        sourceAspectRatio: sourceAspect,
      ),
    );
  }

  Rect _containRect(Size canvasSize) {
    final sourceWidth = math.max(_imageWidth, 1).toDouble();
    final sourceHeight = math.max(_imageHeight, 1).toDouble();
    final scale = math.min(
      canvasSize.width / sourceWidth,
      canvasSize.height / sourceHeight,
    );
    final width = sourceWidth * scale;
    final height = sourceHeight * scale;
    return Rect.fromLTWH(
      (canvasSize.width - width) / 2,
      (canvasSize.height - height) / 2,
      width,
      height,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedTool = ref.watch(
      editorProvider.select((state) => state.selectedTool),
    );
    final straightenDegrees = ref.watch(
      editorProvider.select((state) => state.straightenDegrees),
    );
    final busy = ref.watch(
      editorProvider.select(
        (state) => state.isBusy || state.isPreviewProcessing,
      ),
    );
    final cropMode = selectedTool == EditorTool.crop;
    final radians = straightenDegrees * math.pi / 180.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: cropMode
            ? LayoutBuilder(
                builder: (context, constraints) {
                  final canvasSize = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  final imageRect = _containRect(canvasSize);
                  return Stack(
                    children: [
                      Positioned.fromRect(
                        rect: imageRect,
                        child: Image.memory(
                          widget.bytes,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                        ),
                      ),
                      Positioned.fromRect(
                        rect: imageRect,
                        child: IgnorePointer(
                          ignoring: busy || _applyingCrop,
                          child: InteractiveCropOverlay(
                            draft: _cropDraft,
                            onChanged: (draft) =>
                                setState(() => _cropDraft = draft),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 10,
                        right: 10,
                        top: 10,
                        child: _CropAspectBar(
                          selected: _cropDraft.aspectRatio,
                          enabled: !busy && !_applyingCrop,
                          onSelected: _setAspect,
                        ),
                      ),
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: _CropActionBar(
                          applying: _applyingCrop,
                          enabled: !busy,
                          onReset: () => setState(
                            () => _cropDraft = const CropDraft(),
                          ),
                          onApply: _applyCrop,
                        ),
                      ),
                    ],
                  );
                },
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  InteractiveViewer(
                    transformationController: _transformationController,
                    minScale: _minZoom,
                    maxScale: _maxZoom,
                    child: Center(
                      child: Transform.rotate(
                        angle: radians,
                        child: Image.memory(
                          widget.bytes,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: _ZoomToolbar(
                      zoom: _zoom,
                      canZoomOut: _zoom > _minZoom + 0.01,
                      canZoomIn: _zoom < _maxZoom - 0.01,
                      onZoomOut: _zoomOut,
                      onZoomIn: _zoomIn,
                      onFit: _fitPreview,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ZoomToolbar extends StatelessWidget {
  const _ZoomToolbar({
    required this.zoom,
    required this.canZoomOut,
    required this.canZoomIn,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onFit,
  });

  final double zoom;
  final bool canZoomOut;
  final bool canZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(14),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const ValueKey('editor_zoom_out'),
              tooltip: 'Zoom out',
              visualDensity: VisualDensity.compact,
              onPressed: canZoomOut ? onZoomOut : null,
              icon: const Icon(Icons.remove_rounded),
            ),
            SizedBox(
              width: 52,
              child: Text(
                '${(zoom * 100).round()}%',
                key: const ValueKey('editor_zoom_percent'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            IconButton(
              key: const ValueKey('editor_zoom_in'),
              tooltip: 'Zoom in',
              visualDensity: VisualDensity.compact,
              onPressed: canZoomIn ? onZoomIn : null,
              icon: const Icon(Icons.add_rounded),
            ),
            const SizedBox(width: 2),
            TextButton.icon(
              key: const ValueKey('editor_zoom_fit'),
              onPressed: onFit,
              icon: const Icon(Icons.fit_screen_rounded, size: 18),
              label: const Text('Fit'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CropAspectBar extends StatelessWidget {
  const _CropAspectBar({
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final double? selected;
  final bool enabled;
  final ValueChanged<double?> onSelected;

  @override
  Widget build(BuildContext context) {
    const options = <(String, double?)>[
      ('Free', null),
      ('1:1', 1),
      ('4:3', 4 / 3),
      ('3:4', 3 / 4),
      ('16:9', 16 / 9),
      ('9:16', 9 / 16),
    ];

    bool isSelected(double? ratio) {
      if (ratio == null || selected == null) return ratio == selected;
      return (ratio - selected!).abs() < 0.0001;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final option in options) ...[
            ChoiceChip(
              label: Text(option.$1),
              selected: isSelected(option.$2),
              onSelected:
                  enabled ? (_) => onSelected(option.$2) : null,
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _CropActionBar extends StatelessWidget {
  const _CropActionBar({
    required this.applying,
    required this.enabled,
    required this.onReset,
    required this.onApply,
  });

  final bool applying;
  final bool enabled;
  final VoidCallback onReset;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FilledButton.tonalIcon(
          onPressed: enabled && !applying ? onReset : null,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Reset'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: enabled && !applying ? onApply : null,
          icon: applying
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.crop_rounded),
          label: const Text('Apply Crop'),
        ),
      ],
    );
  }
}
