import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import Metal
import MetalKit
import UIKit

final class MetalCameraPreviewRenderer: NSObject {
  typealias FailureHandler = (String) -> Void
  typealias CaptureHandler = (Result<String, Error>) -> Void

  private struct PreviewUniforms {
    var cropScale: SIMD2<Float>
    var mirrorX: Float
    var strength: Float
    var useLut: Float
    var padding: Float = 0
  }

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
    float strength;
    float useLut;
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

  fragment float4 pixelcraft_fragment(
    VertexOut in [[stage_in]],
    texture2d<float> camera [[texture(0)]],
    texture3d<float> lut [[texture(1)]],
    constant PreviewUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler cameraSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    constexpr sampler lutSampler(coord::normalized, address::clamp_to_edge, filter::linear);

    float2 uv = (in.uv - float2(0.5)) * uniforms.cropScale + float2(0.5);
    uv.x = mix(uv.x, 1.0 - uv.x, uniforms.mirrorX);
    float3 source = camera.sample(cameraSampler, uv).rgb;
    float3 film = lut.sample(lutSampler, clamp(source, 0.0, 1.0)).rgb;
    float amount = clamp(uniforms.useLut * uniforms.strength, 0.0, 1.0);
    return float4(mix(source, film, amount), 1.0);
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
  private let renderQueue = DispatchQueue(label: "dev.pixelcraft.gpu.camera.metal", qos: .userInteractive)
  private var textureCache: CVMetalTextureCache?

  private weak var outputView: MTKView?
  private var currentInput: AVCaptureDeviceInput?
  private var lensPosition: AVCaptureDevice.Position = .back
  private var interfaceOrientation: UIInterfaceOrientation = .portrait
  private var currentLut: MTLTexture
  private var profileId = ""
  private var strength: Float = 0
  private var enabled = false
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
      throw Self.error("Metal Film shader functions are unavailable")
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
    self.currentLut = identity
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

  func attach(view: MTKView, orientation: UIInterfaceOrientation) {
    outputView = view
    interfaceOrientation = orientation
    view.device = device
    view.colorPixelFormat = .bgra8Unorm
    view.framebufferOnly = true
    view.isPaused = true
    view.enableSetNeedsDisplay = false
    sessionQueue.async { [weak self] in
      self?.configureAndStartIfNeeded()
    }
  }

  func detach(view: MTKView) {
    if outputView === view {
      outputView = nil
    }
  }

  func updateInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
    interfaceOrientation = orientation
    sessionQueue.async { [weak self] in
      self?.applyOrientation()
    }
  }

  func setFilm(profileId: String, strength: Double) {
    self.profileId = profileId
    self.strength = Float(max(0, min(1, strength)))
    renderQueue.async { [weak self] in
      guard let self, !self.released else { return }
      do {
        self.currentLut = try self.lutLoader.load(profileId: profileId)
      } catch {
        self.fail("Unable to load Film LUT \(profileId): \(error.localizedDescription)")
      }
    }
  }

  func setStrength(_ value: Double) {
    strength = Float(max(0, min(1, value)))
  }

  func setEnabled(_ value: Bool) {
    enabled = value
  }

  func pause() {
    sessionQueue.async { [weak self] in
      guard let self, self.session.isRunning else { return }
      self.session.stopRunning()
    }
  }

