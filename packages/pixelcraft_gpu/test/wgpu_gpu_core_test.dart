import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft_gpu/wgpu_gpu_core.dart';

void main() {
  test('decodes the stable wgpu backend ABI mask', () {
    final backends = WgpuBackendSet.fromMask(0xF);

    expect(backends.vulkan, isTrue);
    expect(backends.metal, isTrue);
    expect(backends.dx12, isTrue);
    expect(backends.gl, isTrue);
    expect(backends.any, isTrue);
  });

  test('empty backend mask reports unavailable backend set', () {
    final backends = WgpuBackendSet.fromMask(0);

    expect(backends.any, isFalse);
  });
}
