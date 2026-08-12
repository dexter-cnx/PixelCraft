import Flutter
import Foundation

/// iOS registration boundary for PixelCraft's preview-only Metal runtime.
public final class PixelcraftGpuPlugin: NSObject, FlutterPlugin {
  private static var previewPlugin: GpuPreviewPlugin?
  private static var editorPreviewPlugin: GpuEditorPreviewPlugin?

  public static func register(with registrar: FlutterPluginRegistrar) {
    previewPlugin = GpuPreviewPlugin(registrar: registrar)
    editorPreviewPlugin = GpuEditorPreviewPlugin(registrar: registrar)
    GpuFramePacingDiagnostics.shared.register(messenger: registrar.messenger())
    GpuEditorVerificationDiagnostics.shared.register(messenger: registrar.messenger())
  }
}
