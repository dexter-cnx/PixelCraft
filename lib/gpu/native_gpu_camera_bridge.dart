import 'package:flutter/services.dart';

import 'native_gpu_preview_bridge.dart';

typedef NativeGpuRuntimeFailureHandler = Future<void> Function(
  String rendererId,
  String message,
);

/// Camera controls shared by Android Camera2/OpenGL and iOS AVFoundation/Metal.
///
/// Only permission state, lens identifiers and clean capture file paths cross
/// this channel. Live camera frames always stay inside the native backend.
class NativeGpuCameraBridge {
  const NativeGpuCameraBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(gpuPreviewChannelName);

  final MethodChannel _channel;

  void setRuntimeFailureHandler(NativeGpuRuntimeFailureHandler? handler) {
    _channel.setMethodCallHandler(
      handler == null
          ? null
          : (call) async {
              if (call.method != 'runtimeFailure') return;
              final arguments = call.arguments;
              if (arguments is! Map) return;
              final rendererId = arguments['rendererId'] as String? ?? '';
              final message = arguments['message'] as String? ??
                  'Native GPU camera renderer failed';
              await handler(rendererId, message);
            },
    );
  }

  Future<bool> requestCameraPermission() async {
    return await _channel.invokeMethod<bool>(
          'requestCameraPermission',
          const <String, Object?>{
            'protocolVersion': gpuPreviewProtocolVersion,
          },
        ) ??
        false;
  }

  Future<List<String>> availableLenses() async {
    final result = await _channel.invokeListMethod<String>(
      'availableCameraLenses',
      const <String, Object?>{
        'protocolVersion': gpuPreviewProtocolVersion,
      },
    );
    return result ?? const <String>[];
  }

  Future<String> capturePhoto(String rendererId) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'capturePhoto',
      <String, Object?>{
        'protocolVersion': gpuPreviewProtocolVersion,
        'rendererId': rendererId,
      },
    );
    final path = result?['path'] as String?;
    if (path == null || path.isEmpty) {
      throw StateError('Native GPU camera capture returned no file path');
    }
    return path;
  }

  Future<String> switchCamera(String rendererId) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'switchCamera',
      <String, Object?>{
        'protocolVersion': gpuPreviewProtocolVersion,
        'rendererId': rendererId,
      },
    );
    return result?['lensDirection'] as String? ?? '';
  }
}
