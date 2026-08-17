import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/camera/camera_look_preview_coordinator.dart';
import 'package:pixelcraft/camera/camera_look_state.dart';
import 'package:dxtr_pixs_gpu/pixelcraft_gpu.dart';

class _RecordingSink implements CameraLookPreviewSink {
  final calls = <GpuCameraLookState>[];
  Completer<void>? gate;
  Object? error;

  @override
  Future<void> setCameraLook(
    String rendererId,
    GpuCameraLookState state,
  ) async {
    calls.add(state);
    final currentGate = gate;
    if (currentGate != null) await currentGate.future;
    final currentError = error;
    if (currentError != null) throw currentError;
  }
}

void main() {
  test('maps composed camera state to GPU state', () async {
    final sink = _RecordingSink();
    final coordinator = CameraLookPreviewCoordinator(sink: sink)
      ..attach('renderer');

    coordinator.submit(
      CameraLookState()
          .withFilm('velvia_inspired', 0.8)
          .withCreative('golden', 0.6)
          .withAdjustment('brightness', 1.2)
          .withAdjustment('contrast', 0.9)
          .withAdjustment('saturation', 1.3),
    );
    await coordinator.flush();

    expect(sink.calls, hasLength(1));
    final state = sink.calls.single;
    expect(state.filmProfileId, 'velvia_inspired');
    expect(state.filmStrength, 0.8);
    expect(state.creativeFilterId, 'golden');
    expect(state.creativeFilterStrength, 0.6);
    expect(state.adjustments.brightness, 1.2);
    expect(state.adjustments.contrast, 0.9);
    expect(state.adjustments.saturation, 1.3);
  });

  test('collapses pending slider updates to latest state', () async {
    final sink = _RecordingSink();
    final gate = Completer<void>();
    sink.gate = gate;
    final coordinator = CameraLookPreviewCoordinator(sink: sink)
      ..attach('renderer');

    coordinator.submit(CameraLookState().withAdjustment('brightness', 1.1));
    await Future<void>.delayed(Duration.zero);
    coordinator.submit(CameraLookState().withAdjustment('brightness', 1.2));
    coordinator.submit(CameraLookState().withAdjustment('brightness', 1.4));

    gate.complete();
    sink.gate = null;
    await coordinator.flush();

    expect(sink.calls.length, 2);
    expect(sink.calls.first.adjustments.brightness, 1.1);
    expect(sink.calls.last.adjustments.brightness, 1.4);
  });

  test('detach invalidates pending work', () async {
    final sink = _RecordingSink();
    final gate = Completer<void>();
    sink.gate = gate;
    final coordinator = CameraLookPreviewCoordinator(sink: sink)
      ..attach('renderer');

    coordinator.submit(CameraLookState().withAdjustment('contrast', 1.2));
    await Future<void>.delayed(Duration.zero);
    coordinator.submit(CameraLookState().withAdjustment('contrast', 1.6));
    coordinator.detach();
    gate.complete();
    sink.gate = null;
    await coordinator.flush();

    expect(sink.calls, hasLength(1));
  });

  test('native failure is fail-closed and reported once', () async {
    final sink = _RecordingSink()..error = StateError('native failed');
    final failures = <Object>[];
    final coordinator = CameraLookPreviewCoordinator(sink: sink)
      ..attach('renderer')
      ..onFailure = failures.add;

    coordinator.submit(CameraLookState().withCreative('vintage', 1));
    coordinator.submit(CameraLookState().withCreative('golden', 1));
    await coordinator.flush();

    expect(failures, hasLength(1));
    expect(sink.calls, hasLength(1));
  });
}
