import 'package:flutter/foundation.dart';

import 'platform_flow_foundation.dart';

abstract final class AppRoutePaths {
  static const root = '/';
  static const camera = '/camera';
  static const desktop = '/desktop';
  static const editor = '/editor';
  static const films = '/films';
  static const gpuEditorLab = '/debug/gpu-editor-lab';

  static String initialLocationForIntent(AppRouteIntent intent) => switch (intent) {
    AppRouteIntent.camera => camera,
    AppRouteIntent.desktopHome => desktop,
    AppRouteIntent.editor => editor,
  };
}

abstract final class AppRouteNames {
  static const camera = 'camera';
  static const desktop = 'desktop';
  static const editor = 'editor';
  static const films = 'films';
  static const gpuEditorLab = 'gpu-editor-lab';
}

@immutable
class EditorRouteData {
  const EditorRouteData({
    this.imagePath,
    this.imageBytes,
    this.recoveryRecipe,
    this.initialFilmProfileId,
    this.initialFilmStrength = 1,
  }) : assert(
         (imagePath == null) != (imageBytes == null),
         'Provide exactly one editor source.',
       ),
       assert(
         initialFilmProfileId == null || imagePath != null,
         'Initial camera Film handoff requires a file-backed source.',
       );

  final String? imagePath;
  final List<int>? imageBytes;
  final String? recoveryRecipe;
  final String? initialFilmProfileId;
  final double initialFilmStrength;

  bool get hasInitialFilm =>
      initialFilmProfileId != null && initialFilmProfileId!.isNotEmpty;
}
