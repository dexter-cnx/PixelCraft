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
        guard let self else { return }
        do {
          let payload = try MetalLutParityHarness().runReferenceHarness().toChannelMap()
          DispatchQueue.main.async { result(payload) }
        } catch {
          DispatchQueue.main.async { result(self.flutterError("gpu_harness_failed", error)) }
        }
      }
    case "runFilmProfileHarness":
      guard let profileId = arguments(call)["profileId"] as? String, !profileId.isEmpty else {
        result(FlutterError(code: "gpu_invalid_profile", message: "profileId is required", details: nil))
        return
      }
      harnessQueue.async { [weak self] in
        guard let self else { return }
        do {
          let payload = try MetalLutParityHarness()
            .runFilmProfileHarness(profileId: profileId)
            .toChannelMap()
          DispatchQueue.main.async { result(payload) }
        } catch {
          DispatchQueue.main.async { result(self.flutterError("gpu_film_harness_failed", error)) }
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

private struct MetalLutParityHarnessResult {
  let passed: Bool
  let maxChannelError: Double
  let samples: Int
  let renderer: String
  let version: String
  let profileId: String

  func toChannelMap() -> [String: Any] {
    [
      "passed": passed,
      "maxChannelError": maxChannelError,
      "samples": samples,
      "renderer": renderer,
      "version": version,
      "profileId": profileId,
    ]
  }
}

private final class MetalLutParityHarness {
  private struct Fixture {
    let input: SIMD4<Float>
    let expected: SIMD3<Double>
  }

  private static let lutSize = 33
  private static let defaultTolerance = 2.0 / 255.0
  private static let supportedProfileIds: Set<String> = [
    "provia_inspired",
    "velvia_inspired",
    "astia_inspired",
    "e100_inspired",
    "ektar_inspired",
    "chrome64_inspired",
  ]

  private static let shaderSource = """
  #include <metal_stdlib>
  using namespace metal;

  kernel void pixelcraft_lut_parity(
    device const float4 *inputs [[buffer(0)]],
    device float4 *outputs [[buffer(1)]],
    texture3d<float, access::sample> lut [[texture(0)]],
    uint gid [[thread_position_in_grid]]) {
    constexpr sampler lutSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    const float lutSize = 33.0;
    float3 source = clamp(inputs[gid].rgb, 0.0, 1.0);
    float3 grid = source * (lutSize - 1.0);
    float3 lutUv = (grid + 0.5) / lutSize;
    outputs[gid] = float4(lut.sample(lutSampler, lutUv).rgb, 1.0);
  }
  """

  private let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private let pipeline: MTLComputePipelineState
  private let lutLoader: MetalFilmLutLoader

  init() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
      throw Self.error("Metal device is unavailable")
    }
    guard let commandQueue = device.makeCommandQueue() else {
      throw Self.error("Unable to create Metal parity command queue")
    }
    let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
    guard let function = library.makeFunction(name: "pixelcraft_lut_parity") else {
      throw Self.error("Metal LUT parity kernel is unavailable")
    }

    self.device = device
    self.commandQueue = commandQueue
    self.pipeline = try device.makeComputePipelineState(function: function)
    self.lutLoader = MetalFilmLutLoader(device: device)
  }

  func runReferenceHarness() throws -> MetalLutParityHarnessResult {
    let values: [SIMD3<Float>] = [
      SIMD3(0, 0, 0),
      SIMD3(1, 1, 1),
      SIMD3(1, 0, 0),
      SIMD3(0, 1, 0),
      SIMD3(0, 0, 1),
      SIMD3(0.5, 0.5, 0.5),
      SIMD3(0.13, 0.47, 0.91),
      SIMD3(0.82, 0.24, 0.36),
    ]
    let fixtures = values.map { value in
      Fixture(
        input: SIMD4(value.x, value.y, value.z, 1),
        expected: SIMD3(Double(value.x), Double(value.y), Double(value.z))
      )
    }
    return try run(
      profileId: "identity",
      texture: lutLoader.makeIdentity(),
      fixtures: fixtures,
      tolerance: Self.defaultTolerance
    )
  }

  func runFilmProfileHarness(profileId: String) throws -> MetalLutParityHarnessResult {
    guard Self.supportedProfileIds.contains(profileId) else {
      throw Self.error("Unknown Film Profile: \(profileId)")
    }

    let parity = try loadParityFixture()
    guard let inputs = parity["inputs"] as? [Any],
          let profiles = parity["profiles"] as? [String: Any],
          let expectedValues = profiles[profileId] as? [Any],
          inputs.count == expectedValues.count
    else {
      throw Self.error("Invalid parity fixture for \(profileId)")
    }

    let fixtures = try zip(inputs, expectedValues).map { inputValue, expectedValue in
      let input = try Self.rgb(inputValue, label: "input")
      let expected = try Self.rgb(expectedValue, label: "expected")
      return Fixture(
        input: SIMD4(Float(input.x), Float(input.y), Float(input.z), 1),
        expected: expected
      )
    }

    let tolerance = (parity["tolerance"] as? NSNumber)?.doubleValue ?? Self.defaultTolerance
    return try run(
      profileId: profileId,
      texture: lutLoader.load(profileId: profileId),
      fixtures: fixtures,
      tolerance: tolerance
    )
  }

  private func run(
    profileId: String,
    texture: MTLTexture,
    fixtures: [Fixture],
    tolerance: Double
  ) throws -> MetalLutParityHarnessResult {
    guard !fixtures.isEmpty else {
      throw Self.error("Metal LUT parity fixture list is empty")
    }

    let inputs = fixtures.map(\.input)
    let inputBuffer = try inputs.withUnsafeBytes { raw -> MTLBuffer in
      guard let base = raw.baseAddress,
            let buffer = device.makeBuffer(bytes: base, length: raw.count, options: .storageModeShared)
      else { throw Self.error("Unable to create Metal parity input buffer") }
      return buffer
    }

    let outputLength = fixtures.count * MemoryLayout<SIMD4<Float>>.stride
    guard let outputBuffer = device.makeBuffer(length: outputLength, options: .storageModeShared),
          let commandBuffer = commandQueue.makeCommandBuffer(),
          let encoder = commandBuffer.makeComputeCommandEncoder()
    else {
      throw Self.error("Unable to allocate Metal parity command resources")
    }

    encoder.setComputePipelineState(pipeline)
    encoder.setBuffer(inputBuffer, offset: 0, index: 0)
    encoder.setBuffer(outputBuffer, offset: 0, index: 1)
    encoder.setTexture(texture, index: 0)

    let threads = MTLSize(width: fixtures.count, height: 1, depth: 1)
    let width = max(1, min(pipeline.threadExecutionWidth, fixtures.count))
    let group = MTLSize(width: width, height: 1, depth: 1)
    encoder.dispatchThreads(threads, threadsPerThreadgroup: group)
    encoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    if let commandError = commandBuffer.error {
      throw commandError
    }
    guard commandBuffer.status == .completed else {
      throw Self.error("Metal LUT parity command did not complete")
    }

    let output = outputBuffer.contents().bindMemory(
      to: SIMD4<Float>.self,
      capacity: fixtures.count
    )
    var maxError = 0.0
    for index in fixtures.indices {
      let actual = output[index]
      let expected = fixtures[index].expected
      maxError = max(maxError, abs(Double(actual.x) - expected.x))
      maxError = max(maxError, abs(Double(actual.y) - expected.y))
      maxError = max(maxError, abs(Double(actual.z) - expected.z))
    }

    return MetalLutParityHarnessResult(
      passed: maxError <= tolerance,
      maxChannelError: maxError,
      samples: fixtures.count,
      renderer: device.name,
      version: "Metal",
      profileId: profileId
    )
  }

  private func loadParityFixture() throws -> [String: Any] {
    guard let url = Bundle.main.url(
      forResource: "native_parity",
      withExtension: "json",
      subdirectory: "gpu_luts"
    ) else {
      throw Self.error("Missing gpu_luts/native_parity.json")
    }
    let data = try Data(contentsOf: url)
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw Self.error("Unable to decode native_parity.json")
    }
    guard (json["version"] as? NSNumber)?.intValue == 1 else {
      throw Self.error("Unsupported native GPU parity fixture version")
    }
    guard (json["lutSize"] as? NSNumber)?.intValue == Self.lutSize else {
      throw Self.error("Native GPU parity fixture LUT size mismatch")
    }
    return json
  }

  private static func rgb(_ value: Any, label: String) throws -> SIMD3<Double> {
    guard let values = value as? [Any], values.count == 3 else {
      throw error("Parity \(label) must have three channels")
    }
    let channels = values.compactMap { ($0 as? NSNumber)?.doubleValue }
    guard channels.count == 3 else {
      throw error("Parity \(label) contains a non-numeric channel")
    }
    return SIMD3(channels[0], channels[1], channels[2])
  }

  private static func error(_ message: String) -> NSError {
    NSError(
      domain: "PixelCraftGpuParity",
      code: 4001,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}
