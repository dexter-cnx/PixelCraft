import Flutter
import UIKit

/// Lightweight physical-orientation query for portrait-locked Camera UI.
/// No frame payload crosses this channel.
final class CameraDeviceOrientationChannel {
  static let shared = CameraDeviceOrientationChannel()
  static let channelName = "dev.pixelcraft/camera_orientation_v1"

  private var channel: FlutterMethodChannel?

  func register(messenger: FlutterBinaryMessenger) {
    guard channel == nil else { return }
    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "orientation" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self.orientationName())
    }
    self.channel = channel
  }

  private func orientationName() -> String {
    switch UIDevice.current.orientation {
    case .portrait:
      return "portrait"
    case .portraitUpsideDown:
      return "portraitUpsideDown"
    case .landscapeLeft:
      return "landscapeLeft"
    case .landscapeRight:
      return "landscapeRight"
    default:
      return "unknown"
    }
  }
}
