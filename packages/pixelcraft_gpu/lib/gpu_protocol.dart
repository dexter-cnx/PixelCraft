/// Versioned control-plane protocol shared by Dart and native GPU backends.
///
/// Only small state/control messages cross this channel. Pixel/frame buffers
/// must remain native.
const gpuPreviewProtocolVersion = 1;
const gpuPreviewChannelName = 'dev.pixelcraft/gpu_preview_v1';
const gpuEditorPreviewChannelName = 'dev.pixelcraft/gpu_editor_preview_v1';
const gpuCameraPreviewViewType = 'dev.pixelcraft/gpu_camera_preview_v1';
const gpuEditorPreviewViewType = 'dev.pixelcraft/gpu_editor_preview_v1';
