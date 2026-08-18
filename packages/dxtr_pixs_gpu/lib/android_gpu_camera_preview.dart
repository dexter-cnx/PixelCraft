import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

const androidGpuCameraPreviewViewType =
    'dev.pixelcraft/gpu_camera_preview_v1';

/// Android native Camera2 -> external OES -> Film LUT preview surface.
///
/// The platform view receives only the renderer/session id. Camera frame pixels
/// remain entirely native and never cross Dart or Flutter Rust Bridge.
class AndroidGpuCameraPreview extends StatelessWidget {
  const AndroidGpuCameraPreview({
    super.key,
    required this.rendererId,
  });

  final String rendererId;

  @override
  Widget build(BuildContext context) {
    return AndroidView(
      viewType: androidGpuCameraPreviewViewType,
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      creationParams: <String, Object?>{'rendererId': rendererId},
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
