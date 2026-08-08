import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pixelcraft/gpu/gpu_preview_renderer.dart';
import 'package:pixelcraft/gpu/native_gpu_preview_bridge.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android GPU LUT reference harness passes', (tester) async {
    if (!Platform.isAndroid) return;

    const bridge = NativeGpuPreviewBridge();
    final probe = await bridge.probe();

    expect(probe.protocolVersion, gpuPreviewProtocolVersion);
    expect(probe.backend, GpuPreviewBackendKind.androidOpenGl);
    expect(probe.available, isTrue);
    expect(probe.supportsLut33, isTrue);
    expect(probe.maxLutSize, 33);

    final harness = await bridge.runReferenceHarness();
    expect(harness.passed, isTrue);
    expect(harness.profileId, 'identity');
    expect(harness.samples, greaterThanOrEqualTo(8));
    expect(harness.maxChannelError, lessThanOrEqualTo(2 / 255));
  });

  testWidgets('Android GPU samples all Film Profile Pack v2 atlases',
      (tester) async {
    if (!Platform.isAndroid) return;

    const bridge = NativeGpuPreviewBridge();
    const profiles = <String>[
      'provia_inspired',
      'velvia_inspired',
      'astia_inspired',
      'e100_inspired',
      'ektar_inspired',
      'chrome64_inspired',
    ];

    for (final profileId in profiles) {
      final harness = await bridge.runFilmProfileHarness(profileId);
      expect(harness.profileId, profileId);
      expect(harness.passed, isTrue, reason: '$profileId GPU parity failed');
      expect(harness.samples, 24);
      expect(
        harness.maxChannelError,
        lessThanOrEqualTo(2 / 255),
        reason: '$profileId exceeded native GPU parity tolerance',
      );
    }
  });
}
