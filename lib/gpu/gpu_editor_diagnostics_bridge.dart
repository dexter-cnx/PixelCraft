import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const gpuEditorDiagnosticsChannelName =
    'dev.pixelcraft/gpu_editor_diagnostics_v1';
const _gpuPreviewDiagnosticsChannelName = 'dev.pixelcraft/gpu_preview_v1';

@immutable
class GpuEditorParityCaseResult {
  const GpuEditorParityCaseResult({
    required this.name,
    required this.samples,
    required this.maxChannelError,
    required this.passed,
  });

  final String name;
  final int samples;
  final double maxChannelError;
  final bool passed;

  factory GpuEditorParityCaseResult.fromMap(Map<Object?, Object?> map) =>
      GpuEditorParityCaseResult(
        name: map['name'] as String? ?? '',
        samples: map['samples'] as int? ?? 0,
        maxChannelError:
            (map['maxChannelError'] as num? ?? double.infinity).toDouble(),
        passed: map['passed'] as bool? ?? false,
      );
}

@immutable
class GpuEditorParityResult {
  const GpuEditorParityResult({
    required this.backend,
    required this.reference,
    required this.tolerance,
    required this.overallMaxChannelError,
    required this.passed,
    required this.cases,
    required this.filmParity,
  });

  final String backend;
  final String reference;
  final double tolerance;
  final double overallMaxChannelError;
  final bool passed;
  final List<GpuEditorParityCaseResult> cases;
  final String filmParity;

  factory GpuEditorParityResult.fromMap(Map<Object?, Object?> map) {
    final rawCases = map['cases'];
    final cases = rawCases is List
        ? rawCases
            .whereType<Map<Object?, Object?>>()
            .map(GpuEditorParityCaseResult.fromMap)
            .toList(growable: false)
        : const <GpuEditorParityCaseResult>[];
    return GpuEditorParityResult(
      backend: map['backend'] as String? ?? '',
      reference: map['reference'] as String? ?? '',
      tolerance: (map['tolerance'] as num? ?? 0).toDouble(),
      overallMaxChannelError:
          (map['overallMaxChannelError'] as num? ?? double.infinity).toDouble(),
      passed: map['passed'] as bool? ?? false,
      cases: cases,
      filmParity: map['filmParity'] as String? ?? '',
    );
  }
}

@immutable
class GpuEditorLatencyResult {
  const GpuEditorLatencyResult({
    required this.backend,
    required this.device,
    required this.width,
    required this.height,
    required this.iterations,
    required this.workload,
    required this.averageMs,
    required this.p50Ms,
    required this.p95Ms,
    required this.p99Ms,
    required this.maxMs,
    required this.targetMs,
    required this.passed,
  });

  final String backend;
  final String device;
  final int width;
  final int height;
  final int iterations;
  final String workload;
  final double averageMs;
  final double p50Ms;
  final double p95Ms;
  final double p99Ms;
  final double maxMs;
  final double targetMs;
  final bool passed;

  factory GpuEditorLatencyResult.fromMap(Map<Object?, Object?> map) =>
      GpuEditorLatencyResult(
        backend: map['backend'] as String? ?? '',
        device: map['device'] as String? ?? '',
        width: map['width'] as int? ?? 0,
        height: map['height'] as int? ?? 0,
        iterations: map['iterations'] as int? ?? 0,
        workload: map['workload'] as String? ?? '',
        averageMs: (map['averageMs'] as num? ?? 0).toDouble(),
        p50Ms: (map['p50Ms'] as num? ?? 0).toDouble(),
        p95Ms: (map['p95Ms'] as num? ?? 0).toDouble(),
        p99Ms: (map['p99Ms'] as num? ?? 0).toDouble(),
        maxMs: (map['maxMs'] as num? ?? 0).toDouble(),
        targetMs: (map['targetMs'] as num? ?? 0).toDouble(),
        passed: map['passed'] as bool? ?? false,
      );
}

class GpuEditorDiagnosticsBridge {
  const GpuEditorDiagnosticsBridge({
    MethodChannel? channel,
    MethodChannel? previewChannel,
  })  : _channel = channel ??
            const MethodChannel(gpuEditorDiagnosticsChannelName),
        _previewChannel = previewChannel ??
            const MethodChannel(_gpuPreviewDiagnosticsChannelName);

  final MethodChannel _channel;
  final MethodChannel _previewChannel;

  Future<GpuEditorParityResult> runAdjustmentParity() async {
    final map = await _channel.invokeMapMethod<Object?, Object?>(
      'runAdjustmentParity',
    );
    if (map == null) throw StateError('Editor GPU parity returned no data');
    return GpuEditorParityResult.fromMap(map);
  }

  Future<GpuEditorParityResult> runGaussianBlurParity() async {
    final map = await _previewChannel.invokeMapMethod<Object?, Object?>(
      'runGaussianBlurHarness',
      const <String, Object?>{'protocolVersion': 1},
    );
    if (map == null) {
      throw StateError('Gaussian blur GPU parity returned no data');
    }
    return GpuEditorParityResult.fromMap(map);
  }

  Future<GpuEditorLatencyResult> runLatencyBenchmark() async {
    final map = await _channel.invokeMapMethod<Object?, Object?>(
      'runLatencyBenchmark',
    );
    if (map == null) throw StateError('Editor GPU latency returned no data');
    return GpuEditorLatencyResult.fromMap(map);
  }
}
