import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'gpu_editor_preview_bridge.dart';
import 'gpu_protocol.dart';

@immutable
class GpuCameraLookState {
  const GpuCameraLookState({
    this.filmProfileId = '',
    this.filmStrength = 0,
    this.creativeFilterId = '',
    this.creativeFilterStrength = 0,
    this.adjustments = const GpuEditorAdjustmentState(),
  });

  final String filmProfileId;
  final double filmStrength;
  final String creativeFilterId;
  final double creativeFilterStrength;
  final GpuEditorAdjustmentState adjustments;

  Map<String, Object?> toMap() => <String, Object?>{
    'filmProfileId': filmProfileId,
    'filmStrength': filmStrength.clamp(0.0, 1.0).toDouble(),
    'creativeFilterId': creativeFilterId,
    'creativeFilterStrength': creativeFilterStrength.clamp(0.0, 1.0).toDouble(),
    'exposure': adjustments.exposure,
    'temperature': adjustments.temperature,
    'tint': adjustments.tint,
    'brightness': adjustments.brightness,
    'contrast': adjustments.contrast,
    'saturation': adjustments.saturation,
    'vignette': adjustments.vignette,
  };
}

/// PF2 composed live-camera preview control.
///
/// The MethodChannel transports configuration only. Camera frames stay native,
/// and the state sent here never becomes final-render authority.
class CameraLookPreviewBridge {
  const CameraLookPreviewBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(gpuPreviewChannelName);

  final MethodChannel _channel;

  Future<void> setCameraLook(String rendererId, GpuCameraLookState state) =>
      _channel.invokeMethod<void>('setCameraLook', <String, Object?>{
        'protocolVersion': gpuPreviewProtocolVersion,
        'rendererId': rendererId,
        ...state.toMap(),
      });
}
