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
      case "requestGalleryRead":
        Self.requestGalleryRead(result)
      case "requestGalleryWrite":
        Self.requestGalleryWrite(result)
      case "loadLatestGalleryThumbnail":
        Self.loadLatestGalleryThumbnail(result)
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

  private static func requestGalleryRead(_ result: @escaping FlutterResult) {
    if #available(iOS 14, *) {
      PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
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

  private static func loadLatestGalleryThumbnail(_ result: @escaping FlutterResult) {
    let status: PHAuthorizationStatus
    if #available(iOS 14, *) {
      status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    } else {
      status = PHPhotoLibrary.authorizationStatus()
    }
    guard canReadPhotos(status) else {
      result(nil)
      return
    }

    let options = PHFetchOptions()
    options.fetchLimit = 1
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    let assets = PHAsset.fetchAssets(with: .image, options: options)
    guard let asset = assets.firstObject else {
      result(nil)
      return
    }

    let requestOptions = PHImageRequestOptions()
    requestOptions.deliveryMode = .highQualityFormat
    requestOptions.resizeMode = .fast
    requestOptions.isNetworkAccessAllowed = true
    PHImageManager.default().requestImage(
      for: asset,
      targetSize: CGSize(width: 160, height: 160),
      contentMode: .aspectFill,
      options: requestOptions
    ) { image, _ in
      DispatchQueue.main.async {
        guard let data = image?.jpegData(compressionQuality: 0.82) else {
          result(nil)
          return
        }
        result(FlutterStandardTypedData(bytes: data))
      }
    }
  }

  private static func canReadPhotos(_ status: PHAuthorizationStatus) -> Bool {
    if status == .authorized {
      return true
    }
    if #available(iOS 14, *), status == .limited {
      return true
    }
    return false
  }

  private static func permissionDecision(for status: PHAuthorizationStatus) -> String {
    if status == .authorized {
      return "granted"
    }
    if #available(iOS 14, *), status == .limited {
      return "granted"
    }
    if status == .restricted || status == .denied {
      return "restricted"
    }
    return "denied"
  }
}
