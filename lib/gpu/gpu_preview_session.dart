import 'package:flutter/foundation.dart';

import 'gpu_preview_renderer.dart';

enum GpuPreviewSurfaceKind {
  cameraExternalOes,
  flutterTexture,
  nativeSurface,
}

enum GpuPreviewSessionState {
  idle,
  created,
  surfaceConfigured,
  paused,
  destroyed,
  failed,
}

@immutable
class GpuPreviewSurfaceConfiguration {
  const GpuPreviewSurfaceConfiguration({
    required this.kind,
    required this.width,
    required this.height,
    required this.devicePixelRatio,
    this.surfaceId,
  });

  final GpuPreviewSurfaceKind kind;
  final int width;
  final int height;
  final double devicePixelRatio;

  /// Opaque native identifier. It identifies a native-owned surface/texture;
  /// it never carries frame bytes through Dart.
  final String? surfaceId;

  Map<String, Object?> toMap() => <String, Object?>{
        'kind': kind.name,
        'width': width,
        'height': height,
        'devicePixelRatio': devicePixelRatio,
        if (surfaceId != null) 'surfaceId': surfaceId,
      };
}

/// Production control-plane lifecycle for a single native preview renderer.
///
/// G0.3 intentionally defines only session/state messages. G1 will attach the
/// Camera producer directly to the Android external-OES input without routing
/// camera frames through Dart or Flutter Rust Bridge.
abstract interface class GpuPreviewRendererSession {
  String? get rendererId;
  GpuPreviewSessionState get state;

  Future<void> createRenderer();
  Future<void> configureSurface(GpuPreviewSurfaceConfiguration surface);
  Future<void> setFilm(GpuPreviewFilmState film);
  Future<void> setStrength(double strength);
  Future<void> setViewport(GpuPreviewViewport viewport);
  Future<void> setEnabled(bool enabled);
  Future<void> pause();
  Future<void> resume();
  Future<void> destroyRenderer();
}
