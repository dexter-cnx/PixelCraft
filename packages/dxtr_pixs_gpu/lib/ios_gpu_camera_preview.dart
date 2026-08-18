import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

const iosGpuCameraPreviewViewType = 'dev.pixelcraft/gpu_camera_preview_v1';

/// iOS AVFoundation -> CVPixelBuffer -> Metal Film LUT preview surface.
///
/// The platform view receives only the renderer/session id. Camera frame pixels
/// remain entirely native and never cross Dart or Flutter Rust Bridge.
class IosGpuCameraPreview extends StatelessWidget {
  const IosGpuCameraPreview({
    super.key,
    required this.rendererId,
  });

  final String rendererId;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: UiKitView(
        viewType: iosGpuCameraPreviewViewType,
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        creationParams: <String, Object?>{'rendererId': rendererId},
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }
}
