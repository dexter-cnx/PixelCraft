import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import Metal
import MetalKit
import QuartzCore
import UIKit

final class MetalCameraPreviewRenderer: NSObject {
  typealias FailureHandler = (String) -> Void
  typealias CaptureHandler = (Result<String, Error>) -> Void

  private struct PreviewUniforms {
    var cropScale: SIMD2<Float>
    var mirrorX: Float
    var enabled: Float
    var brightness: Float
    var contrast: Float
    var saturation: Float
    var filmStrength: Float
    var useFilm: Float
    var creativeStrength: Float
    var creativeMode: Float
    var padding: Float = 0
  }

  private static let creativeNone: Float = 0
  private static let creativeGrayscale: Float = 1
  private static let creativeInvert: Float = 2
  private static let creativeLut: Float = 3

  private static let shaderSource = """
  #include <metal_stdlib>
  using namespace metal;

  struct VertexOut {
    float4 position [[position]];
    float2 uv;
  };

  struct PreviewUniforms {
    float2 cropScale;
    float mirrorX;
    float enabled;
    float brightness;
    float contrast;
    float saturation;
    float filmStrength;
    float useFilm;
    float creativeStrength;
    float creativeMode;
    float padding;
  };

  vertex VertexOut pixelcraft_vertex(uint vertexId [[vertex_id]]) {
    const float2 positions[4] = {
      float2(-1.0, -1.0),
      float2( 1.0, -1.0),
      float2(-1.0,  1.0),
      float2( 1.0,  1.0)
    };
    const float2 uvs[4] = {
      float2(0.0, 1.0),
      float2(1.0, 1.0),
      float2(0.0, 0.0),
      float2(1.0, 0.0)
    };
    VertexOut out;
    out.position = float4(positions[vertexId], 0.0, 1.0);
    out.uv = uvs[vertexId];
    return out;
  }

  inline float3 sample_lut(texture3d<float> lut, sampler lutSampler, float3 color) {
    const float lutSize = 33.0;
    float3 grid = clamp(color, 0.0, 1.0) * (lutSize - 1.0);
    float3 lutUv = (grid + 0.5) / lutSize;
    return lut.sample(lutSampler, lutUv).rgb;
  }

  inline float3 apply_exact_creative(float3 color, uint mode, float intensity) {
    uint3 source8 = uint3(clamp(floor(color * 255.0 + 0.5), 0.0, 255.0));
    uint3 effected8 = source8;
    if (mode == 1) {
      uint average = (source8.r + source8.g + source8.b) / 3;
      effected8 = uint3(average);
    } else if (mode == 2) {
      effected8 = uint3(255) - source8;
    }
    float strength = clamp(intensity, 0.0, 1.0);
    float3 blended8 = floor(
      float3(source8) + (float3(effected8) - float3(source8)) * strength + 0.5
    );
    return clamp(blended8, 0.0, 255.0) / 255.0;
  }

  fragment float4 pixelcraft_fragment(
    VertexOut in [[stage_in]],
    texture2d<float> camera [[texture(0)]],
    texture3d<float> filmLut [[texture(1)]],
    texture3d<float> creativeLut [[texture(2)]],
    constant PreviewUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler cameraSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    constexpr sampler lutSampler(coord::normalized, address::clamp_to_edge, filter::linear);

    float2 uv = (in.uv - float2(0.5)) * uniforms.cropScale + float2(0.5);
    uv.x = mix(uv.x, 1.0 - uv.x, uniforms.mirrorX);
    float3 source = camera.sample(cameraSampler, uv).rgb;
    if (uniforms.enabled < 0.5) {
      return float4(source, 1.0);
    }

    float3 color = clamp(source + (uniforms.brightness - 1.0), 0.0, 1.0);
    const float midpoint = 128.0 / 255.0;
    color = clamp((color - midpoint) * uniforms.contrast + midpoint, 0.0, 1.0);
    const float luminance = dot(color, float3(0.2126, 0.7152, 0.0722));
    color = clamp(luminance + (color - luminance) * uniforms.saturation, 0.0, 1.0);

    if (uniforms.useFilm > 0.5) {
      float3 film = sample_lut(filmLut, lutSampler, color);
      color = mix(color, film, clamp(uniforms.filmStrength, 0.0, 1.0));
    }

    uint creativeMode = uint(uniforms.creativeMode + 0.5);
    if (creativeMode == 1 || creativeMode == 2) {
      color = apply_exact_creative(color, creativeMode, uniforms.creativeStrength);
    } else if (creativeMode == 3) {
      float3 creative = sample_lut(creativeLut, lutSampler, color);
      color = mix(color, creative, clamp(uniforms.creativeStrength, 0.0, 1.0));
    }

    return float4(color, 1.0);
  }
  """

