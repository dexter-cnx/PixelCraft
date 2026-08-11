import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pixelcraft/gpu/gpu_editor_diagnostics_bridge.dart';
import 'package:pixelcraft/gpu/gpu_editor_preview_bridge.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const diagnostics = GpuEditorDiagnosticsBridge();
  const editorBridge = GpuEditorPreviewBridge();

  testWidgets('G3.1 adjustment parity remains within Rust tolerance',
      (tester) async {
    if (!Platform.isIOS) return;

    final result = await diagnostics.runAdjustmentParity();
    debugPrint(
      '[G3.1 parity] backend=${result.backend} '
      'maxError=${result.overallMaxChannelError} '
      'tolerance=${result.tolerance} cases=${result.cases.length}',
    );
    for (final testCase in result.cases) {
      debugPrint(
        '  ${testCase.name}: samples=${testCase.samples} '
        'maxError=${testCase.maxChannelError} passed=${testCase.passed}',
      );
    }

    expect(result.passed, isTrue);
    expect(result.cases, isNotEmpty);
    expect(
      result.overallMaxChannelError,
      lessThanOrEqualTo(result.tolerance),
    );
  });

  testWidgets('G3.1 gaussian blur parity remains deterministic',
      (tester) async {
    if (!Platform.isIOS) return;

    final result = await diagnostics.runGaussianBlurParity();
    debugPrint(
      '[G3.1 blur parity] backend=${result.backend} '
      'maxError=${result.overallMaxChannelError} '
      'tolerance=${result.tolerance} cases=${result.cases.length}',
    );

    expect(result.passed, isTrue);
    expect(result.cases, isNotEmpty);
    expect(
      result.overallMaxChannelError,
      lessThanOrEqualTo(result.tolerance),
    );
  });

  testWidgets('G3.2 creative compute parity remains within tolerance',
      (tester) async {
    if (!Platform.isIOS) return;

    final result = await diagnostics.runCreativeParity();
    debugPrint(
      '[G3.2 creative parity] backend=${result.backend} '
      'maxError=${result.overallMaxChannelError} '
      'tolerance=${result.tolerance} cases=${result.cases.length}',
    );

    expect(result.passed, isTrue);
    expect(result.cases, isNotEmpty);
    expect(
      result.overallMaxChannelError,
      lessThanOrEqualTo(result.tolerance),
    );
  });

  testWidgets('G3 realtime adjustment plus Film latency stays under budget',
      (tester) async {
    if (!Platform.isIOS) return;

    final result = await diagnostics.runLatencyBenchmark();
    debugPrint(
      '[G3 latency] device=${result.device} workload=${result.workload} '
      '${result.width}x${result.height} iterations=${result.iterations} '
      'avg=${result.averageMs.toStringAsFixed(3)}ms '
      'p50=${result.p50Ms.toStringAsFixed(3)}ms '
      'p95=${result.p95Ms.toStringAsFixed(3)}ms '
      'p99=${result.p99Ms.toStringAsFixed(3)}ms '
      'max=${result.maxMs.toStringAsFixed(3)}ms '
      'target=${result.targetMs.toStringAsFixed(2)}ms',
    );

    expect(result.passed, isTrue);
    expect(result.p95Ms, lessThanOrEqualTo(result.targetMs));
  });

  testWidgets('G3 Sharpen plus Blur representative latency stays under budget',
      (tester) async {
    if (!Platform.isIOS) return;

    final result = await diagnostics.runGaussianBlurLatencyBenchmark();
    debugPrint(
      '[G3 blur latency] device=${result.device} workload=${result.workload} '
      '${result.width}x${result.height} iterations=${result.iterations} '
      'avg=${result.averageMs.toStringAsFixed(3)}ms '
      'p95=${result.p95Ms.toStringAsFixed(3)}ms '
      'p99=${result.p99Ms.toStringAsFixed(3)}ms '
      'max=${result.maxMs.toStringAsFixed(3)}ms '
      'target=${result.targetMs.toStringAsFixed(2)}ms',
    );

    expect(result.passed, isTrue);
    expect(result.p95Ms, lessThanOrEqualTo(result.targetMs));
  });

  testWidgets('G3.3 renderer can be destroyed and recreated repeatedly',
      (tester) async {
    if (!Platform.isIOS) return;

    final created = <String>[];
    for (var cycle = 0; cycle < 12; cycle++) {
      final rendererId = await editorBridge.createRenderer();
      expect(rendererId, isNotEmpty);
      expect(created, isNot(contains(rendererId)));
      created.add(rendererId);
      await editorBridge.destroyRenderer(rendererId);
      debugPrint('[G3.3 lifecycle] recreate cycle ${cycle + 1}/12 passed');
    }

    expect(created.length, 12);
  });
}