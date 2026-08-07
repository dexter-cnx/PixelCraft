import 'package:flutter/foundation.dart';

import '../core/edit_graph.dart';

enum GpuPreviewBackendKind {
  fallback,
  androidOpenGl,
  iosMetal,
}

@immutable
class GpuPreviewCapabilities {
  const GpuPreviewCapabilities({
    required this.backend,
    required this.supportsLut33,
    required this.supportsMasks,
    required this.supportsOverlays,
    required this.supportedNodeTypes,
    this.maxLutSize = 33,
  });

  final GpuPreviewBackendKind backend;
  final bool supportsLut33;
  final bool supportsMasks;
  final bool supportsOverlays;
  final Set<EditNodeType> supportedNodeTypes;
  final int maxLutSize;

  bool supportsNode(EditNodeType type) => supportedNodeTypes.contains(type);
}

@immutable
class GpuPreviewFilmState {
  const GpuPreviewFilmState({
    required this.profileId,
    required this.strength,
  });

  final String profileId;
  final double strength;

  GpuPreviewFilmState normalized() => GpuPreviewFilmState(
        profileId: profileId,
        strength: strength.clamp(0.0, 1.0).toDouble(),
      );
}

@immutable
class GpuPreviewViewport {
  const GpuPreviewViewport({
    required this.width,
    required this.height,
    required this.devicePixelRatio,
  });

  final double width;
  final double height;
  final double devicePixelRatio;
}

/// Platform renderers implement this contract without moving frame pixels
/// through Dart. Dart sends small state/recipe changes only.
abstract interface class GpuPreviewRenderer {
  GpuPreviewCapabilities get capabilities;

  Future<void> initialize();

  Future<void> setViewport(GpuPreviewViewport viewport);

  Future<void> setFilm(GpuPreviewFilmState film);

  Future<void> setEditGraph(EditGraphDocument graph);

  Future<void> setEnabled(bool enabled);

  Future<void> dispose();
}

/// Contract used while the native GPU renderer is being introduced.
///
/// Camera's current ColorFilter.matrix implementation is a visual fallback,
/// not the reference implementation. It intentionally reports no real 33³ LUT
/// support so callers can distinguish approximation from parity-capable GPU.
class FallbackGpuPreviewRenderer implements GpuPreviewRenderer {
  FallbackGpuPreviewRenderer();

  GpuPreviewFilmState _film = const GpuPreviewFilmState(
    profileId: '',
    strength: 0,
  );
  EditGraphDocument _graph = const EditGraphDocument();
  bool _enabled = true;

  GpuPreviewFilmState get film => _film;
  EditGraphDocument get graph => _graph;
  bool get enabled => _enabled;

  @override
  GpuPreviewCapabilities get capabilities => const GpuPreviewCapabilities(
        backend: GpuPreviewBackendKind.fallback,
        supportsLut33: false,
        supportsMasks: false,
        supportsOverlays: false,
        supportedNodeTypes: <EditNodeType>{EditNodeType.filmProfile},
      );

  @override
  Future<void> initialize() async {}

  @override
  Future<void> setViewport(GpuPreviewViewport viewport) async {}

  @override
  Future<void> setFilm(GpuPreviewFilmState film) async {
    _film = film.normalized();
  }

  @override
  Future<void> setEditGraph(EditGraphDocument graph) async {
    _graph = graph;
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
  }

  @override
  Future<void> dispose() async {}
}
