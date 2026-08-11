import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/editor_controller.dart';
import '../ui/screens/editor_screen.dart';

/// Opens the normal Editor for a camera capture, then applies the Film Profile
/// selected in the live viewfinder once the new source has finished loading.
class CameraFilmEditorHandoff extends ConsumerStatefulWidget {
  const CameraFilmEditorHandoff({
    super.key,
    required this.imagePath,
    required this.profileId,
    required this.strength,
  });

  final String imagePath;
  final String profileId;
  final double strength;

  @override
  ConsumerState<CameraFilmEditorHandoff> createState() =>
      _CameraFilmEditorHandoffState();
}

class _CameraFilmEditorHandoffState
    extends ConsumerState<CameraFilmEditorHandoff> {
  bool _sawSourceLoad = false;
  bool _filmScheduled = false;

  @override
  Widget build(BuildContext context) {
    final editor = ref.watch(editorProvider);

    if (editor.isBusy) {
      _sawSourceLoad = true;
    }

    final canApplyInitialFilm =
        widget.profileId.isNotEmpty &&
        _sawSourceLoad &&
        !_filmScheduled &&
        !editor.isBusy &&
        !editor.isGeneratingFilmPreviews &&
        editor.previewBytes != null &&
        editor.selectedFilmProfile != widget.profileId;

    if (canApplyInitialFilm) {
      _filmScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final controller = ref.read(editorProvider.notifier);
        await controller.selectFilmProfile(widget.profileId);
        if (!mounted) return;

        if (ref.read(editorProvider).selectedFilmProfile != widget.profileId) {
          setState(() => _filmScheduled = false);
          return;
        }

        if (widget.strength < 0.999) {
          await controller.updateFilmProfileStrength(widget.strength);
        }
      });
    }

    return EditorScreen(imagePath: widget.imagePath);
  }
}
