import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'gpu_preview_renderer.dart';
import 'gpu_preview_session.dart';

const gpuPreviewProtocolVersion = 1;
const gpuPreviewChannelName = 'dev.pixelcraft/gpu_preview_v1';

@immutable
class NativeGpuProbe {
  const NativeGpuProbe({
    required this.protocolVersion,
    required this.backend,
    required this.available,
    required this.supportsLut33,
    required this.maxLutSize,
    required this.renderer,
    required this.version,
    required this.selfTestPassed,
    required this.assetsLoaded,
    required this.blacklisted,
    required this.cached,
    this.failureCode,
    this.failureDetail,
  });

  final int protocolVersion;
  final GpuPreviewBackendKind backend;
  final bool available;
  final bool supportsLut33;
  final int maxLutSize;
  final String renderer;
  final String version;
  final bool selfTestPassed;
  final bool assetsLoaded;
  final bool blacklisted;
  final bool cached;
  final String? failureCode;
  final String? failureDetail;

  bool get protocolCompatible => protocolVersion == gpuPreviewProtocolVersion;

  factory NativeGpuProbe.fromMap(Map<Object?, Object?> map) {
    final backendName = map['backend'] as String? ?? 'fallback';
    final backend = switch (backendName) {
      'androidOpenGl' => GpuPreviewBackendKind.androidOpenGl,
      'iosMetal' => GpuPreviewBackendKind.iosMetal,
      _ => GpuPreviewBackendKind.fallback,
    };

    return NativeGpuProbe(
      protocolVersion: map['protocolVersion'] as int? ?? 0,
      backend: backend,
      available: map['available'] as bool? ?? false,
      supportsLut33: map['supportsLut33'] as bool? ?? false,
      maxLutSize: map['maxLutSize'] as int? ?? 0,
      renderer: map['renderer'] as String? ?? '',
      version: map['version'] as String? ?? '',
      selfTestPassed: map['selfTestPassed'] as bool? ?? false,
      assetsLoaded: map['assetsLoaded'] as bool? ?? false,
      blacklisted: map['blacklisted'] as bool? ?? false,
      cached: map['cached'] as bool? ?? false,
      failureCode: map['failureCode'] as String?,
      failureDetail: map['failureDetail'] as String? ?? map['error'] as String?,
    );
  }
}

@immutable
class NativeGpuHarnessResult {
  const NativeGpuHarnessResult({
    required this.passed,
    required this.maxChannelError,
    required this.samples,
    required this.profileId,
  });

  final bool passed;
  final double maxChannelError;
  final int samples;
  final String profileId;

  factory NativeGpuHarnessResult.fromMap(Map<Object?, Object?> map) => NativeGpuHarnessResult(
        passed: map['passed'] as bool? ?? false,
        maxChannelError: (map['maxChannelError'] as num? ?? 1).toDouble(),
        samples: map['samples'] as int? ?? 0,
        profileId: map['profileId'] as String? ?? '',
      );
}

class NativeGpuPreviewBridge {
  const NativeGpuPreviewBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(gpuPreviewChannelName);

  final MethodChannel _channel;

