import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/gpu/android_gpu_camera_bridge.dart';
import 'package:pixelcraft/gpu/native_gpu_preview_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(gpuPreviewChannelName);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('camera permission request stays control-plane only', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'requestCameraPermission');
      expect(call.arguments, <String, Object?>{
        'protocolVersion': gpuPreviewProtocolVersion,
      });
      return true;
    });

    expect(
      await const AndroidGpuCameraBridge().requestCameraPermission(),
      isTrue,
    );
  });

  test('available lenses are returned as small identifiers', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'availableCameraLenses');
      return <String>['back', 'front'];
    });

    expect(
      await const AndroidGpuCameraBridge().availableLenses(),
      <String>['back', 'front'],
    );
  });

  test('capture returns only the clean JPEG path', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'capturePhoto');
      expect(call.arguments, <String, Object?>{
        'protocolVersion': gpuPreviewProtocolVersion,
        'rendererId': 'renderer-1',
      });
      return <String, Object?>{
        'path': '/cache/pixelcraft-camera/capture.jpg',
      };
    });

    expect(
      await const AndroidGpuCameraBridge().capturePhoto('renderer-1'),
      '/cache/pixelcraft-camera/capture.jpg',
    );
  });

  test('switch camera returns native lens direction', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'switchCamera');
      return <String, Object?>{'lensDirection': 'front'};
    });

    expect(
      await const AndroidGpuCameraBridge().switchCamera('renderer-1'),
      'front',
    );
  });
}
