import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const gpuEditorPreviewChannelName = 'dev.pixelcraft/gpu_editor_preview_v1';

@immutable
class GpuEditorAdjustmentState {
  const GpuEditorAdjustmentState({
    this.brightness = 1,
    this.contrast = 1,
    this.saturation = 1,
    this.sharpen = 0,
  });

  final double brightness;
  final double contrast;
  final double saturation;
  final double sharpen;

  GpuEditorAdjustmentState copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? sharpen,
  }) =>
      GpuEditorAdjustmentState(
        brightness: brightness ?? this.brightness,
        contrast: contrast ?? this.contrast,
        saturation: saturation ?? this.saturation,
        sharpen: sharpen ?? this.sharpen,
      );
}

class GpuEditorPreviewBridge {
  const GpuEditorPreviewBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(gpuEditorPreviewChannelName);

  final MethodChannel _channel;

  Future<String> createRenderer() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'createRenderer',
    );
    final id = result?['rendererId'] as String?;
    if (id == null || id.isEmpty) {
      throw StateError('Editor GPU renderer returned no rendererId');
    }
    return id;
  }

  Future<void> setSourcePath(String rendererId, String path) =>
      _channel.invokeMethod<void>(
        'setSourcePath',
        <String, Object?>{'rendererId': rendererId, 'path': path},
      );

  Future<void> setAdjustments(
    String rendererId,
    GpuEditorAdjustmentState state,
  ) =>
      _channel.invokeMethod<void>(
        'setAdjustments',
        <String, Object?>{
          'rendererId': rendererId,
          'brightness': state.brightness,
          'contrast': state.contrast,
          'saturation': state.saturation,
          'sharpen': state.sharpen,
        },
      );

  Future<void> setFilm(
    String rendererId, {
    required String profileId,
    required double strength,
  }) =>
      _channel.invokeMethod<void>(
        'setFilm',
        <String, Object?>{
          'rendererId': rendererId,
          'profileId': profileId,
          'strength': strength.clamp(0.0, 1.0).toDouble(),
        },
      );

  Future<void> destroyRenderer(String rendererId) =>
      _channel.invokeMethod<void>(
        'destroyRenderer',
        <String, Object?>{'rendererId': rendererId},
      );
}