  let device: MTLDevice

  private let commandQueue: MTLCommandQueue
  private let pipeline: MTLRenderPipelineState
  private let lutLoader: MetalFilmLutLoader
  private let session = AVCaptureSession()
  private let videoOutput = AVCaptureVideoDataOutput()
  private let photoOutput = AVCapturePhotoOutput()
  private let sessionQueue = DispatchQueue(label: "dev.pixelcraft.gpu.camera.session")
  private let captureQueue = DispatchQueue(label: "dev.pixelcraft.gpu.camera.frames", qos: .userInteractive)
  private let renderQueue = DispatchQueue(label: "dev.pixelcraft.gpu.camera.metal", qos: .userInteractive)
  private let lookQueue = DispatchQueue(label: "dev.pixelcraft.gpu.camera.look", qos: .userInitiated)
  private let frameLock = NSLock()
  private var latestPixelBuffer: CVPixelBuffer?
  private var latestFrameSerial: UInt64 = 0
  private var lastScheduledFrameSerial: UInt64 = 0
  private var lookGeneration: UInt64 = 0
  private var textureCache: CVMetalTextureCache?
  private var diagnosticsMonitor: GpuFramePacingMonitor?

  private weak var outputView: MTKView?
  private var currentInput: AVCaptureDeviceInput?
  private var lensPosition: AVCaptureDevice.Position = .back
  private var interfaceOrientation: UIInterfaceOrientation = .portrait
  private var currentFilmLut: MTLTexture
  private var currentCreativeLut: MTLTexture
  private var profileId = ""
  private var strength: Float = 0
  private var enabled = false
  private var cameraLookMode = false
  private var lookBrightness: Float = 1
  private var lookContrast: Float = 1
  private var lookSaturation: Float = 1
  private var lookUseFilm: Float = 0
  private var lookFilmStrength: Float = 0
  private var lookCreativeStrength: Float = 0
  private var lookCreativeMode: Float = 0
  private var flashMode: AVCaptureDevice.FlashMode = .auto
  private var torchEnabled = false
  private var mirrorFrontPreview = true
  private var released = false
  private var configured = false
  private var captureHandler: CaptureHandler?
  private let onFailure: FailureHandler

