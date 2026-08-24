import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/gpu/native_gpu_preview_bridge.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/pf9_native_preview_suspension');
  final calls = <MethodCall>[];

  setUp(() async {
    calls.clear();
    await NativeGpuPreviewSuspension.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'createRenderer') {
            return <String, Object?>{'rendererId': 'renderer-1'};
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await NativeGpuPreviewSuspension.resetForTesting();
  });

  test('handoff suspension suppresses lifecycle resume until release', () async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final bridge = NativeGpuPreviewBridge(channel: channel);
    final rendererId = await bridge.createRenderer();

    calls.clear();
    await NativeGpuPreviewSuspension.acquire();
    expect(calls.map((call) => call.method), ['pause']);

    await bridge.resume(rendererId);
    expect(calls.map((call) => call.method), ['pause']);

    await NativeGpuPreviewSuspension.release();
    expect(calls.map((call) => call.method), ['pause', 'resume']);
  });

  test('release while app paused waits for normal lifecycle resume', () async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final bridge = NativeGpuPreviewBridge(channel: channel);
    final rendererId = await bridge.createRenderer();

    calls.clear();
    await NativeGpuPreviewSuspension.acquire();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await NativeGpuPreviewSuspension.release();

    expect(calls.map((call) => call.method), ['pause']);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await bridge.resume(rendererId);
    expect(calls.map((call) => call.method), ['pause', 'resume']);
  });

  test('destroyed renderer is never resumed after handoff release', () async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final bridge = NativeGpuPreviewBridge(channel: channel);
    final rendererId = await bridge.createRenderer();

    calls.clear();
    await NativeGpuPreviewSuspension.acquire();
    await bridge.destroyRenderer(rendererId);
    await NativeGpuPreviewSuspension.release();

    expect(calls.map((call) => call.method), ['pause', 'destroyRenderer']);
  });
}
