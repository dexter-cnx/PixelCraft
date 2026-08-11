import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pixelcraft/gpu/gpu_preview_renderer.dart';
import 'package:pixelcraft/gpu/native_gpu_preview_bridge.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native GPU identity LUT reference harness passes', (tester) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    const bridge = NativeGpuPreviewBridge();
    final probe = await bridge.probe();
    final expectedBackend = Platform.isAndroid
        ? GpuPreviewBackendKind.androidOpenGl
        : GpuPreviewBackendKind.iosMetal;

    expect(probe.protocolVersion, gpuPreviewProtocolVersion);
    expect(probe.backend, expectedBackend);
    expect(probe.available, isTrue);
    expect(probe.supportsLut33, isTrue);
    expect(probe.maxLutSize, 33);

    final harness = await bridge.runReferenceHarness();
    debugPrint(
      '[GPU parity] ${expectedBackend.name} identity '
      'samples=${harness.samples} maxError=${harness.maxChannelError}',
    );
    expect(harness.passed, isTrue);
    expect(harness.profileId, 'identity');
    expect(harness.samples, greaterThanOrEqualTo(8));
    expect(harness.maxChannelError, lessThanOrEqualTo(2 / 255));
  });

  testWidgets('native GPU samples all Film Profile Pack v2 LUTs',
      (tester) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

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
      debugPrint(
        '[GPU parity] $profileId samples=${harness.samples} '
        'maxError=${harness.maxChannelError}',
      );
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
