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
  CropDraft _cropDraft = const CropDraft();
  int _imageWidth = 1;
  int _imageHeight = 1;
  int _decodeGeneration = 0;
  bool _hasDecodedSize = false;
  bool _applyingCrop = false;

  @override
  void initState() {
    super.initState();
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
            : InteractiveViewer(
                minScale: 0.75,
                maxScale: 6,
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
