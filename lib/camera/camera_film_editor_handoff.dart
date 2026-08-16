import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/editor_controller.dart';
import '../ui/screens/product_editor_screen.dart';
import 'camera_look_state.dart';

/// Opens the normal Editor for a camera capture, then applies the transient
/// camera look after the source has finished loading.
///
/// This is a PF2 bridge only. PF3 will replace capture -> editor with clean
/// capture -> Rust authoritative full-resolution render -> JPEG Gallery save.
/// The handoff deliberately commits in canonical order: Adjust -> Film ->
/// Creative. Each editor preview request is allowed to drain before the next
/// one so the editor's latest-value-wins queue cannot coalesce an intermediate
/// adjustment away.
class CameraFilmEditorHandoff extends ConsumerStatefulWidget {
  const CameraFilmEditorHandoff({
    super.key,
    required this.imagePath,
    required this.profileId,
    required this.strength,
    this.look,
  });

  final String imagePath;

  /// Legacy PF1 Film fields retained for compatibility with existing callers.
  final String profileId;
  final double strength;

  /// PF2 composed look. When present this takes precedence over [profileId]
  /// and [strength].
  final CameraLookState? look;

  @override
  ConsumerState<CameraFilmEditorHandoff> createState() =>
      _CameraFilmEditorHandoffState();
}

class _CameraFilmEditorHandoffState
    extends ConsumerState<CameraFilmEditorHandoff> {
  bool _sawSourceLoad = false;
  bool _lookScheduled = false;

  CameraLookState get _initialLook => widget.look ??
      CameraLookState(
        filmProfileId: widget.profileId,
        filmStrength: widget.profileId.isEmpty ? 0 : widget.strength,
      );

  bool get _hasInitialLook {
    final look = _initialLook;
    return look.hasFilm ||
        look.hasCreative ||
        look.adjustmentValue('brightness') != 1 ||
        look.adjustmentValue('contrast') != 1 ||
        look.adjustmentValue('saturation') != 1;
  }

  @override
  Widget build(BuildContext context) {
    final editor = ref.watch(editorProvider);

    if (editor.isBusy) {
      _sawSourceLoad = true;
    }

    final canApplyInitialLook = _hasInitialLook &&
        _sawSourceLoad &&
        !_lookScheduled &&
        !editor.isBusy &&
        !editor.isGeneratingFilmPreviews &&
        editor.previewBytes != null;

    if (canApplyInitialLook) {
      _lookScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        try {
          await _applyInitialLook();
        } catch (_) {
          if (mounted) setState(() => _lookScheduled = false);
        }
      });
    }

    return ProductEditorScreen(imagePath: widget.imagePath);
  }

  Future<void> _applyInitialLook() async {
    final controller = ref.read(editorProvider.notifier);
    final look = _initialLook;

    for (final id in const ['brightness', 'contrast', 'saturation']) {
      final value = look.adjustmentValue(id);
      if ((value - 1).abs() <= 0.000001) continue;
      controller.selectFilter(id);
      await controller.commitFilterValue(value);
      await _waitForPreviewIdle();
      if (!mounted) return;
    }

    if (look.hasFilm) {
      await controller.selectFilmProfile(look.filmProfileId);
      await _waitForPreviewIdle();
      if (!mounted) return;
      if (look.filmStrength < 0.999) {
        await controller.updateFilmProfileStrength(look.filmStrength);
        await _waitForPreviewIdle();
        if (!mounted) return;
      }
    }

    if (look.hasCreative) {
      await controller.applyCreativeFilter(look.creativeFilterId);
      await _waitForPreviewIdle();
      if (!mounted) return;
      if (look.creativeFilterStrength < 0.999) {
        await controller.updateCreativeFilterValue(look.creativeFilterStrength);
        await _waitForPreviewIdle();
      }
    }
  }

  Future<void> _waitForPreviewIdle() async {
    while (mounted && ref.read(editorProvider).isPreviewProcessing) {
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
  }
}
