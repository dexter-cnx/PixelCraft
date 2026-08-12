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
  final String? surfaceId;

  Map<String, Object?> toMap() => <String, Object?>{
        'kind': kind.name,
        'width': width,
        'height': height,
        'devicePixelRatio': devicePixelRatio,
        if (surfaceId != null) 'surfaceId': surfaceId,
      };
}

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
