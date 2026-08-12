import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const iosGpuEditorPreviewViewType = 'dev.pixelcraft/gpu_editor_preview_v1';

class IosGpuEditorPreview extends StatelessWidget {
  const IosGpuEditorPreview({
    super.key,
    required this.rendererId,
  });

  final String rendererId;

  @override
  Widget build(BuildContext context) {
    return UiKitView(
      viewType: iosGpuEditorPreviewViewType,
      creationParams: <String, Object?>{'rendererId': rendererId},
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
