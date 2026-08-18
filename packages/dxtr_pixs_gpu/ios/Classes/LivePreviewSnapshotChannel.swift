import Flutter
import MetalKit
import UIKit

final class LivePreviewSnapshotChannel {
  static let channelName = "dev.pixelcraft/gpu_preview_snapshot_v1"

  private let channel: FlutterMethodChannel

  init(registrar: FlutterPluginRegistrar) {
    channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "snapshot" else {
      result(FlutterMethodNotImplemented)
      return
    }

    let args = call.arguments as? [String: Any] ?? [:]
    let maxEdge = max(96, min(512, (args["maxEdge"] as? NSNumber)?.intValue ?? 180))
    let qualityValue = (args["jpegQuality"] as? NSNumber)?.doubleValue ?? 0.72
    let jpegQuality = max(0.4, min(0.95, qualityValue))

    DispatchQueue.main.async {
      do {
        let data = try self.snapshot(maxEdge: maxEdge, jpegQuality: jpegQuality)
        result(FlutterStandardTypedData(bytes: data))
      } catch {
        result(
          FlutterError(
            code: "gpu_preview_snapshot_failed",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    }
  }

  private func snapshot(maxEdge: Int, jpegQuality: Double) throws -> Data {
    guard let metalView = activeMetalView() else {
      throw snapshotError("Active Metal camera preview is unavailable")
    }
    guard metalView.bounds.width > 1, metalView.bounds.height > 1 else {
      throw snapshotError("Active Metal camera preview has invalid bounds")
    }

    let sourceSize = metalView.bounds.size
    let sourceRenderer = UIGraphicsImageRenderer(size: sourceSize)
    let source = sourceRenderer.image { _ in
      metalView.drawHierarchy(in: CGRect(origin: .zero, size: sourceSize), afterScreenUpdates: false)
    }

    let side = min(source.size.width, source.size.height)
    guard side > 1 else {
      throw snapshotError("Live preview snapshot has invalid dimensions")
    }
    let cropRect = CGRect(
      x: (source.size.width - side) * 0.5,
      y: (source.size.height - side) * 0.5,
      width: side,
      height: side
    )
    guard let cgImage = source.cgImage?.cropping(to: cropRect.integral) else {
      throw snapshotError("Unable to crop live preview snapshot")
    }

    let targetEdge = min(CGFloat(maxEdge), side)
    let targetSize = CGSize(width: targetEdge, height: targetEdge)
    let targetRenderer = UIGraphicsImageRenderer(size: targetSize)
    let thumbnail = targetRenderer.image { _ in
      UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: targetSize))
    }
    guard let data = thumbnail.jpegData(compressionQuality: jpegQuality) else {
      throw snapshotError("Unable to encode live preview snapshot")
    }
    return data
  }

  private func activeMetalView() -> MTKView? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap(\.windows)
    let roots = windows
      .sorted { lhs, rhs in
        if lhs.isKeyWindow != rhs.isKeyWindow { return lhs.isKeyWindow }
        return lhs.windowLevel.rawValue > rhs.windowLevel.rawValue
      }
      .compactMap(\.rootViewController?.view)

    for root in roots {
      if let view = findMetalView(in: root), !view.isHidden, view.alpha > 0.01 {
        return view
      }
    }
    return nil
  }

  private func findMetalView(in view: UIView) -> MTKView? {
    if let metal = view as? MTKView { return metal }
    for child in view.subviews.reversed() {
      if let match = findMetalView(in: child) { return match }
    }
    return nil
  }

  private func snapshotError(_ message: String) -> NSError {
    NSError(
      domain: "PixelCraftGpuSnapshot",
      code: 5001,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}
