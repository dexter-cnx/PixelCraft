import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'gpu_preview_renderer.dart';

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
  });

  final int protocolVersion;
  final GpuPreviewBackendKind backend;
  final bool available;
  final bool supportsLut33;
  final int maxLutSize;
  final String renderer;
  final String version;

  factory NativeGpuProbe.fromMap(Map<Object?, Object?> map) {
    final protocolVersion = map['protocolVersion'] as int? ?? 0;
    if (protocolVersion != gpuPreviewProtocolVersion) {
      throw StateError(
        'GPU preview protocol mismatch: native=$protocolVersion '
        'dart=$gpuPreviewProtocolVersion',
      );
    }

    final backendName = map['backend'] as String? ?? 'fallback';
    final backend = switch (backendName) {
      'androidOpenGl' => GpuPreviewBackendKind.androidOpenGl,
      'iosMetal' => GpuPreviewBackendKind.iosMetal,
      _ => GpuPreviewBackendKind.fallback,
    };

    return NativeGpuProbe(
      protocolVersion: protocolVersion,
      backend: backend,
      available: map['available'] as bool? ?? false,
      supportsLut33: map['supportsLut33'] as bool? ?? false,
      maxLutSize: map['maxLutSize'] as int? ?? 0,
      renderer: map['renderer'] as String? ?? '',
      version: map['version'] as String? ?? '',
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

  factory NativeGpuHarnessResult.fromMap(Map<Object?, Object?> map) =>
      NativeGpuHarnessResult(
        passed: map['passed'] as bool? ?? false,
        maxChannelError: (map['maxChannelError'] as num? ?? 1).toDouble(),
        samples: map['samples'] as int? ?? 0,
        profileId: map['profileId'] as String? ?? '',
      );
}

/// Thin control-plane bridge for native GPU preview backends.
///
/// No image/frame buffers are allowed through this channel. It carries only
/// protocol negotiation, capability data and small renderer state messages.
class NativeGpuPreviewBridge {
  const NativeGpuPreviewBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(gpuPreviewChannelName);

  final MethodChannel _channel;

  Future<NativeGpuProbe> probe() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>('probe');
    if (result == null) {
      throw StateError('Native GPU probe returned no data');
    }
    return NativeGpuProbe.fromMap(result);
  }

  /// G0.2 device-only identity-LUT check.
  Future<NativeGpuHarnessResult> runReferenceHarness() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'runReferenceHarness',
      const <String, Object?>{'protocolVersion': gpuPreviewProtocolVersion},
    );
    if (result == null) {
      throw StateError('Native GPU harness returned no data');
    }
    return NativeGpuHarnessResult.fromMap(result);
  }

  /// Runs the same OpenGL LUT shader against a generated canonical Film LUT
  /// atlas packaged in the Android app. Only the profile id crosses the
  /// channel; atlas bytes and parity fixtures are loaded natively from assets.
  Future<NativeGpuHarnessResult> runFilmProfileHarness(String profileId) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'runFilmProfileHarness',
      <String, Object?>{
        'protocolVersion': gpuPreviewProtocolVersion,
        'profileId': profileId,
      },
    );
    if (result == null) {
      throw StateError('Native Film GPU harness returned no data');
    }
    return NativeGpuHarnessResult.fromMap(result);
  }
}
