import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'editor_controller.dart';

class CropCommitCoordinator {
  const CropCommitCoordinator(this.ref);

  final Ref ref;

  Future<void> commit({
    required double x,
    required double y,
    required double width,
    required double height,
  }) async {
    final state = ref.read(editorProvider);
    final original = state.originalBytes;
    if (original == null || state.isBusy || state.isPreviewProcessing) return;

    final engine = ref.read(imageEngineProvider);
    await engine.applyCropInBackground(
      x: x,
      y: y,
      width: width,
      height: height,
    );

    // Keep EditorController as the UI/session owner. The crop is committed by
    // the same Rust engine, then the authoritative recipe is replayed through
    // the controller so Undo/Redo/export/persistence stay on the normal path.
    final recipe = await engine.exportSessionRecipeInBackground();
    await ref.read(editorProvider.notifier).restore(original, recipe);
  }
}

final cropCommitCoordinatorProvider = Provider<CropCommitCoordinator>(
  CropCommitCoordinator.new,
);
