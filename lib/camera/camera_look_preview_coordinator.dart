import 'dart:async';

import 'package:dxtr_pixs_gpu/pixelcraft_gpu.dart';

import 'camera_look_state.dart';

abstract interface class CameraLookPreviewSink {
  Future<void> setCameraLook(String rendererId, GpuCameraLookState state);
}

class NativeCameraLookPreviewSink implements CameraLookPreviewSink {
  const NativeCameraLookPreviewSink({CameraLookPreviewBridge? bridge})
    : _bridge = bridge ?? const CameraLookPreviewBridge();

  final CameraLookPreviewBridge _bridge;

  @override
  Future<void> setCameraLook(String rendererId, GpuCameraLookState state) =>
      _bridge.setCameraLook(rendererId, state);
}

/// Serializes PF2 live-camera look updates and collapses rapid slider events.
///
/// Only the newest pending state is sent after an in-flight native update.
/// Failures are reported to the caller but never mutate the canonical camera
/// look state. Native camera frames remain outside Dart.
class CameraLookPreviewCoordinator {
  CameraLookPreviewCoordinator({CameraLookPreviewSink? sink})
    : _sink = sink ?? const NativeCameraLookPreviewSink();

  final CameraLookPreviewSink _sink;

  String? _rendererId;
  CameraLookState? _pending;
  bool _draining = false;
  int _generation = 0;
  void Function(Object error)? onFailure;

  bool get isAttached => _rendererId != null;

  void attach(String rendererId) {
    _rendererId = rendererId;
    _generation++;
  }

  void detach() {
    _rendererId = null;
    _pending = null;
    _generation++;
  }

  void submit(CameraLookState state) {
    if (_rendererId == null) return;
    _pending = state;
    if (!_draining) {
      unawaited(_drain());
    }
  }

  Future<void> flush() async {
    while (_draining || _pending != null) {
      if (!_draining && _pending != null) {
        await _drain();
      } else {
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    final generation = _generation;
    try {
      while (_pending != null && generation == _generation) {
        final state = _pending!;
        _pending = null;
        final rendererId = _rendererId;
        if (rendererId == null) break;
        try {
          await _sink.setCameraLook(rendererId, _toGpuState(state));
        } catch (error) {
          if (generation == _generation) {
            _pending = null;
            onFailure?.call(error);
          }
          break;
        }
      }
    } finally {
      _draining = false;
      if (_pending != null && _rendererId != null) {
        unawaited(_drain());
      }
    }
  }

  GpuCameraLookState _toGpuState(CameraLookState state) => GpuCameraLookState(
    filmProfileId: state.filmProfileId,
    filmStrength: state.filmStrength,
    creativeFilterId: state.creativeFilterId,
    creativeFilterStrength: state.creativeFilterStrength,
    adjustments: GpuEditorAdjustmentState(
      exposure: state.adjustmentValue('exposure'),
      temperature: state.adjustmentValue('temperature'),
      tint: state.adjustmentValue('tint'),
      brightness: state.adjustmentValue('brightness'),
      contrast: state.adjustmentValue('contrast'),
      saturation: state.adjustmentValue('saturation'),
      vignette: state.adjustmentValue('vignette'),
    ),
  );
}
