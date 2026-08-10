import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/editor_controller.dart';

class ImagePreview extends ConsumerWidget {
  const ImagePreview({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final straightenDegrees = ref.watch(
      editorProvider.select((state) => state.straightenDegrees),
    );
    final radians = straightenDegrees * math.pi / 180.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: InteractiveViewer(
          minScale: 0.75,
          maxScale: 6,
          child: Center(
            child: Transform.rotate(
              angle: radians,
              child: Image.memory(
                bytes,
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
