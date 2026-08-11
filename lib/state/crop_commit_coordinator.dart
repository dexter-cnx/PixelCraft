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
    if (state.originalBytes == null || state.isBusy || state.isPreviewProcessing) {
      return;
    }

    // Serialize the entire crop commit through EditorController so competing
    // Apply/Cancel/Undo/Redo/transform actions see isBusy and cannot interleave
    // with the singleton Rust session mutation.
    await ref.read(editorProvider.notifier).commitCrop(
          x: x,
          y: y,
          width: width,
          height: height,
        );
  }
}

final cropCommitCoordinatorProvider = Provider<CropCommitCoordinator>(
  CropCommitCoordinator.new,
);
