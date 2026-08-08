import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/gpu/native_gpu_camera_bridge.dart';
import 'package:pixelcraft/gpu/native_gpu_preview_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(gpuPreviewChannelName);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('camera permission request sends protocol only', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'requestCameraPermission');
      expect(call.arguments, <String, Object?>{
        'protocolVersion': gpuPreviewProtocolVersion,
      });
      return true;
    });

    expect(
      await const NativeGpuCameraBridge().requestCameraPermission(),
      isTrue,
    );
  });

  test('available lenses stay small control-plane identifiers', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'availableCameraLenses');
      expect(call.arguments, <String, Object?>{
        'protocolVersion': gpuPreviewProtocolVersion,
      });
      return <String>['back', 'front'];
    });

    expect(
      await const NativeGpuCameraBridge().availableLenses(),
      <String>['back', 'front'],
    );
  });

  test('capture returns only a clean native file path', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'capturePhoto');
      expect(call.arguments, <String, Object?>{
        'protocolVersion': gpuPreviewProtocolVersion,
        'rendererId': 'renderer-1',
      });
      return <String, Object?>{'path': '/tmp/pixelcraft-camera/capture.jpg'};
    });

    expect(
      await const NativeGpuCameraBridge().capturePhoto('renderer-1'),
      '/tmp/pixelcraft-camera/capture.jpg',
    );
  });

  test('switch camera returns native lens direction', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'switchCamera');
      expect(call.arguments, <String, Object?>{
        'protocolVersion': gpuPreviewProtocolVersion,
        'rendererId': 'renderer-1',
      });
      return <String, Object?>{'lensDirection': 'front'};
    });

    expect(
      await const NativeGpuCameraBridge().switchCamera('renderer-1'),
      'front',
    );
  });

  test('runtime failure forwards renderer id and message', () async {
    String? rendererId;
    String? message;
    const bridge = NativeGpuCameraBridge();
    bridge.setRuntimeFailureHandler((id, detail) async {
      rendererId = id;
      message = detail;
    });

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      gpuPreviewChannelName,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('runtimeFailure', <String, Object?>{
          'protocolVersion': gpuPreviewProtocolVersion,
          'rendererId': 'renderer-9',
          'message': 'Metal drawable unavailable',
        }),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(rendererId, 'renderer-9');
    expect(message, 'Metal drawable unavailable');
    bridge.setRuntimeFailureHandler(null);
  });
}
