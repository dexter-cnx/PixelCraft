import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'gpu_protocol.dart';

typedef NativeGpuRuntimeFailureHandler =
    Future<void> Function(String rendererId, String message);

enum NativeCameraFlashMode { off, auto, on }

enum NativeCameraDeviceOrientation {
  unknown,
  portrait,
  portraitUpsideDown,
  landscapeLeft,
  landscapeRight,
}

extension NativeCameraDeviceOrientationWire on NativeCameraDeviceOrientation {
  static NativeCameraDeviceOrientation parse(Object? value) => switch (value) {
    'portrait' => NativeCameraDeviceOrientation.portrait,
    'portraitUpsideDown' => NativeCameraDeviceOrientation.portraitUpsideDown,
    'landscapeLeft' => NativeCameraDeviceOrientation.landscapeLeft,
    'landscapeRight' => NativeCameraDeviceOrientation.landscapeRight,
    _ => NativeCameraDeviceOrientation.unknown,
  };
}

extension NativeCameraFlashModeWire on NativeCameraFlashMode {
  String get wireName => name;

  static NativeCameraFlashMode parse(Object? value) => switch (value) {
    'on' => NativeCameraFlashMode.on,
    'off' => NativeCameraFlashMode.off,
    _ => NativeCameraFlashMode.auto,
  };
}

@immutable
class NativeCameraControlState {
  const NativeCameraControlState({
    required this.lensDirection,
    required this.hasFlash,
    required this.hasTorch,
    required this.flashMode,
    required this.torchEnabled,
    required this.mirrorEnabled,
    this.deviceOrientation = NativeCameraDeviceOrientation.unknown,
  });

  factory NativeCameraControlState.fromMap(Map<Object?, Object?>? map) {
    final value = map ?? const <Object?, Object?>{};
    return NativeCameraControlState(
      lensDirection: value['lensDirection'] as String? ?? 'back',
      hasFlash: value['hasFlash'] as bool? ?? false,
      hasTorch: value['hasTorch'] as bool? ?? false,
      flashMode: NativeCameraFlashModeWire.parse(value['flashMode']),
      torchEnabled: value['torchEnabled'] as bool? ?? false,
      mirrorEnabled: value['mirrorEnabled'] as bool? ?? false,
      deviceOrientation: NativeCameraDeviceOrientationWire.parse(
        value['deviceOrientation'],
      ),
    );
  }

  final String lensDirection;
  final bool hasFlash;
  final bool hasTorch;
  final NativeCameraFlashMode flashMode;
  final bool torchEnabled;
  final bool mirrorEnabled;
  final NativeCameraDeviceOrientation deviceOrientation;

  bool get isFront => lensDirection == 'front';

  NativeCameraControlState withOrientation(
    NativeCameraDeviceOrientation orientation,
  ) => NativeCameraControlState(
    lensDirection: lensDirection,
    hasFlash: hasFlash,
    hasTorch: hasTorch,
    flashMode: flashMode,
    torchEnabled: torchEnabled,
    mirrorEnabled: mirrorEnabled,
    deviceOrientation: orientation,
  );
}

@immutable
class NativeCameraCaptureResult {
  const NativeCameraCaptureResult({
    required this.path,
    required this.deviceOrientation,
  });

  final String path;
  final NativeCameraDeviceOrientation deviceOrientation;
}

void _traceNativeCamera(String message) {
  if (kDebugMode) {
    debugPrint('[PF2][NativeCamera] $message');
  }
}

/// Shared Camera controls for Android Camera2/OpenGL and iOS AVFoundation/Metal.
/// Live camera frames remain entirely native.
class NativeGpuCameraBridge {
  const NativeGpuCameraBridge({
    MethodChannel? channel,
    MethodChannel? orientationChannel,
  }) : _channel = channel ?? const MethodChannel(gpuPreviewChannelName),
       _orientationChannel = orientationChannel ??
           const MethodChannel('dev.pixelcraft/camera_orientation_v1');

  final MethodChannel _channel;
  final MethodChannel _orientationChannel;

  void setRuntimeFailureHandler(NativeGpuRuntimeFailureHandler? handler) {
    _channel.setMethodCallHandler(
      handler == null
          ? null
          : (call) async {
              if (call.method != 'runtimeFailure') return;
              final arguments = call.arguments;
              if (arguments is! Map) return;
              final rendererId = arguments['rendererId'] as String? ?? '';
              final message =
                  arguments['message'] as String? ??
                  'Native GPU camera renderer failed';
              _traceNativeCamera(
                'runtimeFailure rendererId=$rendererId message=$message',
              );
              await handler(rendererId, message);
            },
    );
  }

  Future<bool> requestCameraPermission() async =>
      await _channel.invokeMethod<bool>(
        'requestCameraPermission',
        const <String, Object?>{'protocolVersion': gpuPreviewProtocolVersion},
      ) ??
      false;

  Future<List<String>> availableLenses() async =>
      await _channel.invokeListMethod<String>(
        'availableCameraLenses',
        const <String, Object?>{'protocolVersion': gpuPreviewProtocolVersion},
      ) ??
      const <String>[];

  Future<NativeCameraControlState> controlState(String rendererId) async {
    var state = await _control('cameraControlState', rendererId);
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final orientation = NativeCameraDeviceOrientationWire.parse(
          await _orientationChannel.invokeMethod<String>('orientation'),
        );
        if (orientation != NativeCameraDeviceOrientation.unknown) {
          state = state.withOrientation(orientation);
        }
      } catch (_) {}
    }
    return state;
  }

  Future<NativeCameraControlState> setFlashMode(
    String rendererId,
    NativeCameraFlashMode mode,
  ) => _control('setFlashMode', rendererId, <String, Object?>{
    'flashMode': mode.wireName,
  });

  Future<NativeCameraControlState> setTorchEnabled(
    String rendererId,
    bool enabled,
  ) => _control('setTorchEnabled', rendererId, <String, Object?>{
    'enabled': enabled,
  });

  Future<NativeCameraControlState> setMirrorEnabled(
    String rendererId,
    bool enabled,
  ) => _control('setMirrorEnabled', rendererId, <String, Object?>{
    'enabled': enabled,
  });

  Future<NativeCameraCaptureResult> capturePhoto(String rendererId) async {
    // Snapshot physical orientation immediately before shutter. Preview remains
    // portrait-locked; this metadata is used only if the resulting JPEG/EXIF
    // shape disagrees with the physical device orientation.
    final state = await controlState(rendererId);
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

    final carriesPhysicalOrientation =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return NativeCameraCaptureResult(
      path: path,
      deviceOrientation: carriesPhysicalOrientation
          ? state.deviceOrientation
          : NativeCameraDeviceOrientation.unknown,
    );
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

  Future<NativeCameraControlState> _control(
    String method,
    String rendererId, [
    Map<String, Object?> extra = const <String, Object?>{},
  ]) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      method,
      <String, Object?>{
        'protocolVersion': gpuPreviewProtocolVersion,
        'rendererId': rendererId,
        ...extra,
      },
    );
    return NativeCameraControlState.fromMap(result);
  }
}