  init(onFailure: @escaping FailureHandler) throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
      throw Self.error("Metal device is unavailable")
    }
    guard let commandQueue = device.makeCommandQueue() else {
      throw Self.error("Unable to create Metal command queue")
    }
    let library = try Self.makeLibrary(device: device)
    guard
      let vertex = library.makeFunction(name: "pixelcraft_vertex"),
      let fragment = library.makeFunction(name: "pixelcraft_fragment")
    else {
      throw Self.error("Metal camera look shader functions are unavailable")
    }
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = vertex
    descriptor.fragmentFunction = fragment
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    let loader = MetalFilmLutLoader(device: device)
    let identity = try loader.makeIdentity()

    self.device = device
    self.commandQueue = commandQueue
    self.pipeline = pipeline
    self.lutLoader = loader
    self.currentFilmLut = identity
    self.currentCreativeLut = identity
    self.onFailure = onFailure
    super.init()

    var cache: CVMetalTextureCache?
    let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
    guard status == kCVReturnSuccess, let cache else {
      throw Self.error("Unable to create CVMetalTextureCache")
    }
    textureCache = cache
  }

  static func makeLibrary(device: MTLDevice) throws -> MTLLibrary {
    try device.makeLibrary(source: shaderSource, options: nil)
  }

  func setDiagnosticsMonitor(_ monitor: GpuFramePacingMonitor?) {
    frameLock.lock()
    diagnosticsMonitor = monitor
    frameLock.unlock()
  }

  func colorCharacterizationSample(maxSamples: Int = 4096) throws -> [String: Any] {
    frameLock.lock()
    guard let pixelBuffer = latestPixelBuffer else {
      frameLock.unlock()
      throw Self.error("No camera frame is available for color characterization")
    }
    let activeProfile = profileId
    let activeStrength = strength
    let filmEnabled = enabled && !activeProfile.isEmpty && !cameraLookMode
    frameLock.unlock()

    guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
      throw Self.error("Color characterization requires a 32BGRA camera frame")
    }

    let lutBytes: Data?
    if filmEnabled {
      guard let url = Bundle.main.url(
        forResource: activeProfile,
        withExtension: "rgba8",
        subdirectory: "gpu_luts"
      ) else {
        throw Self.error("Missing Film LUT asset for color characterization: \(activeProfile)")
      }
      lutBytes = try Data(contentsOf: url)
      let expected = 198 * 198 * 4
      guard lutBytes?.count == expected else {
        throw Self.error("Invalid Film LUT atlas size for color characterization")
      }
    } else {
      lutBytes = nil
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
      throw Self.error("Camera frame has no readable base address")
    }
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let side = min(width, height)
    let originX = (width - side) / 2
    let originY = (height - side) / 2
    let requested = max(64, maxSamples)
    let step = max(1, Int(Double(side) / sqrt(Double(requested))))
    let bytes = base.assumingMemoryBound(to: UInt8.self)

    var sourceSum = SIMD3<Double>(repeating: 0)
    var filmSum = SIMD3<Double>(repeating: 0)
    var samples = 0
    for y in stride(from: originY, to: originY + side, by: step) {
      for x in stride(from: originX, to: originX + side, by: step) {
        let offset = y * bytesPerRow + x * 4
        let source = SIMD3<Double>(
          Double(bytes[offset + 2]) / 255.0,
          Double(bytes[offset + 1]) / 255.0,
          Double(bytes[offset]) / 255.0
        )
        sourceSum += source
        if let lutBytes {
          let transformed = Self.sampleAtlasLut(source, atlas: lutBytes)
          let amount = Double(max(0, min(1, activeStrength)))
          filmSum += source + (transformed - source) * amount
        } else {
          filmSum += source
        }
        samples += 1
      }
    }
    guard samples > 0 else { throw Self.error("Color characterization produced no camera samples") }
    let sourceMean = sourceSum / Double(samples)
    let filmMean = filmSum / Double(samples)
    return [
      "profileId": activeProfile,
      "strength": Double(activeStrength),
      "filmEnabled": filmEnabled,
      "samples": samples,
      "sourceMeanRgb": [sourceMean.x, sourceMean.y, sourceMean.z],
      "filmMeanRgb": [filmMean.x, filmMean.y, filmMean.z],
      "roi": "centerSquare",
      "pixelFormat": "32BGRA",
    ]
  }

  func attach(view: MTKView, orientation: UIInterfaceOrientation) {
    outputView = view
    interfaceOrientation = orientation
    view.device = device
    view.colorPixelFormat = .bgra8Unorm
    view.framebufferOnly = true
    view.delegate = self
    view.preferredFramesPerSecond = 60
    view.isPaused = false
    view.enableSetNeedsDisplay = false
    sessionQueue.async { [weak self] in self?.configureAndStartIfNeeded() }
  }

  func detach(view: MTKView) {
    if outputView === view { view.delegate = nil; outputView = nil }
  }

  func updateInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
    interfaceOrientation = orientation
    sessionQueue.async { [weak self] in self?.applyOrientation() }
  }

  func setFilm(profileId: String, strength: Double) {
    frameLock.lock(); lookGeneration &+= 1; let generation = lookGeneration; frameLock.unlock()
    let clamped = Float(max(0, min(1, strength)))
    lookQueue.async { [weak self] in
      guard let self, !self.released else { return }
      do {
        let texture = try self.lutLoader.load(profileId: profileId)
        guard self.isCurrentLookGeneration(generation) else { return }
        self.renderQueue.async { [weak self] in
          guard let self, !self.released, self.isCurrentLookGeneration(generation) else { return }
          self.cameraLookMode = false
          self.profileId = profileId
          self.strength = clamped
          self.currentFilmLut = texture
          self.lookBrightness = 1
          self.lookContrast = 1
          self.lookSaturation = 1
          self.lookUseFilm = profileId.isEmpty || clamped <= 0 ? 0 : 1
          self.lookFilmStrength = clamped
          self.lookCreativeStrength = 0
          self.lookCreativeMode = Self.creativeNone
        }
      } catch {
        if self.isCurrentLookGeneration(generation) {
          self.fail("Unable to load Film LUT \(profileId): \(error.localizedDescription)")
        }
      }
    }
  }

  func setCameraLook(_ look: NativeGpuCameraLook) {
    frameLock.lock(); lookGeneration &+= 1; let generation = lookGeneration; frameLock.unlock()
    lookQueue.async { [weak self] in
      guard let self, !self.released else { return }
      do {
        let filmTexture = look.hasFilm ? try self.lutLoader.load(profileId: look.filmProfileId) : nil
        let creativeAsset = look.creativeLutAssetId
        let creativeTexture = look.hasCreative && creativeAsset != nil
          ? try self.lutLoader.load(profileId: creativeAsset!) : nil
        let mode: Float
        if !look.hasCreative { mode = Self.creativeNone }
        else if look.creativeFilterId == "grayscale" { mode = Self.creativeGrayscale }
        else if look.creativeFilterId == "invert" { mode = Self.creativeInvert }
        else if creativeTexture != nil { mode = Self.creativeLut }
        else { throw Self.error("Unsupported CameraLook creative stage: \(look.creativeFilterId)") }
        guard self.isCurrentLookGeneration(generation) else { return }
        self.renderQueue.async { [weak self] in
          guard let self, !self.released, self.isCurrentLookGeneration(generation) else { return }
          if let filmTexture { self.currentFilmLut = filmTexture }
          if let creativeTexture { self.currentCreativeLut = creativeTexture }
          self.cameraLookMode = true
          self.profileId = look.filmProfileId
          self.strength = look.filmStrength
          self.lookBrightness = look.brightness
          self.lookContrast = look.contrast
          self.lookSaturation = look.saturation
          self.lookUseFilm = look.hasFilm ? 1 : 0
          self.lookFilmStrength = look.filmStrength
          self.lookCreativeStrength = look.creativeFilterStrength
          self.lookCreativeMode = mode
        }
      } catch {
        if self.isCurrentLookGeneration(generation) {
          self.fail("Unable to prepare CameraLook resources: \(error.localizedDescription)")
        }
      }
    }
  }

  func setStrength(_ value: Double) {
    let clamped = Float(max(0, min(1, value)))
    strength = clamped
    if !cameraLookMode {
      lookFilmStrength = clamped
      lookUseFilm = profileId.isEmpty || clamped <= 0 ? 0 : 1
    }
  }

  func setEnabled(_ value: Bool) { enabled = value }

  func cameraControlState() -> [String: Any] {
    sessionQueue.sync { controlStateMap() }
  }

  func setFlashMode(_ value: String) throws -> [String: Any] {
    try sessionQueue.sync {
      let mode: AVCaptureDevice.FlashMode
      switch value {
      case "off": mode = .off
      case "on": mode = .on
      case "auto": mode = .auto
      default: throw Self.error("Unsupported flash mode: \(value)")
      }
      flashMode = torchEnabled ? .off : mode
      return controlStateMap()
    }
  }

  func setTorchEnabled(_ value: Bool) throws -> [String: Any] {
    try sessionQueue.sync {
      let device = currentInput?.device ?? Self.camera(position: lensPosition)
      guard let device else { throw Self.error("Active camera is unavailable") }
      if value {
        guard device.hasTorch && device.isTorchAvailable else {
          throw Self.error("Torch is unavailable for the active camera")
        }
        flashMode = .off
      }
      try applyTorch(value, device: device)
      torchEnabled = value
      return controlStateMap()
    }
  }

  func setMirrorEnabled(_ value: Bool) -> [String: Any] {
    sessionQueue.sync {
      mirrorFrontPreview = value
      return controlStateMap()
    }
  }

  func pause() {
    DispatchQueue.main.async { [weak self] in self?.outputView?.isPaused = true }
    sessionQueue.async { [weak self] in
      guard let self, self.session.isRunning else { return }
      self.session.stopRunning()
    }
  }

  func resume() {
    DispatchQueue.main.async { [weak self] in self?.outputView?.isPaused = false }
    sessionQueue.async { [weak self] in self?.configureAndStartIfNeeded() }
  }

  func switchCamera(completion: @escaping (Result<String, Error>) -> Void) {
    sessionQueue.async { [weak self] in
      guard let self, !self.released else {
        completion(.failure(Self.error("Renderer is released")))
        return
      }
      let desired: AVCaptureDevice.Position = self.lensPosition == .back ? .front : .back
      guard let device = Self.camera(position: desired) else {
        completion(.failure(Self.error("Requested camera lens is unavailable")))
        return
      }
      do {
        if self.torchEnabled, let currentDevice = self.currentInput?.device {
          try self.applyTorch(false, device: currentDevice)
          self.torchEnabled = false
        }
        let input = try AVCaptureDeviceInput(device: device)
        self.session.beginConfiguration()
        if let current = self.currentInput { self.session.removeInput(current) }
        guard self.session.canAddInput(input) else {
          if let current = self.currentInput, self.session.canAddInput(current) {
            self.session.addInput(current)
          }
          self.session.commitConfiguration()
          completion(.failure(Self.error("Unable to attach requested camera lens")))
          return
        }
        self.session.addInput(input)
        self.currentInput = input
        self.lensPosition = desired
        self.session.commitConfiguration()
        self.applyOrientation()
        completion(.success(desired == .front ? "front" : "back"))
      } catch {
        completion(.failure(error))
      }
    }
  }

  func capturePhoto(completion: @escaping CaptureHandler) {
    sessionQueue.async { [weak self] in
      guard let self, self.session.isRunning else {
        completion(.failure(Self.error("Camera is not ready")))
        return
      }
      guard self.captureHandler == nil else {
        completion(.failure(Self.error("Capture already in progress")))
        return
      }
      self.captureHandler = completion
      self.applyOrientation()
      let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
      let captureDevice = self.currentInput?.device
      settings.flashMode = captureDevice?.hasFlash == true && !self.torchEnabled
        ? self.flashMode
        : .off
      self.photoOutput.capturePhoto(with: settings, delegate: self)
    }
  }

  func releaseRenderer() {
    frameLock.lock(); lookGeneration &+= 1; frameLock.unlock()
    released = true
    if let view = outputView { view.delegate = nil; view.isPaused = true }
    outputView = nil
    videoOutput.setSampleBufferDelegate(nil, queue: nil)
    frameLock.lock(); latestPixelBuffer = nil; diagnosticsMonitor = nil; frameLock.unlock()
    sessionQueue.async { [weak self] in
      guard let self else { return }
      if self.torchEnabled, let device = self.currentInput?.device {
        try? self.applyTorch(false, device: device)
        self.torchEnabled = false
      }
      if self.session.isRunning { self.session.stopRunning() }
      self.captureHandler?(.failure(Self.error("Camera closed during capture")))
      self.captureHandler = nil
      self.currentInput = nil
    }
    if let cache = textureCache { CVMetalTextureCacheFlush(cache, 0) }
    textureCache = nil
  }

  private func controlStateMap() -> [String: Any] {
    let camera = currentInput?.device ?? Self.camera(position: lensPosition)
    return [
      "lensDirection": lensPosition == .front ? "front" : "back",
      "hasFlash": camera?.hasFlash ?? false,
      "hasTorch": camera?.hasTorch ?? false,
      "flashMode": Self.flashModeName(flashMode),
      "torchEnabled": torchEnabled,
      "mirrorEnabled": mirrorFrontPreview,
    ]
  }

  private func applyTorch(_ enabled: Bool, device: AVCaptureDevice) throws {
    guard device.hasTorch else {
      if enabled { throw Self.error("Torch is unavailable for the active camera") }
      return
    }
    try device.lockForConfiguration()
    defer { device.unlockForConfiguration() }
    device.torchMode = enabled ? .on : .off
  }

  private static func flashModeName(_ mode: AVCaptureDevice.FlashMode) -> String {
    switch mode {
    case .on: return "on"
    case .auto: return "auto"
    default: return "off"
    }
  }

  private func isCurrentLookGeneration(_ generation: UInt64) -> Bool {
    frameLock.lock(); let current = generation == lookGeneration && !released; frameLock.unlock(); return current
  }

  private func configureAndStartIfNeeded() {
    guard !released, outputView != nil else { return }
    do {
      if !configured { try configureSession(); configured = true }
      applyOrientation()
      if !session.isRunning { session.startRunning() }
    } catch {
      fail("Unable to start AVFoundation camera: \(error.localizedDescription)")
    }
  }

  private func configureSession() throws {
    guard let camera = Self.camera(position: lensPosition) ?? Self.camera(position: .front) else {
      throw Self.error("No camera is available")
    }
    lensPosition = camera.position
    let input = try AVCaptureDeviceInput(device: camera)
    session.beginConfiguration()
    defer { session.commitConfiguration() }
    session.sessionPreset = .high
    guard session.canAddInput(input) else { throw Self.error("Unable to add camera input") }
    session.addInput(input)
    currentInput = input
    videoOutput.alwaysDiscardsLateVideoFrames = true
    videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
    videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
    guard session.canAddOutput(videoOutput) else { throw Self.error("Unable to add video output") }
    session.addOutput(videoOutput)
    guard session.canAddOutput(photoOutput) else { throw Self.error("Unable to add clean photo output") }
    session.addOutput(photoOutput)
  }

  private func applyOrientation() {
    let videoOrientation = Self.captureOrientation(from: interfaceOrientation)
    if let connection = videoOutput.connection(with: .video) {
      if connection.isVideoOrientationSupported { connection.videoOrientation = videoOrientation }
      if connection.isVideoMirroringSupported { connection.isVideoMirrored = false }
    }
    if let connection = photoOutput.connection(with: .video) {
      if connection.isVideoOrientationSupported { connection.videoOrientation = videoOrientation }
      if connection.isVideoMirroringSupported { connection.isVideoMirrored = false }
    }
  }

  private func latestFrameForRender() -> (pixelBuffer: CVPixelBuffer, isUnique: Bool)? {
    frameLock.lock()
    guard let pixelBuffer = latestPixelBuffer else { frameLock.unlock(); return nil }
    let isUnique = latestFrameSerial != lastScheduledFrameSerial
    if isUnique { lastScheduledFrameSerial = latestFrameSerial }
    frameLock.unlock()
    return (pixelBuffer, isUnique)
  }

  private func render(
    pixelBuffer: CVPixelBuffer,
    drawable: CAMetalDrawable,
    drawableSize: CGSize,
    isUniqueFrame: Bool
  ) {
    guard !released, let cache = textureCache else { return }
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    var cvTexture: CVMetalTexture?
    let status = CVMetalTextureCacheCreateTextureFromImage(
      kCFAllocatorDefault, cache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvTexture
    )
    guard
      status == kCVReturnSuccess,
      let cvTexture,
      let sourceTexture = CVMetalTextureGetTexture(cvTexture),
      let commandBuffer = commandQueue.makeCommandBuffer()
    else { return }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = drawable.texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
    guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
    let crop = cropScale(
      sourceWidth: Float(width),
      sourceHeight: Float(height),
      outputWidth: Float(max(drawableSize.width, 1)),
      outputHeight: Float(max(drawableSize.height, 1))
    )
    var uniforms = PreviewUniforms(
      cropScale: crop,
      mirrorX: lensPosition == .front && mirrorFrontPreview ? 1 : 0,
      enabled: enabled ? 1 : 0,
      brightness: lookBrightness,
      contrast: lookContrast,
      saturation: lookSaturation,
      filmStrength: lookFilmStrength,
      useFilm: lookUseFilm,
      creativeStrength: lookCreativeStrength,
      creativeMode: lookCreativeMode
    )
    encoder.setRenderPipelineState(pipeline)
    encoder.setFragmentTexture(sourceTexture, index: 0)
    encoder.setFragmentTexture(currentFilmLut, index: 1)
    encoder.setFragmentTexture(currentCreativeLut, index: 2)
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<PreviewUniforms>.stride, index: 0)
    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    encoder.endEncoding()
    commandBuffer.present(drawable)
    let committedAt = CACurrentMediaTime()
    let monitor = diagnosticsMonitor
    commandBuffer.addCompletedHandler { [weak monitor] _ in
      guard let monitor else { return }
      monitor.recordCommandCompletion(
        latencyMs: (CACurrentMediaTime() - committedAt) * 1000.0,
        uniqueFrame: isUniqueFrame
      )
    }
    commandBuffer.commit()
  }

  private static func sampleAtlasLut(_ color: SIMD3<Double>, atlas: Data) -> SIMD3<Double> {
    let scaled = SIMD3<Double>(
      max(0, min(1, color.x)) * 32.0,
      max(0, min(1, color.y)) * 32.0,
      max(0, min(1, color.z)) * 32.0
    )
    let r0 = Int(floor(scaled.x)), g0 = Int(floor(scaled.y)), b0 = Int(floor(scaled.z))
    let r1 = min(r0 + 1, 32), g1 = min(g0 + 1, 32), b1 = min(b0 + 1, 32)
    let rf = scaled.x - Double(r0), gf = scaled.y - Double(g0), bf = scaled.z - Double(b0)
    func texel(_ red: Int, _ green: Int, _ blue: Int) -> SIMD3<Double> {
      let tileX = blue % 6, tileY = blue / 6
      let x = tileX * 33 + red, y = tileY * 33 + green, offset = (y * 198 + x) * 4
      return atlas.withUnsafeBytes { raw in
        let bytes = raw.bindMemory(to: UInt8.self)
        return SIMD3(Double(bytes[offset]) / 255.0, Double(bytes[offset + 1]) / 255.0, Double(bytes[offset + 2]) / 255.0)
      }
    }
    func slice(_ blue: Int) -> SIMD3<Double> {
      let c00 = texel(r0, g0, blue), c10 = texel(r1, g0, blue), c01 = texel(r0, g1, blue), c11 = texel(r1, g1, blue)
      let top = c00 + (c10 - c00) * rf, bottom = c01 + (c11 - c01) * rf
      return top + (bottom - top) * gf
    }
    let low = slice(b0), high = slice(b1)
    return low + (high - low) * bf
  }

  private func cropScale(
    sourceWidth: Float,
    sourceHeight: Float,
    outputWidth: Float,
    outputHeight: Float
  ) -> SIMD2<Float> {
    let sourceAspect = sourceWidth / sourceHeight
    let outputAspect = outputWidth / outputHeight
    if sourceAspect > outputAspect { return SIMD2<Float>(outputAspect / sourceAspect, 1) }
    return SIMD2<Float>(1, sourceAspect / outputAspect)
  }

  private func fail(_ message: String) {
    guard !released else { return }
    DispatchQueue.main.async { [onFailure] in onFailure(message) }
  }

  private static func camera(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
    AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInWideAngleCamera],
      mediaType: .video,
      position: position
    ).devices.first
  }

  static func availableLenses() -> [String] {
    var result: [String] = []
    if camera(position: .back) != nil { result.append("back") }
    if camera(position: .front) != nil { result.append("front") }
    return result
  }

  private static func captureOrientation(from orientation: UIInterfaceOrientation) -> AVCaptureVideoOrientation {
    switch orientation {
    case .landscapeLeft: return .landscapeLeft
    case .landscapeRight: return .landscapeRight
    case .portraitUpsideDown: return .portraitUpsideDown
    default: return .portrait
    }
  }

  private static func error(_ message: String) -> NSError {
    NSError(domain: "PixelCraftGpu", code: 2001, userInfo: [NSLocalizedDescriptionKey: message])
  }
}

