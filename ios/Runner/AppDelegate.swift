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
      case "requestGalleryWrite":
        if #available(iOS 14, *) {
          PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
              result(Self.permissionDecision(for: status))
            }
          }
        } else {
          PHPhotoLibrary.requestAuthorization { status in
            DispatchQueue.main.async {
              result(Self.permissionDecision(for: status))
            }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func permissionDecision(for status: PHAuthorizationStatus) -> String {
    switch status {
    case .authorized, .limited:
      return "granted"
    case .restricted:
      return "restricted"
    case .denied:
      return "restricted"
    case .notDetermined:
      return "denied"
    @unknown default:
      return "denied"
    }
  }
}
