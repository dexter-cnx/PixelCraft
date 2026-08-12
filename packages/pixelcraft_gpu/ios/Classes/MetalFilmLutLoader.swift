import Flutter
import Foundation
import Metal
import MetalKit
import QuartzCore
import UIKit

final class MetalFilmLutLoader {
  static let lutSize = 33
  private static let tilesPerRow = 6
  private static let atlasSize = lutSize * tilesPerRow

  private let device: MTLDevice

  init(device: MTLDevice) {
    self.device = device
  }

  func load(profileId: String) throws -> MTLTexture {
    guard let url = Bundle.main.url(
      forResource: profileId,
      withExtension: "rgba8",
      subdirectory: "gpu_luts"
    ) else {
      throw NSError(
        domain: "PixelCraftGpu",
        code: 1001,
        userInfo: [NSLocalizedDescriptionKey: "Missing Film LUT asset: \(profileId)"]
      )
    }

    let atlas = try Data(contentsOf: url)
    let expected = Self.atlasSize * Self.atlasSize * 4
    guard atlas.count == expected else {
      throw NSError(
        domain: "PixelCraftGpu",
        code: 1002,
        userInfo: [NSLocalizedDescriptionKey: "Unexpected Film LUT byte count for \(profileId): \(atlas.count)"]
      )
    }

    var volume = Data(count: Self.lutSize * Self.lutSize * Self.lutSize * 4)
    atlas.withUnsafeBytes { atlasRaw in
      volume.withUnsafeMutableBytes { volumeRaw in
        guard
          let atlasBytes = atlasRaw.bindMemory(to: UInt8.self).baseAddress,
          let volumeBytes = volumeRaw.bindMemory(to: UInt8.self).baseAddress
        else { return }

        for blue in 0..<Self.lutSize {
          let tileX = blue % Self.tilesPerRow
          let tileY = blue / Self.tilesPerRow
          for green in 0..<Self.lutSize {
            for red in 0..<Self.lutSize {
              let atlasX = tileX * Self.lutSize + red
              let atlasY = tileY * Self.lutSize + green
              let atlasOffset = (atlasY * Self.atlasSize + atlasX) * 4
              let volumeOffset = (red + Self.lutSize * (green + Self.lutSize * blue)) * 4
              volumeBytes[volumeOffset] = atlasBytes[atlasOffset]
              volumeBytes[volumeOffset + 1] = atlasBytes[atlasOffset + 1]
              volumeBytes[volumeOffset + 2] = atlasBytes[atlasOffset + 2]
              volumeBytes[volumeOffset + 3] = 255
            }
          }
        }
      }
    }

    return try makeTexture(bytes: volume)
  }

  func makeIdentity() throws -> MTLTexture {
    var volume = Data(count: Self.lutSize * Self.lutSize * Self.lutSize * 4)
    volume.withUnsafeMutableBytes { raw in
      guard let bytes = raw.bindMemory(to: UInt8.self).baseAddress else { return }
      for blue in 0..<Self.lutSize {
        for green in 0..<Self.lutSize {
          for red in 0..<Self.lutSize {
            let offset = (red + Self.lutSize * (green + Self.lutSize * blue)) * 4
            bytes[offset] = UInt8(round(Double(red) / Double(Self.lutSize - 1) * 255.0))
            bytes[offset + 1] = UInt8(round(Double(green) / Double(Self.lutSize - 1) * 255.0))
            bytes[offset + 2] = UInt8(round(Double(blue) / Double(Self.lutSize - 1) * 255.0))
            bytes[offset + 3] = 255
          }
        }
      }
    }
    return try makeTexture(bytes: volume)
  }

  static func canonicalAssetsAvailable() -> Bool {
    let profileIds = [
      "provia_inspired",
      "velvia_inspired",
      "astia_inspired",
      "e100_inspired",
      "ektar_inspired",
      "chrome64_inspired",
    ]
    return profileIds.allSatisfy {
      Bundle.main.url(forResource: $0, withExtension: "rgba8", subdirectory: "gpu_luts") != nil
    }
  }

  private func makeTexture(bytes: Data) throws -> MTLTexture {
    let descriptor = MTLTextureDescriptor()
    descriptor.textureType = .type3D
    descriptor.pixelFormat = .rgba8Unorm
    descriptor.width = Self.lutSize
    descriptor.height = Self.lutSize
    descriptor.depth = Self.lutSize
    descriptor.mipmapLevelCount = 1
    descriptor.usage = [.shaderRead]
    descriptor.storageMode = .shared

    guard let texture = device.makeTexture(descriptor: descriptor) else {
      throw NSError(
        domain: "PixelCraftGpu",
        code: 1003,
        userInfo: [NSLocalizedDescriptionKey: "Unable to allocate 33^3 Metal LUT texture"]
      )
    }

    bytes.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { return }
      texture.replace(
        region: MTLRegionMake3D(0, 0, 0, Self.lutSize, Self.lutSize, Self.lutSize),
        mipmapLevel: 0,
        slice: 0,
        withBytes: base,
        bytesPerRow: Self.lutSize * 4,
        bytesPerImage: Self.lutSize * Self.lutSize * 4
      )
    }
    return texture
  }
}

