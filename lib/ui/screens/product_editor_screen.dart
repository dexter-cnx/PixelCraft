import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/editor_controller.dart';
import 'editor_screen.dart';

/// Product-facing Editor entry point.
///
/// [EditorScreen] continues to own the editing transaction/runtime UI. This
/// shell adds product UX that can be expressed entirely through the existing
/// Editor controller without creating a second semantic editing model.
class ProductEditorScreen extends ConsumerStatefulWidget {
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
  ConsumerState<ProductEditorScreen> createState() =>
      _ProductEditorScreenState();
}

class _ProductEditorScreenState extends ConsumerState<ProductEditorScreen> {
  static const _wideLayoutBreakpoint = 900.0;
  static const _wideToolPanelWidth = 360.0;
  static const _wideContentGap = 20.0;
  static const _contentPadding = 16.0;
  static const _compareCanvasInset = 16.0;

  @override
  void initState() {
    super.initState();
    // showOriginal is presentation-only state held by the app-wide editor
    // provider. Reset it at every product-editor session boundary so a Compare
    // choice from the previous photo cannot leak into a new/recovered session.
    ref.read(editorProvider.notifier).setShowOriginal(false);
  }

  double _compareRightInset(double width) {
    if (width < _wideLayoutBreakpoint) return _compareCanvasInset;
    return _contentPadding +
        _wideToolPanelWidth +
        _wideContentGap +
        _compareCanvasInset;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorProvider);
    final compareBlocked = state.previewBytes == null ||
        state.isBusy ||
        state.isPreviewProcessing ||
        state.isExporting;

    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          EditorScreen(
            imageBytes: widget.imageBytes,
            imagePath: widget.imagePath,
            recoveryRecipe: widget.recoveryRecipe,
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + kToolbarHeight + 12,
            right: _compareRightInset(constraints.maxWidth),
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
      ),
    );
  }
}
