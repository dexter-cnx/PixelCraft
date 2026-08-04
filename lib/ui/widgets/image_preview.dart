import 'dart:typed_data';
import 'package:flutter/material.dart';

class ImagePreview extends StatelessWidget {
  const ImagePreview({super.key, required this.bytes});
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: InteractiveViewer(
        minScale: 0.75,
        maxScale: 6,
        child: Center(child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true)),
      ),
    ),
  );
}
