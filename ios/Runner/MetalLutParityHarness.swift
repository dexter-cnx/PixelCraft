import Foundation
import Metal

struct MetalLutParityHarnessResult {
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

final class MetalLutParityHarness {
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
