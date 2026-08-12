import Foundation
import Metal
import UIKit

final class GpuCapabilityProbe {
  private static let cacheSchema = 1
  private static let cacheKey = "dev.pixelcraft.gpu.ios.capability.v1"
  private let defaults = UserDefaults.standard

  func invalidate() {
    defaults.removeObject(forKey: Self.cacheKey)
  }

  func probe(forceSelfTest: Bool) -> [String: Any] {
    let identity = cacheIdentity()
    if !forceSelfTest,
       let cached = defaults.dictionary(forKey: Self.cacheKey),
       cached["identity"] as? String == identity,
       let payload = cached["payload"] as? [String: Any] {
      var result = payload
      result["cached"] = true
      return result
    }

    let result = performProbe()
    defaults.set(
      ["identity": identity, "payload": result],
      forKey: Self.cacheKey
    )
    return result
  }

  private func performProbe() -> [String: Any] {
    guard let device = MTLCreateSystemDefaultDevice() else {
      return failure(code: "backend_unavailable", detail: "Metal device is unavailable")
    }

    guard MetalFilmLutLoader.canonicalAssetsAvailable() else {
      return failure(
        code: "native_assets_unavailable",
        detail: "Canonical Film GPU assets are missing from the iOS bundle",
        renderer: device.name
      )
    }

    do {
      _ = try MetalCameraPreviewRenderer.makeLibrary(device: device)
      let loader = MetalFilmLutLoader(device: device)
      _ = try loader.makeIdentity()
      _ = try loader.load(profileId: "provia_inspired")
    } catch {
      return failure(
        code: "shader_self_test_failed",
        detail: error.localizedDescription,
        renderer: device.name
      )
    }

    return [
      "backend": "iosMetal",
      "available": true,
      "supportsLut33": true,
      "maxLutSize": 33,
      "renderer": device.name,
      "version": "Metal G1",
      "selfTestPassed": true,
      "assetsLoaded": true,
      "blacklisted": false,
      "cached": false,
    ]
  }

  private func failure(
    code: String,
    detail: String,
    renderer: String = ""
  ) -> [String: Any] {
    [
      "backend": "iosMetal",
      "available": false,
      "supportsLut33": false,
      "maxLutSize": 0,
      "renderer": renderer,
      "version": "Metal G1",
      "selfTestPassed": false,
      "assetsLoaded": code != "native_assets_unavailable",
      "blacklisted": false,
      "cached": false,
      "failureCode": code,
      "failureDetail": detail,
    ]
  }

  private func cacheIdentity() -> String {
    let info = Bundle.main.infoDictionary ?? [:]
    let version = info["CFBundleShortVersionString"] as? String ?? ""
    let build = info["CFBundleVersion"] as? String ?? ""
    let os = UIDevice.current.systemVersion
    let model = UIDevice.current.model
    return "\(Self.cacheSchema)|\(version)|\(build)|\(os)|\(model)"
  }
}
