import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/gpu/gpu_preview_capability.dart';
import 'package:pixelcraft/gpu/gpu_preview_renderer.dart';
import 'package:pixelcraft/gpu/native_gpu_preview_bridge.dart';

void main() {
  const policy = GpuPreviewCapabilityPolicy();

  NativeGpuProbe probe({
    int protocolVersion = gpuPreviewProtocolVersion,
    bool available = true,
    bool supportsLut33 = true,
    int maxLutSize = 33,
    bool selfTestPassed = true,
    bool assetsLoaded = true,
    bool blacklisted = false,
  }) =>
      NativeGpuProbe(
        protocolVersion: protocolVersion,
        backend: GpuPreviewBackendKind.androidOpenGl,
        available: available,
        supportsLut33: supportsLut33,
        maxLutSize: maxLutSize,
        renderer: 'test-renderer',
        version: 'OpenGL ES 3.0',
        selfTestPassed: selfTestPassed,
        assetsLoaded: assetsLoaded,
        blacklisted: blacklisted,
        cached: false,
      );

  test('eligible Android backend uses native GPU', () {
    final decision = policy.evaluate(probe());

    expect(decision.useNativeGpu, isTrue);
    expect(decision.fallbackReason, isNull);
    expect(decision.capabilities.backend, GpuPreviewBackendKind.androidOpenGl);
    expect(decision.capabilities.supportsLut33, isTrue);
  });

  test('protocol mismatch falls back', () {
    final decision = policy.evaluate(probe(protocolVersion: 999));

    expect(decision.useNativeGpu, isFalse);
    expect(decision.fallbackReason, GpuPreviewFallbackReason.protocolMismatch);
  });

  test('missing native assets has a distinct fallback reason', () {
    final decision = policy.evaluate(probe(assetsLoaded: false));

    expect(decision.useNativeGpu, isFalse);
    expect(
      decision.fallbackReason,
      GpuPreviewFallbackReason.nativeAssetsUnavailable,
    );
  });

  test('backend unavailable has a distinct fallback reason', () {
    final decision = policy.evaluate(probe(available: false));

    expect(decision.useNativeGpu, isFalse);
    expect(
      decision.fallbackReason,
      GpuPreviewFallbackReason.backendUnavailable,
    );
  });

  test('shader self-test failure is not reported as LUT unsupported', () {
    final decision = policy.evaluate(
      probe(selfTestPassed: false, supportsLut33: false),
    );

    expect(decision.useNativeGpu, isFalse);
    expect(
      decision.fallbackReason,
      GpuPreviewFallbackReason.shaderSelfTestFailed,
    );
  });

  test('LUT33 unsupported falls back after self-test passes', () {
    final decision = policy.evaluate(probe(supportsLut33: false));

    expect(decision.useNativeGpu, isFalse);
    expect(
      decision.fallbackReason,
      GpuPreviewFallbackReason.lut33Unsupported,
    );
  });

  test('blacklisted GPU always falls back', () {
    final decision = policy.evaluate(probe(blacklisted: true));

    expect(decision.useNativeGpu, isFalse);
    expect(decision.fallbackReason, GpuPreviewFallbackReason.blacklisted);
  });

  test('renderer init and runtime failures map to fallback', () {
    expect(
      policy.rendererInitializationFailed().fallbackReason,
      GpuPreviewFallbackReason.rendererInitializationFailed,
    );
    expect(
      policy.runtimeRenderFailed().fallbackReason,
      GpuPreviewFallbackReason.runtimeRenderFailure,
    );
  });
}