  Future<NativeGpuProbe> probe({bool forceSelfTest = false}) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'probe',
      <String, Object?>{
        'protocolVersion': gpuPreviewProtocolVersion,
        'forceSelfTest': forceSelfTest,
      },
    );
    if (result == null) throw StateError('Native GPU probe returned no data');
    return NativeGpuProbe.fromMap(result);
  }

  Future<void> invalidateCapabilityCache() => _channel.invokeMethod<void>('invalidateCapabilityCache');

  Future<String> createRenderer() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'createRenderer',
      const <String, Object?>{'protocolVersion': gpuPreviewProtocolVersion},
    );
    final rendererId = result?['rendererId'] as String?;
    if (rendererId == null || rendererId.isEmpty) {
      throw StateError('Native GPU renderer creation returned no rendererId');
    }
    return rendererId;
  }

  Future<void> configureSurface(String rendererId, GpuPreviewSurfaceConfiguration surface) =>
      _invokeRendererControl('configureSurface', rendererId, surface.toMap());

  Future<void> setFilm(String rendererId, GpuPreviewFilmState film) => _invokeRendererControl(
        'setFilm',
        rendererId,
        <String, Object?>{
          'profileId': film.profileId,
          'strength': film.normalized().strength,
        },
      );

  Future<void> setStrength(String rendererId, double strength) => _invokeRendererControl(
        'setStrength',
        rendererId,
        <String, Object?>{'strength': strength.clamp(0.0, 1.0).toDouble()},
      );

  Future<void> setViewport(String rendererId, GpuPreviewViewport viewport) => _invokeRendererControl(
        'setViewport',
        rendererId,
        <String, Object?>{
          'width': viewport.width,
          'height': viewport.height,
          'devicePixelRatio': viewport.devicePixelRatio,
        },
      );

  Future<void> setEnabled(String rendererId, bool enabled) =>
      _invokeRendererControl('setEnabled', rendererId, <String, Object?>{'enabled': enabled});

  Future<void> pause(String rendererId) => _invokeRendererControl('pause', rendererId);
  Future<void> resume(String rendererId) => _invokeRendererControl('resume', rendererId);
  Future<void> destroyRenderer(String rendererId) => _invokeRendererControl('destroyRenderer', rendererId);

  Future<void> _invokeRendererControl(
    String method,
    String rendererId, [
    Map<String, Object?> values = const <String, Object?>{},
  ]) async {
    await _channel.invokeMethod<void>(
      method,
      <String, Object?>{
        'protocolVersion': gpuPreviewProtocolVersion,
        'rendererId': rendererId,
        ...values,
      },
    );
  }

  Future<NativeGpuHarnessResult> runReferenceHarness() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'runReferenceHarness',
      const <String, Object?>{'protocolVersion': gpuPreviewProtocolVersion},
    );
    if (result == null) throw StateError('Native GPU harness returned no data');
    return NativeGpuHarnessResult.fromMap(result);
  }

  Future<NativeGpuHarnessResult> runFilmProfileHarness(String profileId) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'runFilmProfileHarness',
      <String, Object?>{
        'protocolVersion': gpuPreviewProtocolVersion,
        'profileId': profileId,
      },
    );
    if (result == null) throw StateError('Native Film GPU harness returned no data');
    return NativeGpuHarnessResult.fromMap(result);
  }
}

class NativeGpuPreviewSession implements GpuPreviewRendererSession {
  NativeGpuPreviewSession({NativeGpuPreviewBridge? bridge})
      : _bridge = bridge ?? const NativeGpuPreviewBridge();

  final NativeGpuPreviewBridge _bridge;
  bool _hasSurface = false;

  @override
  String? rendererId;

  @override
  GpuPreviewSessionState state = GpuPreviewSessionState.idle;

  String get _requiredRendererId {
    final id = rendererId;
    if (id == null || id.isEmpty) {
      throw StateError('GPU renderer session has not been created');
    }
    return id;
  }

  @override
  Future<void> createRenderer() async {
    if (state != GpuPreviewSessionState.idle && state != GpuPreviewSessionState.destroyed) {
      throw StateError('Cannot create GPU renderer from state $state');
    }
    try {
      rendererId = await _bridge.createRenderer();
      _hasSurface = false;
      state = GpuPreviewSessionState.created;
    } catch (_) {
      state = GpuPreviewSessionState.failed;
      try {
        await _bridge.invalidateCapabilityCache();
      } catch (_) {}
      rethrow;
    }
  }

  @override
  Future<void> configureSurface(GpuPreviewSurfaceConfiguration surface) async {
    await _bridge.configureSurface(_requiredRendererId, surface);
    _hasSurface = true;
    state = GpuPreviewSessionState.surfaceConfigured;
  }

  @override
  Future<void> setFilm(GpuPreviewFilmState film) => _bridge.setFilm(_requiredRendererId, film);

  @override
  Future<void> setStrength(double strength) => _bridge.setStrength(_requiredRendererId, strength);

  @override
  Future<void> setViewport(GpuPreviewViewport viewport) => _bridge.setViewport(_requiredRendererId, viewport);

  @override
  Future<void> setEnabled(bool enabled) => _bridge.setEnabled(_requiredRendererId, enabled);

  @override
  Future<void> pause() async {
    await _bridge.pause(_requiredRendererId);
    state = GpuPreviewSessionState.paused;
  }

  @override
  Future<void> resume() async {
    await _bridge.resume(_requiredRendererId);
    state = _hasSurface ? GpuPreviewSessionState.surfaceConfigured : GpuPreviewSessionState.created;
  }

  @override
  Future<void> destroyRenderer() async {
    final id = rendererId;
    if (id != null && state != GpuPreviewSessionState.destroyed) {
      await _bridge.destroyRenderer(id);
    }
    rendererId = null;
    _hasSurface = false;
    state = GpuPreviewSessionState.destroyed;
  }
}
