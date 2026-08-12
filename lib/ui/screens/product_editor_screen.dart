import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/editor_controller.dart';
import 'editor_screen.dart';

/// Product-facing Editor entry point.
///
/// [EditorScreen] continues to own the editing transaction/runtime UI. This
/// shell adds product UX that can be expressed entirely through the existing
/// Editor controller without creating a second semantic editing model.
class ProductEditorScreen extends ConsumerWidget {
  const ProductEditorScreen({
    super.key,
    this.imageBytes,
    this.imagePath,
    this.recoveryRecipe,
  }) : assert(
          (imageBytes == null) != (imagePath == null),
          'Provide exactly one of imageBytes or imagePath.',
        );

  final List<int>? imageBytes;
  final String? imagePath;
  final String? recoveryRecipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final compareBlocked = state.previewBytes == null ||
        state.isBusy ||
        state.isPreviewProcessing ||
        state.isExporting;

    return Stack(
      children: [
        EditorScreen(
          imageBytes: imageBytes,
          imagePath: imagePath,
          recoveryRecipe: recoveryRecipe,
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + kToolbarHeight + 12,
          right: 16,
          child: SafeArea(
            top: false,
            left: false,
            child: Material(
              color: Colors.transparent,
              child: FilledButton.tonalIcon(
                key: const ValueKey('editor_compare_button'),
                onPressed: compareBlocked
                    ? null
                    : () => ref
                        .read(editorProvider.notifier)
                        .setShowOriginal(!state.showOriginal),
                icon: Icon(
                  state.showOriginal
                      ? Icons.auto_fix_high_rounded
                      : Icons.compare_rounded,
                  size: 18,
                ),
                label: Text(state.showOriginal ? 'Edited' : 'Before'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