extension MetalCameraPreviewRenderer: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    frameLock.lock()
    let overwrotePending = latestPixelBuffer != nil && latestFrameSerial != lastScheduledFrameSerial
    latestFrameSerial &+= 1
    latestPixelBuffer = pixelBuffer
    let monitor = diagnosticsMonitor
    frameLock.unlock()
    monitor?.recordCaptureFrame(overwrotePending: overwrotePending)
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didDrop sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    frameLock.lock(); let monitor = diagnosticsMonitor; frameLock.unlock()
    monitor?.recordDroppedCaptureFrame()
  }
}

extension MetalCameraPreviewRenderer: MTKViewDelegate {
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

  func draw(in view: MTKView) {
    guard !released, outputView === view, let frame = latestFrameForRender(), let drawable = view.currentDrawable else { return }
    let drawableSize = view.drawableSize
    renderQueue.async { [weak self] in
      self?.render(
        pixelBuffer: frame.pixelBuffer,
        drawable: drawable,
        drawableSize: drawableSize,
        isUniqueFrame: frame.isUnique
      )
    }
  }
}

extension MetalCameraPreviewRenderer: AVCapturePhotoCaptureDelegate {
  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: Error?
  ) {
    let completion = captureHandler
    captureHandler = nil
    if let error { completion?(.failure(error)); return }
    guard let data = photo.fileDataRepresentation() else {
      completion?(.failure(Self.error("AVCapturePhotoOutput returned no JPEG data"))); return
    }
    do {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pixelcraft-camera", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
      let file = directory.appendingPathComponent("capture-\(UUID().uuidString).jpg")
      try data.write(to: file, options: .atomic)
      completion?(.success(file.path))
    } catch {
      completion?(.failure(error))
    }
  }
}
