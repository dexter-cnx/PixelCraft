import AVFoundation
import Flutter
import Foundation
import MetalKit

final class GpuPreviewPlugin {
  static let protocolVersion = 1
  static let channelName = "dev.pixelcraft/gpu_preview_v1"
  static let viewType = "dev.pixelcraft/gpu_camera_preview_v1"

  private let channel: FlutterMethodChannel
  private let registry = MetalRendererRegistry()
  private let capabilityProbe = GpuCapabilityProbe()
  private let probeQueue = DispatchQueue(label: "dev.pixelcraft.gpu.probe", qos: .utility)
  private let harnessQueue = DispatchQueue(label: "dev.pixelcraft.gpu.parity", qos: .userInitiated)

  init(registrar: FlutterPluginRegistrar) {
    channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: registrar.messenger()
    )
    registry.runtimeFailure = { [weak channel] rendererId, message in
      DispatchQueue.main.async {
        channel?.invokeMethod(
          "runtimeFailure",
          arguments: [
            "protocolVersion": Self.protocolVersion,
            "rendererId": rendererId,
            "message": message,
          ]
        )
      }
    }
    registrar.register(
      MetalCameraPreviewViewFactory(registry: registry),
      withId: Self.viewType
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "invalidateCapabilityCache" {
      capabilityProbe.invalidate()
      result(nil)
      return
    }
    guard validateProtocol(call: call, result: result) else { return }

    switch call.method {
    case "probe":
      let args = arguments(call)
      let forceSelfTest = args["forceSelfTest"] as? Bool ?? false
      probeQueue.async { [weak self] in
        guard let self else { return }
        var payload = self.capabilityProbe.probe(forceSelfTest: forceSelfTest)
        payload["protocolVersion"] = Self.protocolVersion
        DispatchQueue.main.async { result(payload) }
      }
    case "requestCameraPermission":
      requestCameraPermission(result: result)
    case "availableCameraLenses":
      result(MetalCameraPreviewRenderer.availableLenses())
    case "runReferenceHarness":
      harnessQueue.async { [weak self] in
        guard self != nil else { return }
        do {
          let payload = try MetalLutParityHarness().runReferenceHarness().toChannelMap()
          DispatchQueue.main.async { result(payload) }
        } catch {
          DispatchQueue.main.async {
            result(self?.flutterError("gpu_harness_failed", error))
          }
        }
      }
    case "runFilmProfileHarness":
      guard let profileId = arguments(call)["profileId"] as? String, !profileId.isEmpty else {
        result(FlutterError(code: "gpu_invalid_profile", message: "profileId is required", details: nil))
        return
      }
      harnessQueue.async { [weak self] in
        guard self != nil else { return }
        do {
          let payload = try MetalLutParityHarness()
            .runFilmProfileHarness(profileId: profileId)
            .toChannelMap()
          DispatchQueue.main.async { result(payload) }
        } catch {
          DispatchQueue.main.async {
            result(self?.flutterError("gpu_film_harness_failed", error))
          }
        }
      }
    case "createRenderer":
      do {
        let id = try registry.create()
        result([
          "protocolVersion": Self.protocolVersion,
          "rendererId": id,
          "state": "created",
        ])
      } catch {
        capabilityProbe.invalidate()
        result(flutterError("gpu_renderer_init_failed", error))
      }
    case "configureSurface":
      withRenderer(call: call, result: result) { _, args in
        guard
          let width = (args["width"] as? NSNumber)?.doubleValue,
          let height = (args["height"] as? NSNumber)?.doubleValue,
          width > 0, height > 0
        else { throw pluginError("Surface dimensions must be positive") }
      }
    case "setFilm":
      withRenderer(call: call, result: result) { renderer, args in
        guard let profileId = args["profileId"] as? String, !profileId.isEmpty else {
          throw pluginError("profileId is required")
        }
        let strength = (args["strength"] as? NSNumber)?.doubleValue ?? 0
        renderer.setFilm(profileId: profileId, strength: strength)
      }
    case "setStrength":
      withRenderer(call: call, result: result) { renderer, args in
        renderer.setStrength((args["strength"] as? NSNumber)?.doubleValue ?? 0)
      }
    case "setViewport":
      withRenderer(call: call, result: result) { _, args in
        guard
          let width = (args["width"] as? NSNumber)?.doubleValue,
          let height = (args["height"] as? NSNumber)?.doubleValue,
          width > 0, height > 0
        else { throw pluginError("Viewport dimensions must be positive") }
      }
    case "setEnabled":
      withRenderer(call: call, result: result) { renderer, args in
        renderer.setEnabled(args["enabled"] as? Bool ?? false)
      }
    case "pause":
      withRenderer(call: call, result: result) { renderer, _ in renderer.pause() }
    case "resume":
      withRenderer(call: call, result: result) { renderer, _ in renderer.resume() }
    case "destroyRenderer":
      guard let id = rendererId(call: call, result: result) else { return }
      registry.destroy(id: id)
      result(nil)
    case "capturePhoto":
      guard let id = rendererId(call: call, result: result) else { return }
      do {
        let renderer = try registry.renderer(id: id)
        renderer.capturePhoto { capture in
          DispatchQueue.main.async {
            switch capture {
            case .success(let path): result(["path": path])
            case .failure(let error): result(self.flutterError("gpu_camera_capture_failed", error))
            }
          }
        }
      } catch {
        result(flutterError("gpu_camera_capture_failed", error))
      }
    case "switchCamera":
      guard let id = rendererId(call: call, result: result) else { return }
      do {
        let renderer = try registry.renderer(id: id)
        renderer.switchCamera { switched in
          DispatchQueue.main.async {
            switch switched {
            case .success(let lens): result(["lensDirection": lens])
            case .failure(let error): result(self.flutterError("gpu_camera_switch_failed", error))
            }
          }
        }
      } catch {
        result(flutterError("gpu_camera_switch_failed", error))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func withRenderer(
    call: FlutterMethodCall,
    result: FlutterResult,
    action: (MetalCameraPreviewRenderer, [String: Any]) throws -> Void
  ) {
    guard let id = rendererId(call: call, result: result) else { return }
    do {
      let renderer = try registry.renderer(id: id)
      try action(renderer, arguments(call))
      result(nil)
    } catch {
      result(flutterError("gpu_renderer_failed", error))
    }
  }

  private func requestCameraPermission(result: @escaping FlutterResult) {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      result(true)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async { result(granted) }
      }
    default:
      result(false)
    }
  }

  private func validateProtocol(call: FlutterMethodCall, result: FlutterResult) -> Bool {
    let version = (arguments(call)["protocolVersion"] as? NSNumber)?.intValue ?? 0
    guard version == Self.protocolVersion else {
      result(FlutterError(
        code: "gpu_protocol_mismatch",
        message: "Native GPU protocol is \(Self.protocolVersion), requested \(version)",
        details: nil
      ))
      return false
    }
    return true
  }

  private func rendererId(call: FlutterMethodCall, result: FlutterResult) -> String? {
    guard let id = arguments(call)["rendererId"] as? String, !id.isEmpty else {
      result(FlutterError(code: "gpu_renderer_invalid", message: "rendererId is required", details: nil))
      return nil
    }
    return id
  }

  private func arguments(_ call: FlutterMethodCall) -> [String: Any] {
    call.arguments as? [String: Any] ?? [:]
  }

  private func flutterError(_ code: String, _ error: Error) -> FlutterError {
    FlutterError(code: code, message: error.localizedDescription, details: nil)
  }

  private func pluginError(_ message: String) -> NSError {
    NSError(domain: "PixelCraftGpu", code: 3001, userInfo: [NSLocalizedDescriptionKey: message])
  }
}

final class MetalRendererRegistry {
  var runtimeFailure: ((String, String) -> Void)?
  private var renderers: [String: MetalCameraPreviewRenderer] = [:]

  func create() throws -> String {
    let id = UUID().uuidString
    let renderer = try MetalCameraPreviewRenderer { [weak self] message in
      self?.runtimeFailure?(id, message)
    }
    renderers[id] = renderer
    return id
  }

  func renderer(id: String) throws -> MetalCameraPreviewRenderer {
    guard let renderer = renderers[id] else {
      throw NSError(
        domain: "PixelCraftGpu",
        code: 3002,
        userInfo: [NSLocalizedDescriptionKey: "Unknown GPU renderer session: \(id)"]
      )
    }
    return renderer
  }

  func destroy(id: String) {
    renderers.removeValue(forKey: id)?.releaseRenderer()
  }

  func attach(id: String, view: MTKView, orientation: UIInterfaceOrientation) throws {
    try renderer(id: id).attach(view: view, orientation: orientation)
  }

  func detach(id: String, view: MTKView) {
    try? renderer(id: id).detach(view: view)
  }
}
