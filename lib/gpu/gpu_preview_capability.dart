import 'package:flutter/foundation.dart';

import '../core/edit_graph.dart';
import 'gpu_preview_renderer.dart';
import 'native_gpu_preview_bridge.dart';

enum GpuPreviewFallbackReason {
  protocolMismatch,
  backendUnavailable,
  lut33Unsupported,
  shaderSelfTestFailed,
  nativeAssetsUnavailable,
  rendererInitializationFailed,
  runtimeRenderFailure,
  blacklisted,
}

@immutable
class GpuPreviewCapabilityDecision {
  const GpuPreviewCapabilityDecision._({
    required this.useNativeGpu,
    required this.capabilities,
    this.fallbackReason,
    this.detail,
  });

  const GpuPreviewCapabilityDecision.native({
    required GpuPreviewCapabilities capabilities,
  }) : this._(
          useNativeGpu: true,
          capabilities: capabilities,
        );

  const GpuPreviewCapabilityDecision.fallback({
    required GpuPreviewFallbackReason reason,
    required GpuPreviewCapabilities capabilities,
    String? detail,
  }) : this._(
          useNativeGpu: false,
          capabilities: capabilities,
          fallbackReason: reason,
          detail: detail,
        );

  final bool useNativeGpu;
  final GpuPreviewCapabilities capabilities;
  final GpuPreviewFallbackReason? fallbackReason;
  final String? detail;
}

/// Central G0.3 policy for deciding whether the native preview backend may be
/// used. Callers should fall back to the existing Camera matrix approximation
/// whenever this policy returns [GpuPreviewCapabilityDecision.useNativeGpu]
/// as false.
///
/// This policy never modifies source/captured pixels. Fallback is preview-only.
class GpuPreviewCapabilityPolicy {
  const GpuPreviewCapabilityPolicy();

  static const _fallbackCapabilities = GpuPreviewCapabilities(
    backend: GpuPreviewBackendKind.fallback,
    supportsLut33: false,
    supportsMasks: false,
    supportsOverlays: false,
    supportedNodeTypes: <EditNodeType>{EditNodeType.filmProfile},
  );

  GpuPreviewCapabilityDecision evaluate(NativeGpuProbe probe) {
    if (probe.protocolVersion != gpuPreviewProtocolVersion) {
      return GpuPreviewCapabilityDecision.fallback(
        reason: GpuPreviewFallbackReason.protocolMismatch,
        capabilities: _fallbackCapabilities,
        detail: 'native=${probe.protocolVersion} dart=$gpuPreviewProtocolVersion',
      );
    }
    if (probe.blacklisted) {
      return GpuPreviewCapabilityDecision.fallback(
        reason: GpuPreviewFallbackReason.blacklisted,
        capabilities: _fallbackCapabilities,
        detail: probe.failureDetail,
      );
    }
    if (!probe.assetsLoaded) {
      return GpuPreviewCapabilityDecision.fallback(
        reason: GpuPreviewFallbackReason.nativeAssetsUnavailable,
        capabilities: _fallbackCapabilities,
        detail: probe.failureDetail,
      );
    }
    if (!probe.available) {
      return GpuPreviewCapabilityDecision.fallback(
        reason: GpuPreviewFallbackReason.backendUnavailable,
        capabilities: _fallbackCapabilities,
        detail: probe.failureDetail,
      );
    }
    if (!probe.selfTestPassed) {
      return GpuPreviewCapabilityDecision.fallback(
        reason: GpuPreviewFallbackReason.shaderSelfTestFailed,
        capabilities: _fallbackCapabilities,
        detail: probe.failureDetail,
      );
    }
    if (!probe.supportsLut33 || probe.maxLutSize < 33) {
      return const GpuPreviewCapabilityDecision.fallback(
        reason: GpuPreviewFallbackReason.lut33Unsupported,
        capabilities: _fallbackCapabilities,
      );
    }

    return GpuPreviewCapabilityDecision.native(
      capabilities: GpuPreviewCapabilities(
        backend: probe.backend,
        supportsLut33: true,
        supportsMasks: false,
        supportsOverlays: false,
        supportedNodeTypes: const <EditNodeType>{EditNodeType.filmProfile},
        maxLutSize: probe.maxLutSize,
      ),
    );
  }

  GpuPreviewCapabilityDecision rendererInitializationFailed({String? detail}) =>
      GpuPreviewCapabilityDecision.fallback(
        reason: GpuPreviewFallbackReason.rendererInitializationFailed,
        capabilities: _fallbackCapabilities,
        detail: detail,
      );

  GpuPreviewCapabilityDecision runtimeRenderFailed({String? detail}) =>
      GpuPreviewCapabilityDecision.fallback(
        reason: GpuPreviewFallbackReason.runtimeRenderFailure,
        capabilities: _fallbackCapabilities,
        detail: detail,
      );
}
