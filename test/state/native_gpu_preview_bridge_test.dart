import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/gpu/gpu_preview_renderer.dart';
import 'package:pixelcraft/gpu/native_gpu_preview_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(gpuPreviewChannelName);

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('probe parses Android OpenGL protocol v1 capabilities', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'probe');
      return <String, Object?>{
        'protocolVersion': gpuPreviewProtocolVersion,
        'backend': 'androidOpenGl',
        'available': true,
        'supportsLut33': true,
        'maxLutSize': 33,
        'renderer': 'Test GPU',
        'version': 'OpenGL ES 3.2',
      };
    });

    final probe = await const NativeGpuPreviewBridge().probe();

    expect(probe.protocolVersion, gpuPreviewProtocolVersion);
    expect(probe.backend, GpuPreviewBackendKind.androidOpenGl);
    expect(probe.available, isTrue);
    expect(probe.supportsLut33, isTrue);
    expect(probe.maxLutSize, 33);
  });

  test('probe rejects a native protocol mismatch', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return <String, Object?>{
        'protocolVersion': gpuPreviewProtocolVersion + 1,
        'backend': 'androidOpenGl',
      };
    });

    expect(
      const NativeGpuPreviewBridge().probe(),
      throwsA(isA<StateError>()),
    );
  });

  test('reference harness sends protocol version and parses result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'runReferenceHarness');
      expect(
        call.arguments,
        <String, Object?>{'protocolVersion': gpuPreviewProtocolVersion},
      );
      return <String, Object?>{
        'passed': true,
        'maxChannelError': 1 / 255,
        'samples': 8,
      };
    });

    final result =
        await const NativeGpuPreviewBridge().runReferenceHarness();

    expect(result.passed, isTrue);
    expect(result.samples, 8);
    expect(result.maxChannelError, lessThanOrEqualTo(2 / 255));
  });
}