// MARK: - G2 editor GPU preview / integration

final class GpuEditorPreviewPlugin {
  static let channelName = "dev.pixelcraft/gpu_editor_preview_v1"
  static let viewType = "dev.pixelcraft/gpu_editor_preview_v1"

  private let channel: FlutterMethodChannel
  private let registry = MetalEditorRendererRegistry()
  private let benchmarkQueue = DispatchQueue(
    label: "dev.pixelcraft.gpu.editor.benchmark",
    qos: .userInitiated
  )

  init(registrar: FlutterPluginRegistrar) {
    channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.register(
      MetalEditorPreviewViewFactory(registry: registry),
      withId: Self.viewType
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "createRenderer":
      do {
        result(["rendererId": try registry.create()])
      } catch {
        result(flutterError("gpu_editor_init_failed", error))
      }
    case "setSourcePath":
      guard let id = rendererId(args, result: result) else { return }
      guard let path = args["path"] as? String, !path.isEmpty else {
        result(FlutterError(code: "gpu_editor_source_invalid", message: "path is required", details: nil))
        return
      }
      do {
        try registry.renderer(id: id).setSource(path: path)
        result(nil)
      } catch {
        result(flutterError("gpu_editor_source_failed", error))
      }
    case "setAdjustments":
      guard let id = rendererId(args, result: result) else { return }
      do {
        try registry.renderer(id: id).setAdjustments(
          brightness: number(args["brightness"], fallback: 1),
          contrast: number(args["contrast"], fallback: 1),
          saturation: number(args["saturation"], fallback: 1),
          sharpen: number(args["sharpen"], fallback: 0),
          gaussianBlur: number(args["gaussianBlur"], fallback: 0)
        )
        result(nil)
      } catch {
        result(flutterError("gpu_editor_adjustment_failed", error))
      }
    case "setCreative":
      guard let id = rendererId(args, result: result) else { return }
      do {
        try registry.renderer(id: id).setCreative(
          filterId: args["filterId"] as? String ?? "",
          intensity: number(args["intensity"], fallback: 0)
        )
        result(nil)
      } catch {
        result(flutterError("gpu_editor_creative_failed", error))
      }
    case "setFilm":
      guard let id = rendererId(args, result: result) else { return }
      do {
        let renderer = try registry.renderer(id: id)
        let profileId = args["profileId"] as? String ?? ""
        let strength = number(args["strength"], fallback: 0)
        try renderer.setFilm(profileId: profileId, strength: strength)
        result(nil)
      } catch {
        result(flutterError("gpu_editor_film_failed", error))
      }
    case "runCreativeParity":
      benchmarkQueue.async { [weak self] in
        guard let self else { return }
        do {
          let payload = try MetalCreativeFilterParityHarness().run()
          DispatchQueue.main.async { result(payload) }
        } catch {
          DispatchQueue.main.async {
            result(self.flutterError("gpu_editor_creative_parity_failed", error))
          }
        }
      }
    case "runGaussianBlurLatencyBenchmark":
      benchmarkQueue.async { [weak self] in
        guard let self else { return }
        do {
          let payload = try MetalGaussianBlurBenchmark().run()
          DispatchQueue.main.async { result(payload) }
        } catch {
          DispatchQueue.main.async {
            result(self.flutterError("gpu_editor_blur_latency_failed", error))
          }
        }
      }
    case "destroyRenderer":
      guard let id = rendererId(args, result: result) else { return }
      registry.destroy(id: id)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func rendererId(_ args: [String: Any], result: FlutterResult) -> String? {
    guard let id = args["rendererId"] as? String, !id.isEmpty else {
      result(FlutterError(code: "gpu_editor_renderer_invalid", message: "rendererId is required", details: nil))
      return nil
    }
    return id
  }

  private func number(_ value: Any?, fallback: Double) -> Double {
    (value as? NSNumber)?.doubleValue ?? fallback
  }

  private func flutterError(_ code: String, _ error: Error) -> FlutterError {
    FlutterError(code: code, message: error.localizedDescription, details: nil)
  }
}

final class MetalEditorRendererRegistry {
  private var renderers: [String: MetalEditorPreviewRenderer] = [:]

  func create() throws -> String {
    let id = UUID().uuidString
    renderers[id] = try MetalEditorPreviewRenderer(editorPreview: ())
    return id
  }

  func renderer(id: String) throws -> MetalEditorPreviewRenderer {
    guard let renderer = renderers[id] else {
      throw NSError(
        domain: "PixelCraftGpuEditor",
        code: 4101,
        userInfo: [NSLocalizedDescriptionKey: "Unknown editor GPU renderer: \(id)"]
      )
    }
    return renderer
  }

  func destroy(id: String) {
    renderers.removeValue(forKey: id)?.releaseRenderer()
  }

  func attach(id: String, view: MTKView) throws {
    try renderer(id: id).attach(view: view)
  }

  func detach(id: String, view: MTKView) {
    try? renderer(id: id).detach(view: view)
  }
}

final class MetalEditorPreviewViewFactory: NSObject, FlutterPlatformViewFactory {
  private let registry: MetalEditorRendererRegistry

  init(registry: MetalEditorRendererRegistry) {
    self.registry = registry
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let rendererId = (args as? [String: Any])?["rendererId"] as? String ?? ""
    return MetalEditorPreviewPlatformView(
      frame: frame,
      rendererId: rendererId,
      registry: registry
    )
  }
}

final class MetalEditorPreviewPlatformView: NSObject, FlutterPlatformView {
  private let rendererId: String
  private let registry: MetalEditorRendererRegistry
  private let metalView: MTKView

  init(frame: CGRect, rendererId: String, registry: MetalEditorRendererRegistry) {
    self.rendererId = rendererId
    self.registry = registry
    self.metalView = MTKView(frame: frame)
    super.init()
    try? registry.attach(id: rendererId, view: metalView)
  }

  func view() -> UIView { metalView }

  deinit {
    registry.detach(id: rendererId, view: metalView)
  }
}

final class MetalEditorPreviewRenderer: NSObject, MTKViewDelegate {
  private struct Uniforms {
    var contentScale: SIMD2<Float>
    var brightness: Float
    var contrast: Float
    var saturation: Float
    var sharpen: Float
    var filmStrength: Float
    var useLut: Float
  }

  private struct BlurUniforms {
    var width: UInt32
    var height: UInt32
    var sigma: Float
    var horizontal: UInt32
  }

  fileprivate struct CreativeUniforms {
    var width: UInt32
    var height: UInt32
    var mode: UInt32
    var intensity: Float
  }

  fileprivate static let shaderSource = """
  #include <metal_stdlib>
  using namespace metal;

  struct VertexOut {
    float4 position [[position]];
    float2 uv;
  };

  struct Uniforms {
    float2 contentScale;
    float brightness;
    float contrast;
    float saturation;
    float sharpen;
    float filmStrength;
    float useLut;
  };

  struct BlurUniforms {
    uint width;
    uint height;
    float sigma;
    uint horizontal;
  };

  struct CreativeUniforms {
    uint width;
    uint height;
    uint mode;
    float intensity;
  };

  inline float gaussian_weight(float x, float sigma) {
    const float twoPi = 6.28318530717958647692;
    float safeSigma = max(sigma, 0.01);
    return exp(-(x * x) / (2.0 * safeSigma * safeSigma)) /
      (sqrt(twoPi) * safeSigma);
  }

  kernel void pixelcraft_editor_gaussian_blur(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant BlurUniforms &uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height) return;

    float sigma = max(uniforms.sigma, 0.01);
    int radius = int(ceil(2.0 * sigma));
    float4 sum = float4(0.0);
    for (int offset = -radius; offset <= radius; ++offset) {
      int px = int(gid.x);
      int py = int(gid.y);
      if (uniforms.horizontal != 0) {
        px = clamp(px + offset, 0, int(uniforms.width) - 1);
      } else {
        py = clamp(py + offset, 0, int(uniforms.height) - 1);
      }
      float weight = gaussian_weight(float(offset), sigma);
      sum += input.read(uint2(uint(px), uint(py))) * weight;
    }
    output.write(clamp(sum, 0.0, 1.0), gid);
  }

  kernel void pixelcraft_editor_creative(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant CreativeUniforms &uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height) return;

    float4 source = input.read(gid);
    uint3 source8 = uint3(clamp(floor(source.rgb * 255.0 + 0.5), 0.0, 255.0));
    uint3 effected8 = source8;
    if (uniforms.mode == 1) {
      uint average = (source8.r + source8.g + source8.b) / 3;
      effected8 = uint3(average);
    } else if (uniforms.mode == 2) {
      effected8 = uint3(255) - source8;
    }

    float strength = clamp(uniforms.intensity, 0.0, 1.0);
    float3 blended8 = floor(
      float3(source8) + (float3(effected8) - float3(source8)) * strength + 0.5
    );
    output.write(
      float4(clamp(blended8, 0.0, 255.0) / 255.0, source.a),
      gid
    );
  }

  vertex VertexOut pixelcraft_editor_vertex(
    uint vertexId [[vertex_id]],
    constant Uniforms &uniforms [[buffer(0)]]) {
    const float2 positions[4] = {
      float2(-1.0, -1.0), float2(1.0, -1.0),
      float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 uvs[4] = {
      float2(0.0, 1.0), float2(1.0, 1.0),
      float2(0.0, 0.0), float2(1.0, 0.0)
    };
    VertexOut out;
    out.position = float4(positions[vertexId] * uniforms.contentScale, 0.0, 1.0);
    out.uv = uvs[vertexId];
    return out;
  }

  fragment float4 pixelcraft_editor_fragment(
    VertexOut in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    texture3d<float> lut [[texture(1)]],
    constant Uniforms &uniforms [[buffer(0)]]) {
    constexpr sampler sourceSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    constexpr sampler lutSampler(coord::normalized, address::clamp_to_edge, filter::linear);

    float3 center = sourceTexture.sample(sourceSampler, in.uv).rgb;
    float3 color = center;
    float sharpenStrength = clamp(uniforms.sharpen, 0.0, 2.0);
    if (sharpenStrength > 0.0001) {
      float2 texel = 1.0 / float2(sourceTexture.get_width(), sourceTexture.get_height());
      float3 left = sourceTexture.sample(sourceSampler, in.uv - float2(texel.x, 0.0)).rgb;
      float3 right = sourceTexture.sample(sourceSampler, in.uv + float2(texel.x, 0.0)).rgb;
      float3 up = sourceTexture.sample(sourceSampler, in.uv - float2(0.0, texel.y)).rgb;
      float3 down = sourceTexture.sample(sourceSampler, in.uv + float2(0.0, texel.y)).rgb;
      color = clamp(
        center * (1.0 + 4.0 * sharpenStrength) -
          sharpenStrength * (left + right + up + down),
        0.0,
        1.0
      );
    }

    color = clamp(color + (uniforms.brightness - 1.0), 0.0, 1.0);
    const float midpoint = 128.0 / 255.0;
    color = clamp((color - midpoint) * uniforms.contrast + midpoint, 0.0, 1.0);
    const float luminance = dot(color, float3(0.2126, 0.7152, 0.0722));
    color = clamp(luminance + (color - luminance) * uniforms.saturation, 0.0, 1.0);

    const float lutSize = 33.0;
    float3 grid = clamp(color, 0.0, 1.0) * (lutSize - 1.0);
    float3 lutUv = (grid + 0.5) / lutSize;
    float3 film = lut.sample(lutSampler, lutUv).rgb;
    float amount = clamp(uniforms.useLut * uniforms.filmStrength, 0.0, 1.0);
    return float4(mix(color, film, amount), 1.0);
  }
  """

  private let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private let pipeline: MTLRenderPipelineState
  private let blurPipeline: MTLComputePipelineState
  private let creativePipeline: MTLComputePipelineState
  private let textureLoader: MTKTextureLoader
  private let lutLoader: MetalFilmLutLoader
  private let stateQueue = DispatchQueue(label: "dev.pixelcraft.gpu.editor.state", qos: .userInitiated)

  private weak var outputView: MTKView?
  private var sourceTexture: MTLTexture?
  private var blurHorizontalTexture: MTLTexture?
  private var blurVerticalTexture: MTLTexture?
  private var creativeTexture: MTLTexture?
  private var currentLut: MTLTexture
  private var currentProfileId = ""
  private var brightness: Float = 1
  private var contrast: Float = 1
  private var saturation: Float = 1
  private var sharpen: Float = 0
  private var gaussianBlur: Float = 0
  private var creativeMode: UInt32 = 0
  private var creativeIntensity: Float = 0
  private var filmStrength: Float = 0
  private var useLut: Float = 0

  init(editorPreview: Void) throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
      throw Self.error("Metal device is unavailable")
    }
    guard let commandQueue = device.makeCommandQueue() else {
      throw Self.error("Unable to create editor Metal command queue")
    }
    let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
    guard
      let vertex = library.makeFunction(name: "pixelcraft_editor_vertex"),
      let fragment = library.makeFunction(name: "pixelcraft_editor_fragment"),
      let blur = library.makeFunction(name: "pixelcraft_editor_gaussian_blur"),
      let creative = library.makeFunction(name: "pixelcraft_editor_creative")
    else {
      throw Self.error("Editor Metal shader functions are unavailable")
    }
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = vertex
    descriptor.fragmentFunction = fragment
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

    self.device = device
    self.commandQueue = commandQueue
    self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    self.blurPipeline = try device.makeComputePipelineState(function: blur)
    self.creativePipeline = try device.makeComputePipelineState(function: creative)
    self.textureLoader = MTKTextureLoader(device: device)
    self.lutLoader = MetalFilmLutLoader(device: device)
    self.currentLut = try self.lutLoader.makeIdentity()
    super.init()
  }

