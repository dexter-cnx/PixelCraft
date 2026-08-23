import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_routes.dart';
import '../../app/editor_source_contract.dart';
import '../../app/platform_flow_foundation.dart';
import '../../app/platform_media_services.dart';
import 'camera_film_preview_screen_g1.dart' as legacy;

/// PF4 routing wrapper around the current G1 camera runtime.
///
/// Camera capture behavior remains owned by G1. Gallery acquisition is adapted
/// here so selected media enters the canonical Product Editor route with its
/// typed [EditorSource] metadata intact instead of using the legacy direct
/// CameraFilmEditorHandoff path.
class CameraFilmPreviewScreen extends StatelessWidget {
  const CameraFilmPreviewScreen({super.key, this.mediaPickerService});

  final MediaPickerService? mediaPickerService;

  @override
  Widget build(BuildContext context) {
    final picker = LegacyGalleryEditorRoutingPicker(
      picker: mediaPickerService ?? ImagePickerMediaService(),
      onOpenEditor: (source) async {
        if (!context.mounted) return;
        await context.pushNamed<void>(
          AppRouteNames.editor,
          extra: EditorRouteData(source: source),
        );
      },
    );

    return legacy.CameraFilmPreviewScreen(mediaPickerService: picker);
  }
}
