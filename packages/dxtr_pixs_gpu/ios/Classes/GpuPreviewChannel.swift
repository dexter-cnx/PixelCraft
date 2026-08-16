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
    case "runGaussianBlurHarness":
      harnessQueue.async { [weak self] in
        guard let self else { return }
        do {
          let payload = try MetalGaussianBlurParityHarness().run()
          DispatchQueue.main.async { result(payload) }
        } catch {
          DispatchQueue.main.async {
            result(self.flutterError("gpu_gaussian_blur_harness_failed", error))
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
    case "setCameraLook":
      withRenderer(call: call, result: result) { renderer, args in
        renderer.setCameraLook(try NativeGpuCameraLook(arguments: args))
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

private final class MetalGaussianBlurParityHarness {
  private struct BlurUniforms {
    var width: UInt32
    var height: UInt32
    var radius: UInt32
    var axis: UInt32
    var sigma: Float
  }

  private static let width = 9
  private static let height = 9
  private static let tolerance = 2.0 / 255.0
  private static let values: [Float] = [0.25, 0.50, 1.00, 1.50, 2.00]

  private static let shaderSource = """
  #include <metal_stdlib>
  using namespace metal;

  struct BlurUniforms {
    uint width;
    uint height;
    uint radius;
    uint axis;
    float sigma;
  };

  inline float gaussian_pdf(float x, float sigma) {
    return (1.0 / (sigma * sqrt(2.0 * M_PI_F))) * exp(-(x * x) / (2.0 * sigma * sigma));
  }

  kernel void pixelcraft_gaussian_023(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant BlurUniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= u.width || gid.y >= u.height) return;

    float4 acc = float4(0.0);
    int radius = int(u.radius);
    for (int offset = -radius; offset <= radius; ++offset) {
      int2 p = int2(gid);
      if (u.axis == 0) p.x += offset; else p.y += offset;
      p.x = clamp(p.x, 0, int(u.width) - 1);
      p.y = clamp(p.y, 0, int(u.height) - 1);
      float weight = gaussian_pdf(float(abs(offset)), u.sigma);
      acc += input.read(uint2(p)) * weight;
    }
    output.write(clamp(acc, 0.0, 1.0), gid);
  }
  """

  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let pipeline: MTLComputePipelineState

  init() throws {
    guard let device = MTLCreateSystemDefaultDevice(),
          let queue = device.makeCommandQueue()
    else { throw Self.error("Metal blur parity device/queue unavailable") }
    let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
    guard let function = library.makeFunction(name: "pixelcraft_gaussian_023") else {
      throw Self.error("Gaussian parity kernel unavailable")
    }
    self.device = device
    self.queue = queue
    self.pipeline = try device.makeComputePipelineState(function: function)
  }

  func run() throws -> [String: Any] {
    let source = Self.makeFixture()
    var cases: [[String: Any]] = []
    var overallMax = 0.0
    var overallPassed = true

    for value in Self.values {
      let sigma = max(value * 2.5, 0.01)
      let expected = Self.rust023Reference(source: source, sigma: sigma)
      let actual = try runMetal(source: source, sigma: sigma)
      var maxError = 0.0
      for index in expected.indices {
        for channel in 0..<3 {
          let e = Double(expected[index][channel]) / 255.0
          let a = Double(actual[index][channel]) / 255.0
          maxError = max(maxError, abs(a - e))
        }
      }
      let passed = maxError <= Self.tolerance
      overallMax = max(overallMax, maxError)
      overallPassed = overallPassed && passed
      cases.append([
        "name": String(format: "gaussian_blur_%.2f", value),
        "value": value,
        "sigma": sigma,
        "radius": Int(ceil(2.0 * sigma)),
        "samples": Self.width * Self.height,
        "maxChannelError": maxError,
        "passed": passed,
      ])
    }

    return [
      "backend": "iosMetal",
      "reference": "imageproc 0.23 gaussian_blur_f32 separable/u8 continuity semantics",
      "tolerance": Self.tolerance,
      "overallMaxChannelError": overallMax,
      "passed": overallPassed,
      "cases": cases,
      "width": Self.width,
      "height": Self.height,
    ]
  }

  private func runMetal(source: [[UInt8]], sigma: Float) throws -> [[UInt8]] {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba8Unorm,
      width: Self.width,
      height: Self.height,
      mipmapped: false
    )
    descriptor.usage = [.shaderRead, .shaderWrite]
    descriptor.storageMode = .shared
    guard let input = device.makeTexture(descriptor: descriptor),
          let intermediate = device.makeTexture(descriptor: descriptor),
          let output = device.makeTexture(descriptor: descriptor)
    else { throw Self.error("Unable to allocate Gaussian parity textures") }

    let bytes = source.flatMap { $0 }
    bytes.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { return }
      input.replace(
        region: MTLRegionMake2D(0, 0, Self.width, Self.height),
        mipmapLevel: 0,
        withBytes: base,
        bytesPerRow: Self.width * 4
      )
    }

    let radius = UInt32(ceil(2.0 * sigma))
    try encodePass(input: input, output: intermediate, sigma: sigma, radius: radius, axis: 0)
    try encodePass(input: intermediate, output: output, sigma: sigma, radius: radius, axis: 1)

    var out = [UInt8](repeating: 0, count: Self.width * Self.height * 4)
    output.getBytes(
      &out,
      bytesPerRow: Self.width * 4,
      from: MTLRegionMake2D(0, 0, Self.width, Self.height),
      mipmapLevel: 0
    )
    return stride(from: 0, to: out.count, by: 4).map {
      [out[$0], out[$0 + 1], out[$0 + 2], out[$0 + 3]]
    }
  }

  private func encodePass(
    input: MTLTexture,
    output: MTLTexture,
    sigma: Float,
    radius: UInt32,
    axis: UInt32
  ) throws {
    guard let command = queue.makeCommandBuffer(),
          let encoder = command.makeComputeCommandEncoder()
    else { throw Self.error("Unable to create Gaussian parity command") }
    var uniforms = BlurUniforms(
      width: UInt32(Self.width),
      height: UInt32(Self.height),
      radius: radius,
      axis: axis,
      sigma: sigma
    )
    encoder.setComputePipelineState(pipeline)
    encoder.setTexture(input, index: 0)
    encoder.setTexture(output, index: 1)
    encoder.setBytes(&uniforms, length: MemoryLayout<BlurUniforms>.stride, index: 0)
    let w = pipeline.threadExecutionWidth
    let h = max(1, pipeline.maxTotalThreadsPerThreadgroup / w)
    encoder.dispatchThreads(
      MTLSize(width: Self.width, height: Self.height, depth: 1),
      threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1)
    )
    encoder.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    if let error = command.error { throw error }
  }

  private static func rust023Reference(source: [[UInt8]], sigma: Float) -> [[UInt8]] {
    let radius = Int(ceil(2.0 * sigma))
    let kernel = (-radius...radius).map { gaussianPdf(Float(abs($0)), sigma: sigma) }
    let horizontal = filter(source: source, kernel: kernel, horizontal: true)
    return filter(source: horizontal, kernel: kernel, horizontal: false)
  }

  private static func filter(
    source: [[UInt8]],
    kernel: [Float],
    horizontal: Bool
  ) -> [[UInt8]] {
    let radius = kernel.count / 2
    var output = Array(repeating: [UInt8](repeating: 0, count: 4), count: width * height)
    for y in 0..<height {
      for x in 0..<width {
        var accum = SIMD4<Float>(repeating: 0)
        for index in kernel.indices {
          let offset = index - radius
          let sx = horizontal ? min(width - 1, max(0, x + offset)) : x
          let sy = horizontal ? y : min(height - 1, max(0, y + offset))
          let pixel = source[sy * width + sx]
          let weight = kernel[index]
          accum += SIMD4(
            Float(pixel[0]), Float(pixel[1]), Float(pixel[2]), Float(pixel[3])
          ) * weight
        }
        output[y * width + x] = [
          clampU8(accum.x), clampU8(accum.y), clampU8(accum.z), clampU8(accum.w),
        ]
      }
    }
    return output
  }

  private static func gaussianPdf(_ x: Float, sigma: Float) -> Float {
    1.0 / (sigma * sqrt(2.0 * Float.pi)) * exp(-(x * x) / (2.0 * sigma * sigma))
  }

  private static func clampU8(_ value: Float) -> UInt8 {
    UInt8(max(0, min(255, Int(value.rounded()))))
  }

  private static func makeFixture() -> [[UInt8]] {
    var pixels: [[UInt8]] = []
    pixels.reserveCapacity(width * height)
    for y in 0..<height {
      for x in 0..<width {
        let checker = ((x + y) % 2 == 0) ? 28 : 224
        let r = UInt8((checker + x * 13 + y * 7) % 256)
        let g = UInt8((40 + x * 21 + y * 17) % 256)
        let b = UInt8((220 + x * 9 + y * 29) % 256)
        pixels.append([r, g, b, 255])
      }
    }
    return pixels
  }

  private static func error(_ message: String) -> NSError {
    NSError(
      domain: "PixelCraftGaussianParity",
      code: 4300,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}
