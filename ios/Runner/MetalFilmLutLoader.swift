import Flutter
import Foundation
import Metal
import MetalKit
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

// MARK: - G2 editor GPU preview lab / integration

final class GpuEditorPreviewPlugin {
  static let channelName = "dev.pixelcraft/gpu_editor_preview_v1"
  static let viewType = "dev.pixelcraft/gpu_editor_preview_v1"

  private let channel: FlutterMethodChannel
  private let registry = MetalEditorRendererRegistry()

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
        let renderer = try registry.renderer(id: id)
        renderer.setAdjustments(
          brightness: number(args["brightness"], fallback: 1),
          contrast: number(args["contrast"], fallback: 1),
          saturation: number(args["saturation"], fallback: 1),
          sharpen: number(args["sharpen"], fallback: 0)
        )
        result(nil)
      } catch {
        result(flutterError("gpu_editor_adjustment_failed", error))
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

  private static let shaderSource = """
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
  private let textureLoader: MTKTextureLoader
  private let lutLoader: MetalFilmLutLoader
  private let stateQueue = DispatchQueue(label: "dev.pixelcraft.gpu.editor.state", qos: .userInitiated)

  private weak var outputView: MTKView?
  private var sourceTexture: MTLTexture?
  private var currentLut: MTLTexture
  private var currentProfileId = ""
  private var brightness: Float = 1
  private var contrast: Float = 1
  private var saturation: Float = 1
  private var sharpen: Float = 0
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
      let fragment = library.makeFunction(name: "pixelcraft_editor_fragment")
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
    stateQueue.sync { sourceTexture = texture }
    requestDraw()
  }

  func setAdjustments(
    brightness: Double,
    contrast: Double,
    saturation: Double,
    sharpen: Double
  ) {
    stateQueue.sync {
      self.brightness = Float(max(0, min(2, brightness)))
      self.contrast = Float(max(0, min(2, contrast)))
      self.saturation = Float(max(0, min(2, saturation)))
      self.sharpen = Float(max(0, min(2, sharpen)))
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
  }

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    requestDraw()
  }

  func draw(in view: MTKView) {
    var source: MTLTexture?
    var lut: MTLTexture?
    var localBrightness: Float = 1
    var localContrast: Float = 1
    var localSaturation: Float = 1
    var localSharpen: Float = 0
    var localFilmStrength: Float = 0
    var localUseLut: Float = 0
    stateQueue.sync {
      source = sourceTexture
      lut = currentLut
      localBrightness = brightness
      localContrast = contrast
      localSaturation = saturation
      localSharpen = sharpen
      localFilmStrength = filmStrength
      localUseLut = useLut
    }
    guard
      let source,
      let lut,
      let drawable = view.currentDrawable,
      let commandBuffer = commandQueue.makeCommandBuffer()
    else { return }

    let outputWidth = max(Float(view.drawableSize.width), 1)
    let outputHeight = max(Float(view.drawableSize.height), 1)
    let sourceAspect = Float(source.width) / Float(max(source.height, 1))
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
    encoder.setFragmentTexture(source, index: 0)
    encoder.setFragmentTexture(lut, index: 1)
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    encoder.endEncoding()
    commandBuffer.present(drawable)
    commandBuffer.commit()
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
