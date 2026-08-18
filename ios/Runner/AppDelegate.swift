import AVFoundation
import Flutter
import Photos
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let permissionChannel = "dev.cnxdev.pixelcraft/permissions"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: Self.permissionChannel,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "requestCamera":
        Self.requestCamera(result)
      case "requestGalleryWrite":
        Self.requestGalleryWrite(result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func requestCamera(_ result: @escaping FlutterResult) {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      result("granted")
    case .restricted, .denied:
      result("restricted")
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async {
          result(granted ? "granted" : "restricted")
        }
      }
    @unknown default:
      result("denied")
    }
  }

  private static func requestGalleryWrite(_ result: @escaping FlutterResult) {
    if #available(iOS 14, *) {
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        DispatchQueue.main.async {
          result(permissionDecision(for: status))
        }
      }
    } else {
      PHPhotoLibrary.requestAuthorization { status in
        DispatchQueue.main.async {
          result(permissionDecision(for: status))
        }
      }
    }
  }

  private static func permissionDecision(for status: PHAuthorizationStatus) -> String {
    switch status {
    case .authorized, .limited:
      return "granted"
    case .restricted, .denied:
      return "restricted"
    case .notDetermined:
      return "denied"
    @unknown default:
      return "denied"
    }
  }
}
