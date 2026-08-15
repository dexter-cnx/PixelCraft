import Flutter
import Metal
import QuartzCore

// G2 editor GPU verification diagnostics remain part of the GPU plugin so
// package extraction does not remove the parity/latency verification surface.
final class GpuEditorVerificationDiagnostics {
  static let shared = GpuEditorVerificationDiagnostics()
  static let channelName = "dev.pixelcraft/gpu_editor_diagnostics_v1"

  private let queue = DispatchQueue(
    label: "dev.pixelcraft.gpu.editor.verification",
    qos: .userInitiated
  )
  private var channel: FlutterMethodChannel?

  private init() {}

  func register(messenger: FlutterBinaryMessenger) {
    guard channel == nil else { return }
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "runAdjustmentParity":
        queue.async {
          do {
            let payload = try EditorMetalVerificationHarness().runAdjustmentParity()
            DispatchQueue.main.async { result(payload) }
          } catch {
            DispatchQueue.main.async {
              result(FlutterError(
                code: "gpu_editor_parity_failed",
                message: error.localizedDescription,
                details: nil
              ))
            }
          }
        }
      case "runLatencyBenchmark":
        queue.async {
          do {
            let payload = try EditorMetalVerificationHarness().runLatencyBenchmark()
            DispatchQueue.main.async { result(payload) }
          } catch {
            DispatchQueue.main.async {
              result(FlutterError(
                code: "gpu_editor_latency_failed",
                message: error.localizedDescription,
                details: nil
              ))
            }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

private final class EditorMetalVerificationHarness {
  private struct AdjustmentUniforms {
    var brightness: Float
    var contrast: Float
    var saturation: Float
    var padding: Float = 0
  }

  private struct SharpenUniforms {
    var width: UInt32
    var height: UInt32
    var strength: Float
    var padding: Float = 0
  }

  private struct LatencyUniforms {
    var width: UInt32
    var height: UInt32
    var brightness: Float
    var contrast: Float
    var saturation: Float
    var filmStrength: Float
    var padding0: Float = 0
    var padding1: Float = 0
  }

  private struct ParityCase {
    let name: String
    let brightness: Float
    let contrast: Float
    let saturation: Float
  }

  private static let shaderSource = """
  #include <metal_stdlib>
  using namespace metal;

  struct AdjustmentUniforms {
    float brightness;
    float contrast;
    float saturation;
    float padding;
  };

  struct SharpenUniforms {
    uint width;
    uint height;
    float strength;
    float padding;
  };

  struct LatencyUniforms {
    uint width;
    uint height;
    float brightness;
    float contrast;
    float saturation;
    float filmStrength;
    float padding0;
    float padding1;
  };

  inline float3 apply_adjustments(float3 color, float brightness, float contrast, float saturation) {
    color = clamp(color + (brightness - 1.0), 0.0, 1.0);
    const float midpoint = 128.0 / 255.0;
    color = clamp((color - midpoint) * contrast + midpoint, 0.0, 1.0);
    const float luminance = dot(color, float3(0.2126, 0.7152, 0.0722));
    return clamp(luminance + (color - luminance) * saturation, 0.0, 1.0);
  }

  kernel void pixelcraft_editor_adjustment_parity(
    device const float4 *input [[buffer(0)]],
    device float4 *output [[buffer(1)]],
    constant AdjustmentUniforms &uniforms [[buffer(2)]],
    uint index [[thread_position_in_grid]]) {
    float3 color = apply_adjustments(
      input[index].rgb,
      uniforms.brightness,
      uniforms.contrast,
      uniforms.saturation
    );
    output[index] = float4(color, 1.0);
  }

  kernel void pixelcraft_editor_sharpen_parity(
    device const float4 *input [[buffer(0)]],
    device float4 *output [[buffer(1)]],
    constant SharpenUniforms &uniforms [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height) return;

    int width = int(uniforms.width);
    int height = int(uniforms.height);
    int x = int(gid.x);
    int y = int(gid.y);

    int leftX = max(x - 1, 0);
    int rightX = min(x + 1, width - 1);
    int upY = max(y - 1, 0);
    int downY = min(y + 1, height - 1);

    int centerIndex = y * width + x;
    int leftIndex = y * width + leftX;
    int rightIndex = y * width + rightX;
    int upIndex = upY * width + x;
    int downIndex = downY * width + x;

    float strength = clamp(uniforms.strength, 0.0, 2.0);
    float3 center = input[centerIndex].rgb;
    float3 color = center * (1.0 + 4.0 * strength)
      - strength * (
        input[leftIndex].rgb +
        input[rightIndex].rgb +
        input[upIndex].rgb +
        input[downIndex].rgb
      );
    output[centerIndex] = float4(clamp(color, 0.0, 1.0), 1.0);
  }

  kernel void pixelcraft_editor_latency(
    texture2d<float, access::write> output [[texture(0)]],
    texture3d<float> lut [[texture(1)]],
    constant LatencyUniforms &uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height) return;
    float2 uv = float2(gid) / float2(max(uniforms.width - 1, 1u), max(uniforms.height - 1, 1u));
    float3 source = float3(uv.x, uv.y, 0.25 + 0.5 * uv.x);
    float3 color = apply_adjustments(
      source,
      uniforms.brightness,
      uniforms.contrast,
      uniforms.saturation
    );
    constexpr sampler lutSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    const float lutSize = 33.0;
    float3 grid = clamp(color, 0.0, 1.0) * (lutSize - 1.0);
    float3 lutUv = (grid + 0.5) / lutSize;
    float3 film = lut.sample(lutSampler, lutUv).rgb;
    float3 finalColor = mix(color, film, clamp(uniforms.filmStrength, 0.0, 1.0));
    output.write(float4(finalColor, 1.0), gid);
  }
  """

  private let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private let parityPipeline: MTLComputePipelineState
  private let sharpenPipeline: MTLComputePipelineState
  private let latencyPipeline: MTLComputePipelineState
  private let lutLoader: MetalFilmLutLoader

  init() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
      throw Self.error("Metal device is unavailable")
    }
    guard let commandQueue = device.makeCommandQueue() else {
      throw Self.error("Unable to create Metal verification command queue")
    }
    let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
    guard
      let parityFunction = library.makeFunction(name: "pixelcraft_editor_adjustment_parity"),
      let sharpenFunction = library.makeFunction(name: "pixelcraft_editor_sharpen_parity"),
      let latencyFunction = library.makeFunction(name: "pixelcraft_editor_latency")
    else {
      throw Self.error("Editor verification Metal functions are unavailable")
    }

    self.device = device
    self.commandQueue = commandQueue
    self.parityPipeline = try device.makeComputePipelineState(function: parityFunction)
    self.sharpenPipeline = try device.makeComputePipelineState(function: sharpenFunction)
    self.latencyPipeline = try device.makeComputePipelineState(function: latencyFunction)
    self.lutLoader = MetalFilmLutLoader(device: device)
  }

  func runAdjustmentParity() throws -> [String: Any] {
    let samples: [SIMD4<Float>] = [
      rgba(0, 0, 0), rgba(255, 255, 255), rgba(255, 0, 0), rgba(0, 255, 0),
      rgba(0, 0, 255), rgba(64, 128, 192), rgba(192, 128, 64), rgba(16, 48, 240),
      rgba(240, 48, 16), rgba(32, 200, 96), rgba(127, 128, 129), rgba(8, 240, 128),
      rgba(220, 180, 140), rgba(40, 80, 120), rgba(12, 34, 56), rgba(201, 77, 155),
    ]
    let cases = [
      ParityCase(name: "brightness_0.65", brightness: 0.65, contrast: 1, saturation: 1),
      ParityCase(name: "brightness_1.35", brightness: 1.35, contrast: 1, saturation: 1),
      ParityCase(name: "contrast_0.70", brightness: 1, contrast: 0.70, saturation: 1),
      ParityCase(name: "contrast_1.40", brightness: 1, contrast: 1.40, saturation: 1),
      ParityCase(name: "saturation_0.00", brightness: 1, contrast: 1, saturation: 0),
      ParityCase(name: "saturation_1.60", brightness: 1, contrast: 1, saturation: 1.60),
    ]

    let tolerance = 1.0 / 255.0
    var results: [[String: Any]] = []
    var overallMax = 0.0
    var overallPassed = true

    for testCase in cases {
      let gpu = try runParityCase(samples: samples, testCase: testCase)
      var maxError = 0.0
      for index in samples.indices {
        let expected = rustReference(samples[index], testCase: testCase)
        let actual = gpu[index]
        let rgbError = max(
          Double(abs(actual.x - expected.x)),
          max(Double(abs(actual.y - expected.y)), Double(abs(actual.z - expected.z)))
        )
        maxError = max(maxError, rgbError)
      }
      let passed = maxError <= tolerance
      overallMax = max(overallMax, maxError)
      overallPassed = overallPassed && passed
      results.append([
        "name": testCase.name,
        "samples": samples.count,
        "maxChannelError": maxError,
        "passed": passed,
      ])
    }

    let spatialWidth = 5
    let spatialHeight = 5
    let spatial = spatialFixture()
    for strength: Float in [0.50, 1.00, 1.50] {
      let gpu = try runSharpenCase(
        samples: spatial,
        width: spatialWidth,
        height: spatialHeight,
        strength: strength
      )
      let expected = rustSharpenReference(
        spatial,
        width: spatialWidth,
        height: spatialHeight,
        strength: strength
      )
      var maxError = 0.0
      for index in spatial.indices {
        let actual = gpu[index]
        let reference = expected[index]
        let rgbError = max(
          Double(abs(actual.x - reference.x)),
          max(Double(abs(actual.y - reference.y)), Double(abs(actual.z - reference.z)))
        )
        maxError = max(maxError, rgbError)
      }
      let passed = maxError <= tolerance
      overallMax = max(overallMax, maxError)
      overallPassed = overallPassed && passed
      results.append([
        "name": String(format: "sharpen_%.2f", strength),
        "samples": spatial.count,
        "maxChannelError": maxError,
        "passed": passed,
      ])
    }

    return [
      "backend": "iosMetal",
      "reference": "rust/src/filters.rs u8 + filter3x3 continuity semantics",
      "tolerance": tolerance,
      "overallMaxChannelError": overallMax,
      "passed": overallPassed,
      "cases": results,
      "filmParity": "covered by canonical G1 Metal 33^3 LUT parity harness",
    ]
  }

  func runLatencyBenchmark() throws -> [String: Any] {
    let width = 1024
    let height = 1024
    let iterations = 60
    let warmup = 8
    let lut = try lutLoader.load(profileId: "velvia_inspired")

    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba8Unorm,
      width: width,
      height: height,
      mipmapped: false
    )
    descriptor.usage = [.shaderWrite]
    descriptor.storageMode = .private
    guard let output = device.makeTexture(descriptor: descriptor) else {
      throw Self.error("Unable to allocate editor latency output texture")
    }

    var uniforms = LatencyUniforms(
      width: UInt32(width),
      height: UInt32(height),
      brightness: 1.12,
      contrast: 1.18,
      saturation: 1.20,
      filmStrength: 1
    )

    for _ in 0..<warmup {
      _ = try submitLatencyWork(output: output, lut: lut, uniforms: &uniforms)
    }

    var timings: [Double] = []
    timings.reserveCapacity(iterations)
    for _ in 0..<iterations {
      timings.append(try submitLatencyWork(output: output, lut: lut, uniforms: &uniforms))
    }
    timings.sort()

    let average = timings.reduce(0, +) / Double(timings.count)
    let p50 = percentile(timings, 0.50)
    let p95 = percentile(timings, 0.95)
    let p99 = percentile(timings, 0.99)
    let maximum = timings.last ?? 0
    let targetMs = 16.67

    return [
      "backend": "iosMetal",
      "device": device.name,
      "width": width,
      "height": height,
      "iterations": iterations,
      "workload": "brightness+contrast+saturation+velvia100",
      "averageMs": average,
      "p50Ms": p50,
      "p95Ms": p95,
      "p99Ms": p99,
      "maxMs": maximum,
      "targetMs": targetMs,
      "passed": p95 <= targetMs,
    ]
  }

  private func runParityCase(
    samples: [SIMD4<Float>],
    testCase: ParityCase
  ) throws -> [SIMD4<Float>] {
    let byteCount = samples.count * MemoryLayout<SIMD4<Float>>.stride
    guard
      let input = device.makeBuffer(bytes: samples, length: byteCount, options: .storageModeShared),
      let output = device.makeBuffer(length: byteCount, options: .storageModeShared),
      let commandBuffer = commandQueue.makeCommandBuffer(),
      let encoder = commandBuffer.makeComputeCommandEncoder()
    else {
      throw Self.error("Unable to allocate editor parity Metal resources")
    }

    var uniforms = AdjustmentUniforms(
      brightness: testCase.brightness,
      contrast: testCase.contrast,
      saturation: testCase.saturation
    )
    encoder.setComputePipelineState(parityPipeline)
    encoder.setBuffer(input, offset: 0, index: 0)
    encoder.setBuffer(output, offset: 0, index: 1)
    encoder.setBytes(&uniforms, length: MemoryLayout<AdjustmentUniforms>.stride, index: 2)
    let width = min(parityPipeline.maxTotalThreadsPerThreadgroup, samples.count)
    encoder.dispatchThreads(
      MTLSize(width: samples.count, height: 1, depth: 1),
      threadsPerThreadgroup: MTLSize(width: max(width, 1), height: 1, depth: 1)
    )
    encoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    if let error = commandBuffer.error { throw error }

    let pointer = output.contents().bindMemory(to: SIMD4<Float>.self, capacity: samples.count)
    return Array(UnsafeBufferPointer(start: pointer, count: samples.count))
  }

  private func runSharpenCase(
    samples: [SIMD4<Float>],
    width: Int,
    height: Int,
    strength: Float
  ) throws -> [SIMD4<Float>] {
    let byteCount = samples.count * MemoryLayout<SIMD4<Float>>.stride
    guard
      let input = device.makeBuffer(bytes: samples, length: byteCount, options: .storageModeShared),
      let output = device.makeBuffer(length: byteCount, options: .storageModeShared),
      let commandBuffer = commandQueue.makeCommandBuffer(),
      let encoder = commandBuffer.makeComputeCommandEncoder()
    else {
      throw Self.error("Unable to allocate sharpen parity Metal resources")
    }

    var uniforms = SharpenUniforms(
      width: UInt32(width),
      height: UInt32(height),
      strength: strength
    )
    encoder.setComputePipelineState(sharpenPipeline)
    encoder.setBuffer(input, offset: 0, index: 0)
    encoder.setBuffer(output, offset: 0, index: 1)
    encoder.setBytes(&uniforms, length: MemoryLayout<SharpenUniforms>.stride, index: 2)
    let threadWidth = sharpenPipeline.threadExecutionWidth
    let threadHeight = max(1, sharpenPipeline.maxTotalThreadsPerThreadgroup / threadWidth)
    encoder.dispatchThreads(
      MTLSize(width: width, height: height, depth: 1),
      threadsPerThreadgroup: MTLSize(width: threadWidth, height: threadHeight, depth: 1)
    )
    encoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    if let error = commandBuffer.error { throw error }

    let pointer = output.contents().bindMemory(to: SIMD4<Float>.self, capacity: samples.count)
    return Array(UnsafeBufferPointer(start: pointer, count: samples.count))
  }

  private func submitLatencyWork(
    output: MTLTexture,
    lut: MTLTexture,
    uniforms: inout LatencyUniforms
  ) throws -> Double {
    guard
      let commandBuffer = commandQueue.makeCommandBuffer(),
      let encoder = commandBuffer.makeComputeCommandEncoder()
    else {
      throw Self.error("Unable to create editor latency Metal command")
    }

    encoder.setComputePipelineState(latencyPipeline)
    encoder.setTexture(output, index: 0)
    encoder.setTexture(lut, index: 1)
    encoder.setBytes(&uniforms, length: MemoryLayout<LatencyUniforms>.stride, index: 0)
    let threadWidth = latencyPipeline.threadExecutionWidth
    let threadHeight = max(1, latencyPipeline.maxTotalThreadsPerThreadgroup / threadWidth)
    encoder.dispatchThreads(
      MTLSize(width: output.width, height: output.height, depth: 1),
      threadsPerThreadgroup: MTLSize(width: threadWidth, height: threadHeight, depth: 1)
    )
    encoder.endEncoding()

    let start = CACurrentMediaTime()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    let elapsedMs = (CACurrentMediaTime() - start) * 1000.0
    if let error = commandBuffer.error { throw error }
    return elapsedMs
  }

  private func rustReference(_ input: SIMD4<Float>, testCase: ParityCase) -> SIMD4<Float> {
    var r = input.x
    var g = input.y
    var b = input.z

    if testCase.brightness != 1 {
      let offset = (testCase.brightness - 1) * 255
      r = quantize255(r * 255 + offset)
      g = quantize255(g * 255 + offset)
      b = quantize255(b * 255 + offset)
    }
    if testCase.contrast != 1 {
      r = quantize255((r * 255 - 128) * testCase.contrast + 128)
      g = quantize255((g * 255 - 128) * testCase.contrast + 128)
      b = quantize255((b * 255 - 128) * testCase.contrast + 128)
    }
    if testCase.saturation != 1 {
      let r255 = r * 255
      let g255 = g * 255
      let b255 = b * 255
      let luminance = 0.2126 * r255 + 0.7152 * g255 + 0.0722 * b255
      r = quantize255(luminance + (r255 - luminance) * testCase.saturation)
      g = quantize255(luminance + (g255 - luminance) * testCase.saturation)
      b = quantize255(luminance + (b255 - luminance) * testCase.saturation)
    }
    return SIMD4<Float>(r, g, b, 1)
  }

  private func rustSharpenReference(
    _ input: [SIMD4<Float>],
    width: Int,
    height: Int,
    strength: Float
  ) -> [SIMD4<Float>] {
    var output = Array(repeating: SIMD4<Float>(0, 0, 0, 1), count: input.count)
    let clampedStrength = max(0, min(2, strength))

    for y in 0..<height {
      for x in 0..<width {
        let center = input[y * width + x]
        let left = input[y * width + max(x - 1, 0)]
        let right = input[y * width + min(x + 1, width - 1)]
        let up = input[max(y - 1, 0) * width + x]
        let down = input[min(y + 1, height - 1) * width + x]

        let r = (center.x * (1 + 4 * clampedStrength)
          - clampedStrength * (left.x + right.x + up.x + down.x)) * 255
        let g = (center.y * (1 + 4 * clampedStrength)
          - clampedStrength * (left.y + right.y + up.y + down.y)) * 255
        let b = (center.z * (1 + 4 * clampedStrength)
          - clampedStrength * (left.z + right.z + up.z + down.z)) * 255

        output[y * width + x] = SIMD4<Float>(
          quantize255(r),
          quantize255(g),
          quantize255(b),
          1
        )
      }
    }
    return output
  }

  private func spatialFixture() -> [SIMD4<Float>] {
    [
      rgba(12, 24, 36), rgba(48, 64, 80), rgba(96, 112, 128), rgba(144, 160, 176), rgba(192, 208, 224),
      rgba(220, 40, 60), rgba(180, 80, 100), rgba(140, 120, 140), rgba(100, 160, 180), rgba(60, 200, 220),
      rgba(10, 240, 80), rgba(50, 200, 120), rgba(90, 160, 160), rgba(130, 120, 200), rgba(170, 80, 240),
      rgba(250, 230, 30), rgba(210, 190, 70), rgba(170, 150, 110), rgba(130, 110, 150), rgba(90, 70, 190),
      rgba(8, 16, 240), rgba(56, 72, 200), rgba(104, 128, 160), rgba(152, 184, 120), rgba(200, 240, 80),
    ]
  }

  private func quantize255(_ value: Float) -> Float {
    round(max(0, min(255, value))) / 255
  }

  private func rgba(_ r: Int, _ g: Int, _ b: Int) -> SIMD4<Float> {
    SIMD4<Float>(Float(r) / 255, Float(g) / 255, Float(b) / 255, 1)
  }

  private func percentile(_ values: [Double], _ percentile: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let index = Int(ceil(percentile * Double(values.count))) - 1
    return values[max(0, min(values.count - 1, index))]
  }

  private static func error(_ message: String) -> NSError {
    NSError(
      domain: "PixelCraftGpuEditorVerification",
      code: 4200,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}
