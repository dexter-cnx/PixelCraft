import Flutter
import Foundation
import UIKit

/// iOS registration boundary for PixelCraft's preview-only Metal runtime.
public final class PixelcraftGpuPlugin: NSObject, FlutterPlugin {
  private static var previewPlugin: GpuPreviewPlugin?
  private static var editorPreviewPlugin: GpuEditorPreviewPlugin?
  private static var livePreviewSnapshotChannel: LivePreviewSnapshotChannel?
  private static var orientationChannel: FlutterMethodChannel?

  public static func register(with registrar: FlutterPluginRegistrar) {
    previewPlugin = GpuPreviewPlugin(registrar: registrar)
    editorPreviewPlugin = GpuEditorPreviewPlugin(registrar: registrar)
    livePreviewSnapshotChannel = LivePreviewSnapshotChannel(registrar: registrar)
    registerOrientationChannel(messenger: registrar.messenger())
    GpuFramePacingDiagnostics.shared.register(messenger: registrar.messenger())
    GpuEditorVerificationDiagnostics.shared.register(messenger: registrar.messenger())
  }

  private static func registerOrientationChannel(messenger: FlutterBinaryMessenger) {
    guard orientationChannel == nil else { return }
    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    let channel = FlutterMethodChannel(
      name: "dev.pixelcraft/camera_orientation_v1",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "orientation" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(orientationName())
    }
    orientationChannel = channel
  }

  private static func orientationName() -> String {
    switch UIDevice.current.orientation {
    case .portrait:
      return "portrait"
    case .portraitUpsideDown:
      return "portraitUpsideDown"
    case .landscapeLeft:
      // UIDevice and capture/image orientation use opposite landscape naming.
      // Keep the preview portrait-locked; this value is only capture metadata.
      return "landscapeRight"
    case .landscapeRight:
      return "landscapeLeft"
    default:
      return "unknown"
    }
  }
}