  func attach(view: MTKView) {
    outputView = view
    view.device = device
    view.colorPixelFormat = .bgra8Unorm
    view.framebufferOnly = true
    view.enableSetNeedsDisplay = true
    view.isPaused = true
    view.delegate = self
    requestDraw()
  }

  func detach(view: MTKView) {
    if outputView === view {
      view.delegate = nil
      outputView = nil
    }
  }

  func setSource(path: String) throws {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: path) else {
      throw Self.error("Editor source file does not exist: \(path)")
    }
    let texture = try textureLoader.newTexture(
      URL: url,
      options: [
        .SRGB: false,
        .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
      ]
    )
    stateQueue.sync {
      sourceTexture = texture
      blurHorizontalTexture = nil
      blurVerticalTexture = nil
      creativeTexture = nil
    }
    requestDraw()
  }

  func setAdjustments(
    brightness: Double,
    contrast: Double,
    saturation: Double,
    sharpen: Double,
    gaussianBlur: Double
  ) throws {
    let blur = Float(max(0, min(2, gaussianBlur)))
    if blur > 0.0001 {
      try ensureBlurTexturesForCurrentSource()
    }
    stateQueue.sync {
      self.brightness = Float(max(0, min(2, brightness)))
      self.contrast = Float(max(0, min(2, contrast)))
      self.saturation = Float(max(0, min(2, saturation)))
      self.sharpen = Float(max(0, min(2, sharpen)))
      self.gaussianBlur = blur
    }
    requestDraw()
  }

  func setCreative(filterId: String, intensity: Double) throws {
    let clamped = Float(max(0, min(1, intensity)))
    let mode: UInt32
    switch filterId {
    case "", "none": mode = 0
    case "grayscale": mode = 1
    case "invert": mode = 2
    default:
      throw Self.error("Unsupported Metal creative filter: \(filterId)")
    }
    if mode != 0 && clamped > 0.0001 {
      try ensureCreativeTextureForCurrentSource()
    }
    stateQueue.sync {
      creativeMode = mode
      creativeIntensity = mode == 0 ? 0 : clamped
    }
    requestDraw()
  }

  func setFilm(profileId: String, strength: Double) throws {
    let clampedStrength = Float(max(0, min(1, strength)))
    if profileId.isEmpty || clampedStrength <= 0 {
      stateQueue.sync {
        filmStrength = 0
        useLut = 0
      }
      requestDraw()
      return
    }

    if profileId == currentProfileId {
      stateQueue.sync {
        filmStrength = clampedStrength
        useLut = 1
      }
      requestDraw()
      return
    }

    let lut = try lutLoader.load(profileId: profileId)
    stateQueue.sync {
      currentLut = lut
      currentProfileId = profileId
      filmStrength = clampedStrength
      useLut = 1
    }
    requestDraw()
  }

  func releaseRenderer() {
    if let view = outputView {
      view.delegate = nil
      view.isPaused = true
    }
    outputView = nil
    sourceTexture = nil
    blurHorizontalTexture = nil
    blurVerticalTexture = nil
    creativeTexture = nil
  }

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    requestDraw()
  }

  func draw(in view: MTKView) {
    var source: MTLTexture?
    var blurHorizontal: MTLTexture?
    var blurVertical: MTLTexture?
    var creativeOutput: MTLTexture?
    var lut: MTLTexture?
    var localBrightness: Float = 1
    var localContrast: Float = 1
    var localSaturation: Float = 1
    var localSharpen: Float = 0
    var localGaussianBlur: Float = 0
    var localCreativeMode: UInt32 = 0
    var localCreativeIntensity: Float = 0
    var localFilmStrength: Float = 0
    var localUseLut: Float = 0
    stateQueue.sync {
      source = sourceTexture
      blurHorizontal = blurHorizontalTexture
      blurVertical = blurVerticalTexture
      creativeOutput = creativeTexture
      lut = currentLut
      localBrightness = brightness
      localContrast = contrast
      localSaturation = saturation
      localSharpen = sharpen
      localGaussianBlur = gaussianBlur
      localCreativeMode = creativeMode
      localCreativeIntensity = creativeIntensity
      localFilmStrength = filmStrength
      localUseLut = useLut
    }
    guard
      let source,
      let lut,
      let drawable = view.currentDrawable,
      let commandBuffer = commandQueue.makeCommandBuffer()
    else { return }

    var renderSource = source
    if localCreativeMode != 0,
       localCreativeIntensity > 0.0001,
       let creativeOutput {
      do {
        try encodeCreative(
          commandBuffer: commandBuffer,
          input: source,
          output: creativeOutput,
          mode: localCreativeMode,
          intensity: localCreativeIntensity
        )
        renderSource = creativeOutput
      } catch {
        return
      }
    }

    if localGaussianBlur > 0.0001,
       let blurHorizontal,
       let blurVertical {
      let sigma = max(localGaussianBlur * 2.5, 0.01)
      do {
        try encodeBlur(
          commandBuffer: commandBuffer,
          input: renderSource,
          output: blurHorizontal,
          sigma: sigma,
          horizontal: true
        )
        try encodeBlur(
          commandBuffer: commandBuffer,
          input: blurHorizontal,
          output: blurVertical,
          sigma: sigma,
          horizontal: false
        )
        renderSource = blurVertical
      } catch {
        return
      }
    }

    let outputWidth = max(Float(view.drawableSize.width), 1)
    let outputHeight = max(Float(view.drawableSize.height), 1)
    let sourceAspect = Float(renderSource.width) / Float(max(renderSource.height, 1))
    let outputAspect = outputWidth / outputHeight
    let contentScale: SIMD2<Float>
    if sourceAspect > outputAspect {
      contentScale = SIMD2<Float>(1, outputAspect / sourceAspect)
    } else {
      contentScale = SIMD2<Float>(sourceAspect / outputAspect, 1)
    }

    var uniforms = Uniforms(
      contentScale: contentScale,
      brightness: localBrightness,
      contrast: localContrast,
      saturation: localSaturation,
      sharpen: localSharpen,
      filmStrength: localFilmStrength,
      useLut: localUseLut
    )

    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = drawable.texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

    guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
    encoder.setRenderPipelineState(pipeline)
    encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
    encoder.setFragmentTexture(renderSource, index: 0)
    encoder.setFragmentTexture(lut, index: 1)
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    encoder.endEncoding()
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }

  private func ensureBlurTexturesForCurrentSource() throws {
    var source: MTLTexture?
    var horizontal: MTLTexture?
    var vertical: MTLTexture?
    stateQueue.sync {
      source = sourceTexture
      horizontal = blurHorizontalTexture
      vertical = blurVerticalTexture
    }
    guard let source else { return }
    if horizontal?.width == source.width,
       horizontal?.height == source.height,
       vertical?.width == source.width,
       vertical?.height == source.height {
      return
    }

    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba8Unorm,
      width: source.width,
      height: source.height,
      mipmapped: false
    )
    descriptor.usage = [.shaderRead, .shaderWrite]
    descriptor.storageMode = .private
    guard
      let newHorizontal = device.makeTexture(descriptor: descriptor),
      let newVertical = device.makeTexture(descriptor: descriptor)
    else {
      throw Self.error("Unable to allocate Gaussian blur working textures")
    }
    stateQueue.sync {
      blurHorizontalTexture = newHorizontal
      blurVerticalTexture = newVertical
    }
  }

  private func ensureCreativeTextureForCurrentSource() throws {
    var source: MTLTexture?
    var existing: MTLTexture?
    stateQueue.sync {
      source = sourceTexture
      existing = creativeTexture
    }
    guard let source else { return }
    if existing?.width == source.width, existing?.height == source.height {
      return
    }

    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba8Unorm,
      width: source.width,
      height: source.height,
      mipmapped: false
    )
    descriptor.usage = [.shaderRead, .shaderWrite]
    descriptor.storageMode = .private
    guard let texture = device.makeTexture(descriptor: descriptor) else {
      throw Self.error("Unable to allocate creative filter working texture")
    }
    stateQueue.sync { creativeTexture = texture }
  }

  private func encodeCreative(
    commandBuffer: MTLCommandBuffer,
    input: MTLTexture,
    output: MTLTexture,
    mode: UInt32,
    intensity: Float
  ) throws {
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
      throw Self.error("Unable to create creative filter compute encoder")
    }
    var uniforms = CreativeUniforms(
      width: UInt32(output.width),
      height: UInt32(output.height),
      mode: mode,
      intensity: intensity
    )
    encoder.setComputePipelineState(creativePipeline)
    encoder.setTexture(input, index: 0)
    encoder.setTexture(output, index: 1)
    encoder.setBytes(&uniforms, length: MemoryLayout<CreativeUniforms>.stride, index: 0)
    let threadWidth = creativePipeline.threadExecutionWidth
    let threadHeight = max(1, creativePipeline.maxTotalThreadsPerThreadgroup / threadWidth)
    encoder.dispatchThreads(
      MTLSize(width: output.width, height: output.height, depth: 1),
      threadsPerThreadgroup: MTLSize(width: threadWidth, height: threadHeight, depth: 1)
    )
    encoder.endEncoding()
  }

  private func encodeBlur(
    commandBuffer: MTLCommandBuffer,
    input: MTLTexture,
    output: MTLTexture,
    sigma: Float,
    horizontal: Bool
  ) throws {
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
      throw Self.error("Unable to create Gaussian blur compute encoder")
    }
    var uniforms = BlurUniforms(
      width: UInt32(output.width),
      height: UInt32(output.height),
      sigma: sigma,
      horizontal: horizontal ? 1 : 0
    )
    encoder.setComputePipelineState(blurPipeline)
    encoder.setTexture(input, index: 0)
    encoder.setTexture(output, index: 1)
    encoder.setBytes(&uniforms, length: MemoryLayout<BlurUniforms>.stride, index: 0)
    let threadWidth = blurPipeline.threadExecutionWidth
    let threadHeight = max(1, blurPipeline.maxTotalThreadsPerThreadgroup / threadWidth)
    encoder.dispatchThreads(
      MTLSize(width: output.width, height: output.height, depth: 1),
      threadsPerThreadgroup: MTLSize(width: threadWidth, height: threadHeight, depth: 1)
    )
    encoder.endEncoding()
  }

  private func requestDraw() {
    DispatchQueue.main.async { [weak self] in
      self?.outputView?.setNeedsDisplay()
    }
  }

  private static func error(_ message: String) -> NSError {
    NSError(
      domain: "PixelCraftGpuEditor",
      code: 4100,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}

private final class MetalCreativeFilterParityHarness {
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let pipeline: MTLComputePipelineState

  init() throws {
    guard let device = MTLCreateSystemDefaultDevice(),
          let queue = device.makeCommandQueue()
    else { throw Self.error("Metal device/queue unavailable") }
    let library = try device.makeLibrary(source: MetalEditorPreviewRenderer.shaderSource, options: nil)
    guard let function = library.makeFunction(name: "pixelcraft_editor_creative") else {
      throw Self.error("Creative filter parity kernel unavailable")
    }
    self.device = device
    self.queue = queue
    self.pipeline = try device.makeComputePipelineState(function: function)
  }

  func run() throws -> [String: Any] {
    let pixels: [[UInt8]] = [
      [0, 0, 0, 255], [255, 255, 255, 255], [255, 0, 0, 255], [0, 255, 0, 255],
      [0, 0, 255, 255], [64, 128, 192, 255], [192, 128, 64, 255], [16, 48, 240, 255],
      [240, 48, 16, 255], [32, 200, 96, 255], [127, 128, 129, 255], [8, 240, 128, 255],
      [220, 180, 140, 255], [40, 80, 120, 255], [12, 34, 56, 255], [201, 77, 155, 255],
    ]
    let sourceBytes = pixels.flatMap { $0 }
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba8Unorm,
      width: pixels.count,
      height: 1,
      mipmapped: false
    )
    descriptor.usage = [.shaderRead, .shaderWrite]
    descriptor.storageMode = .shared
    guard
      let source = device.makeTexture(descriptor: descriptor),
      let output = device.makeTexture(descriptor: descriptor)
    else { throw Self.error("Unable to allocate creative parity textures") }

    sourceBytes.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { return }
      source.replace(
        region: MTLRegionMake2D(0, 0, pixels.count, 1),
        mipmapLevel: 0,
        withBytes: base,
        bytesPerRow: pixels.count * 4
      )
    }

    let cases: [(String, UInt32, Float)] = [
      ("grayscale_0.25", 1, 0.25),
      ("grayscale_0.50", 1, 0.50),
      ("grayscale_1.00", 1, 1.00),
      ("invert_0.25", 2, 0.25),
      ("invert_0.50", 2, 0.50),
      ("invert_1.00", 2, 1.00),
    ]
    let tolerance = 1.0 / 255.0
    var results: [[String: Any]] = []
    var overallMax = 0.0
    var overallPassed = true

    for test in cases {
      try submit(
        source: source,
        output: output,
        mode: test.1,
        intensity: test.2
      )
      var actual = [UInt8](repeating: 0, count: sourceBytes.count)
      actual.withUnsafeMutableBytes { raw in
        guard let base = raw.baseAddress else { return }
        output.getBytes(
          base,
          bytesPerRow: pixels.count * 4,
          from: MTLRegionMake2D(0, 0, pixels.count, 1),
          mipmapLevel: 0
        )
      }

      var maxError = 0.0
      for index in pixels.indices {
        let expected = reference(
          pixel: pixels[index],
          mode: test.1,
          intensity: test.2
        )
        for channel in 0..<3 {
          let offset = index * 4 + channel
          maxError = max(
            maxError,
            abs(Double(actual[offset]) - Double(expected[channel])) / 255.0
          )
        }
      }
      let passed = maxError <= tolerance
      overallMax = max(overallMax, maxError)
      overallPassed = overallPassed && passed
      results.append([
        "name": test.0,
        "samples": pixels.count,
        "maxChannelError": maxError,
        "passed": passed,
      ])
    }

    return [
      "backend": "iosMetal",
      "reference": "photon-rs 0.3.3 grayscale/invert + PixelCraft u8 intensity blend",
      "tolerance": tolerance,
      "overallMaxChannelError": overallMax,
      "passed": overallPassed,
      "cases": results,
      "filmParity": "",
    ]
  }

  private func submit(
    source: MTLTexture,
    output: MTLTexture,
    mode: UInt32,
    intensity: Float
  ) throws {
    guard let commandBuffer = queue.makeCommandBuffer(),
          let encoder = commandBuffer.makeComputeCommandEncoder()
    else { throw Self.error("Unable to create creative parity command") }

    var uniforms = MetalEditorPreviewRenderer.CreativeUniforms(
      width: UInt32(output.width),
      height: UInt32(output.height),
      mode: mode,
      intensity: intensity
    )
    encoder.setComputePipelineState(pipeline)
    encoder.setTexture(source, index: 0)
    encoder.setTexture(output, index: 1)
    encoder.setBytes(
      &uniforms,
      length: MemoryLayout<MetalEditorPreviewRenderer.CreativeUniforms>.stride,
      index: 0
    )
    let width = min(pipeline.maxTotalThreadsPerThreadgroup, output.width)
    encoder.dispatchThreads(
      MTLSize(width: output.width, height: 1, depth: 1),
      threadsPerThreadgroup: MTLSize(width: max(width, 1), height: 1, depth: 1)
    )
    encoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    if let error = commandBuffer.error { throw error }
  }

  private func reference(
    pixel: [UInt8],
    mode: UInt32,
    intensity: Float
  ) -> [UInt8] {
    let source = [Int(pixel[0]), Int(pixel[1]), Int(pixel[2])]
    let effected: [Int]
    if mode == 1 {
      let average = (source[0] + source[1] + source[2]) / 3
      effected = [average, average, average]
    } else {
      effected = source.map { 255 - $0 }
    }
    return (0..<3).map { channel in
      let value = Float(source[channel]) +
        (Float(effected[channel]) - Float(source[channel])) * intensity
      return UInt8(max(0, min(255, Int(value.rounded()))))
    }
  }

  private static func error(_ message: String) -> NSError {
    NSError(
      domain: "PixelCraftGpuEditorCreativeParity",
      code: 4400,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}

private final class MetalGaussianBlurBenchmark {
  private struct BlurUniforms {
    var width: UInt32
    var height: UInt32
    var sigma: Float
    var horizontal: UInt32
  }

  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let pipeline: MTLComputePipelineState

  init() throws {
    guard let device = MTLCreateSystemDefaultDevice(),
          let queue = device.makeCommandQueue()
    else { throw Self.error("Metal device/queue unavailable") }
    let library = try device.makeLibrary(source: MetalEditorPreviewRenderer.shaderSource, options: nil)
    guard let function = library.makeFunction(name: "pixelcraft_editor_gaussian_blur") else {
      throw Self.error("Gaussian blur benchmark kernel unavailable")
    }
    self.device = device
    self.queue = queue
    self.pipeline = try device.makeComputePipelineState(function: function)
  }

  func run() throws -> [String: Any] {
    let width = 1024
    let height = 1024
    let iterations = 60
    let warmup = 8
    let sigma: Float = 5.0

    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba8Unorm,
      width: width,
      height: height,
      mipmapped: false
    )
    descriptor.usage = [.shaderRead, .shaderWrite]
    descriptor.storageMode = .private
    guard
      let source = device.makeTexture(descriptor: descriptor),
      let horizontal = device.makeTexture(descriptor: descriptor),
      let vertical = device.makeTexture(descriptor: descriptor)
    else { throw Self.error("Unable to allocate blur benchmark textures") }

    for _ in 0..<warmup {
      _ = try submit(source: source, horizontal: horizontal, vertical: vertical, sigma: sigma)
    }
    var samples: [Double] = []
    samples.reserveCapacity(iterations)
    for _ in 0..<iterations {
      samples.append(try submit(source: source, horizontal: horizontal, vertical: vertical, sigma: sigma))
    }
    samples.sort()
    let average = samples.reduce(0, +) / Double(samples.count)
    let target = 16.67
    let p50 = percentile(samples, 0.50)
    let p95 = percentile(samples, 0.95)
    let p99 = percentile(samples, 0.99)
    return [
      "backend": "iosMetal",
      "device": device.name,
      "width": width,
      "height": height,
      "iterations": iterations,
      "workload": "gaussian_blur_2.00_sigma5_two_pass",
      "averageMs": average,
      "p50Ms": p50,
      "p95Ms": p95,
      "p99Ms": p99,
      "maxMs": samples.last ?? 0,
      "targetMs": target,
      "passed": p95 <= target,
    ]
  }

  private func submit(
    source: MTLTexture,
    horizontal: MTLTexture,
    vertical: MTLTexture,
    sigma: Float
  ) throws -> Double {
    guard let commandBuffer = queue.makeCommandBuffer() else {
      throw Self.error("Unable to create blur benchmark command buffer")
    }
    try encode(commandBuffer, input: source, output: horizontal, sigma: sigma, horizontal: true)
    try encode(commandBuffer, input: horizontal, output: vertical, sigma: sigma, horizontal: false)
    let start = CACurrentMediaTime()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    if let error = commandBuffer.error { throw error }
    return (CACurrentMediaTime() - start) * 1000.0
  }

  private func encode(
    _ commandBuffer: MTLCommandBuffer,
    input: MTLTexture,
    output: MTLTexture,
    sigma: Float,
    horizontal: Bool
  ) throws {
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
      throw Self.error("Unable to create blur benchmark encoder")
    }
    var uniforms = BlurUniforms(
      width: UInt32(output.width),
      height: UInt32(output.height),
      sigma: sigma,
      horizontal: horizontal ? 1 : 0
    )
    encoder.setComputePipelineState(pipeline)
    encoder.setTexture(input, index: 0)
    encoder.setTexture(output, index: 1)
    encoder.setBytes(&uniforms, length: MemoryLayout<BlurUniforms>.stride, index: 0)
    let threadWidth = pipeline.threadExecutionWidth
    let threadHeight = max(1, pipeline.maxTotalThreadsPerThreadgroup / threadWidth)
    encoder.dispatchThreads(
      MTLSize(width: output.width, height: output.height, depth: 1),
      threadsPerThreadgroup: MTLSize(width: threadWidth, height: threadHeight, depth: 1)
    )
    encoder.endEncoding()
  }

  private func percentile(_ values: [Double], _ percentile: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let index = Int(ceil(percentile * Double(values.count))) - 1
    return values[max(0, min(values.count - 1, index))]
  }

  private static func error(_ message: String) -> NSError {
    NSError(
      domain: "PixelCraftGpuEditorBlurBenchmark",
      code: 4300,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}
