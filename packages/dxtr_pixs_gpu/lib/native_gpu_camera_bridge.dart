import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'gpu_protocol.dart';

typedef NativeGpuRuntimeFailureHandler = Future<void> Function(
  String rendererId,
  String message,
);

void _traceNativeCamera(String message) {
  if (kDebugMode) {
    debugPrint('[PF2][NativeCamera] $message');
  }
}

/// Shared Camera controls for Android Camera2/OpenGL and iOS AVFoundation/Metal.
/// Live camera frames remain entirely native.
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
              _traceNativeCamera(
                'runtimeFailure rendererId=$rendererId message=$message',
              );
              await handler(rendererId, message);
            },
    );
  }

  Future<bool> requestCameraPermission() async {
    _traceNativeCamera('requestCameraPermission START');
    try {
      final granted = await _channel.invokeMethod<bool>(
            'requestCameraPermission',
            const <String, Object?>{
              'protocolVersion': gpuPreviewProtocolVersion,
            },
          ) ??
          false;
      _traceNativeCamera('requestCameraPermission OK granted=$granted');
      return granted;
    } catch (error, stackTrace) {
      _traceNativeCamera('requestCameraPermission FAILED error=$error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<List<String>> availableLenses() async {
    _traceNativeCamera('availableLenses START');
    try {
      final lenses = await _channel.invokeListMethod<String>(
            'availableCameraLenses',
            const <String, Object?>{
              'protocolVersion': gpuPreviewProtocolVersion,
            },
          ) ??
          const <String>[];
      _traceNativeCamera('availableLenses OK lenses=$lenses');
      return lenses;
    } catch (error, stackTrace) {
      _traceNativeCamera('availableLenses FAILED error=$error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<String> capturePhoto(String rendererId) async {
    _traceNativeCamera('capturePhoto START rendererId=$rendererId');
    try {
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
      _traceNativeCamera('capturePhoto OK rendererId=$rendererId path=$path');
      return path;
    } catch (error, stackTrace) {
      _traceNativeCamera(
        'capturePhoto FAILED rendererId=$rendererId error=$error',
      );
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<String> switchCamera(String rendererId) async {
    _traceNativeCamera('switchCamera START rendererId=$rendererId');
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'switchCamera',
        <String, Object?>{
          'protocolVersion': gpuPreviewProtocolVersion,
          'rendererId': rendererId,
        },
      );
      final lens = result?['lensDirection'] as String? ?? '';
      _traceNativeCamera(
        'switchCamera OK rendererId=$rendererId lensDirection=$lens',
      );
      return lens;
    } catch (error, stackTrace) {
      _traceNativeCamera(
        'switchCamera FAILED rendererId=$rendererId error=$error',
      );
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }
}
