import 'package:flutter/foundation.dart';

import 'editor_source_contract.dart';
import 'platform_flow_foundation.dart';

abstract final class AppRoutePaths {
  static const root = '/';
  static const camera = '/camera';
  static const desktop = '/desktop';
  static const editor = '/editor';
  static const films = '/films';
  static const gpuEditorLab = '/debug/gpu-editor-lab';

  static String initialLocationForIntent(AppRouteIntent intent) =>
      switch (intent) {
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
    String? imagePath,
    this.imageBytes,
    this.source,
    this.recoveryRecipe,
    this.initialFilmProfileId,
    this.initialFilmStrength = 1,
  }) : _imagePath = imagePath,
       assert(
         (imagePath != null ? 1 : 0) +
                 (imageBytes != null ? 1 : 0) +
                 (source != null ? 1 : 0) ==
             1,
         'Provide exactly one editor source.',
       ),
       assert(
         initialFilmProfileId == null || imagePath != null,
         'Initial camera Film handoff requires a file-backed capture source.',
       );

  final String? _imagePath;
  final List<int>? imageBytes;

  /// Preserves acquisition identity/provenance for Gallery, desktop-open/drop,
  /// and future external-edit flows until the Product Editor boundary.
  final EditorSource? source;

  final String? recoveryRecipe;
  final String? initialFilmProfileId;
  final double initialFilmStrength;

  /// Current Product Editor accepts a filesystem path or bytes. PF4 keeps the
  /// typed source alongside that compatibility boundary rather than discarding
  /// source metadata during routing.
  String? get imagePath {
    final editorSource = source;
    if (editorSource == null) return _imagePath;
    return editorSource.uri.isScheme('file')
        ? editorSource.uri.toFilePath()
        : null;
  }

  bool get hasInitialFilm =>
      initialFilmProfileId != null && initialFilmProfileId!.isNotEmpty;
}
