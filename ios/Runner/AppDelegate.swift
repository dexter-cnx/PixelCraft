import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var gpuPreviewPlugin: GpuPreviewPlugin?
  private var gpuEditorPreviewPlugin: GpuEditorPreviewPlugin?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "PixelCraftGpuPreview"
    ) else {
      assertionFailure("Unable to create Flutter registrar for PixelCraftGpuPreview")
      return
    }
    gpuPreviewPlugin = GpuPreviewPlugin(registrar: registrar)
    gpuEditorPreviewPlugin = GpuEditorPreviewPlugin(registrar: registrar)
    GpuFramePacingDiagnostics.shared.register(messenger: registrar.messenger())
  }
}