  func resume() {
    sessionQueue.async { [weak self] in
      self?.configureAndStartIfNeeded()
    }
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
        let input = try AVCaptureDeviceInput(device: device)
        self.session.beginConfiguration()
        if let current = self.currentInput {
          self.session.removeInput(current)
        }
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
        self.session.commitConfiguration()
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
      self.photoOutput.capturePhoto(with: settings, delegate: self)
    }
  }

  func releaseRenderer() {
    released = true
    outputView = nil
    videoOutput.setSampleBufferDelegate(nil, queue: nil)
    sessionQueue.async { [weak self] in
      guard let self else { return }
      if self.session.isRunning { self.session.stopRunning() }
      self.captureHandler?(.failure(Self.error("Camera closed during capture")))
      self.captureHandler = nil
      self.currentInput = nil
    }
    if let cache = textureCache {
      CVMetalTextureCacheFlush(cache, 0)
    }
    textureCache = nil
  }

  private func configureAndStartIfNeeded() {
    guard !released, outputView != nil else { return }
    do {
      if !configured {
        try configureSession()
        configured = true
      }
      applyOrientation()
      if !session.isRunning {
        session.startRunning()
      }
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

    guard session.canAddInput(input) else {
      throw Self.error("Unable to add camera input")
    }
    session.addInput(input)
    currentInput = input

    videoOutput.alwaysDiscardsLateVideoFrames = true
    videoOutput.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
    ]
    videoOutput.setSampleBufferDelegate(self, queue: renderQueue)
    guard session.canAddOutput(videoOutput) else {
      throw Self.error("Unable to add video output")
    }
    session.addOutput(videoOutput)

    guard session.canAddOutput(photoOutput) else {
      throw Self.error("Unable to add clean photo output")
    }
    session.addOutput(photoOutput)
  }

  private func applyOrientation() {
    let videoOrientation = Self.captureOrientation(from: interfaceOrientation)
    if let connection = videoOutput.connection(with: .video) {
      if connection.isVideoOrientationSupported {
        connection.videoOrientation = videoOrientation
      }
      if connection.isVideoMirroringSupported {
        connection.isVideoMirrored = false
      }
    }
    if let connection = photoOutput.connection(with: .video) {
      if connection.isVideoOrientationSupported {
        connection.videoOrientation = videoOrientation
      }
      if connection.isVideoMirroringSupported {
        connection.isVideoMirrored = false
      }
    }
  }

  private func render(pixelBuffer: CVPixelBuffer) {
    guard
      !released,
      let view = outputView,
      let drawable = view.currentDrawable,
      let cache = textureCache
    else { return }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    var cvTexture: CVMetalTexture?
    let status = CVMetalTextureCacheCreateTextureFromImage(
      kCFAllocatorDefault,
      cache,
      pixelBuffer,
      nil,
      .bgra8Unorm,
      width,
      height,
      0,
      &cvTexture
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
      outputWidth: Float(max(view.drawableSize.width, 1)),
      outputHeight: Float(max(view.drawableSize.height, 1))
    )
    var uniforms = PreviewUniforms(
      cropScale: crop,
      mirrorX: lensPosition == .front ? 1 : 0,
      strength: strength,
      useLut: enabled && !profileId.isEmpty ? 1 : 0
    )

    encoder.setRenderPipelineState(pipeline)
    encoder.setFragmentTexture(sourceTexture, index: 0)
    encoder.setFragmentTexture(currentLut, index: 1)
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<PreviewUniforms>.stride, index: 0)
    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    encoder.endEncoding()
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }

  private func cropScale(
    sourceWidth: Float,
    sourceHeight: Float,
    outputWidth: Float,
    outputHeight: Float
  ) -> SIMD2<Float> {
    let sourceAspect = sourceWidth / sourceHeight
    let outputAspect = outputWidth / outputHeight
    if sourceAspect > outputAspect {
      return SIMD2<Float>(outputAspect / sourceAspect, 1)
    }
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
    NSError(
      domain: "PixelCraftGpu",
      code: 2001,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}

extension MetalCameraPreviewRenderer: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    render(pixelBuffer: pixelBuffer)
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
    if let error {
      completion?(.failure(error))
      return
    }
    guard let data = photo.fileDataRepresentation() else {
      completion?(.failure(Self.error("AVCapturePhotoOutput returned no JPEG data")))
      return
    }
    do {
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("pixelcraft-camera", isDirectory: true)
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: nil
      )
      let file = directory.appendingPathComponent("capture-\(UUID().uuidString).jpg")
      try data.write(to: file, options: .atomic)
      completion?(.success(file.path))
    } catch {
      completion?(.failure(error))
    }
  }
}
