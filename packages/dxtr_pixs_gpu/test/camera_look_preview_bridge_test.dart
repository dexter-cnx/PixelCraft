import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dxtr_pixs_gpu/camera_look_preview_bridge.dart';
import 'package:dxtr_pixs_gpu/gpu_editor_preview_bridge.dart';
import 'package:dxtr_pixs_gpu/gpu_protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('setCameraLook sends versioned composed control payload', () async {
    const channel = MethodChannel('pf2.camera.look.test');
    MethodCall? recorded;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          recorded = call;
          return null;
        });

    const bridge = CameraLookPreviewBridge(channel: channel);
    await bridge.setCameraLook(
      'renderer-1',
      const GpuCameraLookState(
        filmProfileId: 'astia_inspired',
        filmStrength: 0.75,
        creativeFilterId: 'golden',
        creativeFilterStrength: 0.5,
        adjustments: GpuEditorAdjustmentState(
          brightness: 1.1,
          contrast: 0.9,
          saturation: 1.2,
        ),
      ),
    );

    expect(recorded?.method, 'setCameraLook');
    final arguments = recorded?.arguments as Map<Object?, Object?>;
    expect(arguments['protocolVersion'], gpuPreviewProtocolVersion);
    expect(arguments['rendererId'], 'renderer-1');
    expect(arguments['filmProfileId'], 'astia_inspired');
    expect(arguments['filmStrength'], 0.75);
    expect(arguments['creativeFilterId'], 'golden');
    expect(arguments['creativeFilterStrength'], 0.5);
    expect(arguments['brightness'], 1.1);
    expect(arguments['contrast'], 0.9);
    expect(arguments['saturation'], 1.2);
  });
}
