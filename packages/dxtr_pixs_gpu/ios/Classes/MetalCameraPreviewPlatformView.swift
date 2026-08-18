import Flutter
import MetalKit
import QuartzCore
import UIKit

final class MetalCameraPreviewViewFactory: NSObject, FlutterPlatformViewFactory {
  private let registry: MetalRendererRegistry

  init(registry: MetalRendererRegistry) {
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
    let parameters = args as? [String: Any]
    let rendererId = parameters?["rendererId"] as? String ?? ""
    return MetalCameraPreviewPlatformView(
      frame: frame,
      rendererId: rendererId,
      registry: registry
    )
  }
}

final class MetalCameraPreviewPlatformView: NSObject, FlutterPlatformView {
  private let rendererId: String
  private let registry: MetalRendererRegistry
  private let metalView: PixelCraftMetalView
  private var framePacingProxy: MetalFramePacingDelegateProxy?
  private var orientationObserver: NSObjectProtocol?

  init(frame: CGRect, rendererId: String, registry: MetalRendererRegistry) {
    self.rendererId = rendererId
    self.registry = registry
    self.metalView = PixelCraftMetalView(frame: frame)
    super.init()

    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    orientationObserver = NotificationCenter.default.addObserver(
      forName: UIDevice.orientationDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      self.updateOrientation(for: self.metalView)
    }

    metalView.onLayout = { [weak self] view in
      self?.updateOrientation(for: view)
    }

    do {
      try registry.attach(
        id: rendererId,
        view: metalView,
        orientation: currentOrientation(for: metalView)
      )

      let renderer = try registry.renderer(id: rendererId)
      let diagnostics = GpuFramePacingDiagnostics.shared
      let monitor = diagnostics.monitor(rendererId: rendererId)
      renderer.setDiagnosticsMonitor(monitor)
      diagnostics.registerColorProvider(rendererId: rendererId) { maxSamples in
        try renderer.colorCharacterizationSample(maxSamples: maxSamples)
      }
      let proxy = MetalFramePacingDelegateProxy(renderer: renderer, monitor: monitor)
      framePacingProxy = proxy
      metalView.delegate = proxy
    } catch {
      // The Dart control plane receives renderer failures through the channel.
    }
  }

  func view() -> UIView {
    metalView
  }

  deinit {
    if let orientationObserver {
      NotificationCenter.default.removeObserver(orientationObserver)
    }
    UIDevice.current.endGeneratingDeviceOrientationNotifications()
    if let renderer = try? registry.renderer(id: rendererId) {
      renderer.setDiagnosticsMonitor(nil)
    }
    registry.detach(id: rendererId, view: metalView)
    GpuFramePacingDiagnostics.shared.remove(rendererId: rendererId)
  }

  private func updateOrientation(for view: UIView) {
    let orientation = currentOrientation(for: view)
    if let renderer = try? registry.renderer(id: rendererId) {
      renderer.updateInterfaceOrientation(orientation)
    }
  }

  private func currentOrientation(for view: UIView) -> UIInterfaceOrientation {
    switch UIDevice.current.orientation {
    case .portrait:
      return .portrait
    case .portraitUpsideDown:
      return .portraitUpsideDown
    case .landscapeLeft:
      return .landscapeRight
    case .landscapeRight:
      return .landscapeLeft
    default:
      if let orientation = view.window?.windowScene?.interfaceOrientation {
        return orientation
      }
      return .portrait
    }
  }
}

final class PixelCraftMetalView: MTKView {
  var onLayout: ((UIView) -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    drawableSize = CGSize(
      width: max(bounds.width * contentScaleFactor, 1),
      height: max(bounds.height * contentScaleFactor, 1)
    )
    onLayout?(self)
  }
}

private final class MetalFramePacingDelegateProxy: NSObject, MTKViewDelegate {
  private weak var renderer: MetalCameraPreviewRenderer?
  private let monitor: GpuFramePacingMonitor

  init(renderer: MetalCameraPreviewRenderer, monitor: GpuFramePacingMonitor) {
    self.renderer = renderer
    self.monitor = monitor
    super.init()
  }

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    renderer?.mtkView(view, drawableSizeWillChange: size)
  }

  func draw(in view: MTKView) {
    monitor.recordFrame()
    renderer?.draw(in: view)
  }
}

final class GpuFramePacingDiagnostics {
  typealias ColorProvider = (Int) throws -> [String: Any]

  static let shared = GpuFramePacingDiagnostics()
  static let channelName = "dev.pixelcraft/gpu_frame_pacing_v1"

  private let lock = NSLock()
  private let colorQueue = DispatchQueue(label: "dev.pixelcraft.gpu.color-characterization", qos: .userInitiated)
  private var monitors: [String: GpuFramePacingMonitor] = [:]
  private var colorProviders: [String: ColorProvider] = [:]
  private var channel: FlutterMethodChannel?

  private init() {}

  func register(messenger: FlutterBinaryMessenger) {
    guard channel == nil else { return }
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
    self.channel = channel
  }

  func monitor(rendererId: String) -> GpuFramePacingMonitor {
    lock.lock()
    defer { lock.unlock() }
    if let existing = monitors[rendererId] { return existing }
    let monitor = GpuFramePacingMonitor()
    monitors[rendererId] = monitor
    return monitor
  }

  func registerColorProvider(rendererId: String, provider: @escaping ColorProvider) {
    lock.lock()
    colorProviders[rendererId] = provider
    lock.unlock()
  }

  func remove(rendererId: String) {
    lock.lock()
    monitors.removeValue(forKey: rendererId)
    colorProviders.removeValue(forKey: rendererId)
    lock.unlock()
  }

  private func colorProvider(rendererId: String) -> ColorProvider? {
    lock.lock()
    defer { lock.unlock() }
    return colorProviders[rendererId]
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    guard let rendererId = args["rendererId"] as? String, !rendererId.isEmpty else {
      result(FlutterError(
        code: "gpu_frame_pacing_invalid",
        message: "rendererId is required",
        details: nil
      ))
      return
    }

    if call.method == "colorSample" {
      guard let provider = colorProvider(rendererId: rendererId) else {
        result(FlutterError(
          code: "gpu_color_characterization_unavailable",
          message: "Color characterization provider is unavailable for this renderer",
          details: nil
        ))
        return
      }
      let maxSamples = max(64, (args["maxSamples"] as? NSNumber)?.intValue ?? 4096)
      colorQueue.async {
        do {
          let payload = try provider(maxSamples)
          DispatchQueue.main.async { result(payload) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "gpu_color_characterization_failed",
              message: error.localizedDescription,
              details: nil
            ))
          }
        }
      }
      return
    }

    let monitor = monitor(rendererId: rendererId)
    switch call.method {
    case "start":
      monitor.start()
      result(nil)
    case "snapshot":
      result(monitor.snapshot().toChannelMap())
    case "stop":
      result(monitor.stop().toChannelMap())
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

final class GpuFramePacingMonitor {
  private let lock = NSLock()
  private var active = false
  private var startedAt: CFTimeInterval = 0

  private var lastFrameAt: CFTimeInterval?
  private var frameCount = 0
  private var intervalsMs: [Double] = []

  private var lastCaptureAt: CFTimeInterval?
  private var captureFrameCount = 0
  private var captureIntervalsMs: [Double] = []
  private var overwrittenCaptureFrames = 0
  private var droppedCaptureFrames = 0

  private var commandCompletionLatenciesMs: [Double] = []
  private var commandCompletionCount = 0
  private var uniqueRenderedFrames = 0

  func start() {
    lock.lock()
    defer { lock.unlock() }
    active = true
    startedAt = CACurrentMediaTime()

    lastFrameAt = nil
    frameCount = 0
    intervalsMs.removeAll(keepingCapacity: true)

    lastCaptureAt = nil
    captureFrameCount = 0
    captureIntervalsMs.removeAll(keepingCapacity: true)
    overwrittenCaptureFrames = 0
    droppedCaptureFrames = 0

    commandCompletionLatenciesMs.removeAll(keepingCapacity: true)
    commandCompletionCount = 0
    uniqueRenderedFrames = 0
  }

  func recordFrame() {
    let now = CACurrentMediaTime()
    lock.lock()
    defer { lock.unlock() }
    guard active else { return }

    if let previous = lastFrameAt {
      intervalsMs.append((now - previous) * 1000.0)
    }
    lastFrameAt = now
    frameCount += 1
  }

  func recordCaptureFrame(overwrotePending: Bool) {
    let now = CACurrentMediaTime()
    lock.lock()
    defer { lock.unlock() }
    guard active else { return }

    if let previous = lastCaptureAt {
      captureIntervalsMs.append((now - previous) * 1000.0)
    }
    lastCaptureAt = now
    captureFrameCount += 1
    if overwrotePending {
      overwrittenCaptureFrames += 1
    }
  }

  func recordDroppedCaptureFrame() {
    lock.lock()
    defer { lock.unlock() }
    guard active else { return }
    droppedCaptureFrames += 1
  }

  func recordCommandCompletion(latencyMs: Double, uniqueFrame: Bool) {
    lock.lock()
    defer { lock.unlock() }
    guard active else { return }
    commandCompletionCount += 1
    commandCompletionLatenciesMs.append(max(latencyMs, 0))
    if uniqueFrame {
      uniqueRenderedFrames += 1
    }
  }

  func stop() -> GpuFramePacingSnapshot {
    lock.lock()
    active = false
    let snapshot = makeSnapshot(now: CACurrentMediaTime())
    lock.unlock()
    return snapshot
  }

  func snapshot() -> GpuFramePacingSnapshot {
    lock.lock()
    let snapshot = makeSnapshot(now: CACurrentMediaTime())
    lock.unlock()
    return snapshot
  }

  private func makeSnapshot(now: CFTimeInterval) -> GpuFramePacingSnapshot {
    let elapsed = startedAt > 0 ? max(now - startedAt, 0) : 0
    let sorted = intervalsMs.sorted()
    let captureSorted = captureIntervalsMs.sorted()
    let completionSorted = commandCompletionLatenciesMs.sorted()

    return GpuFramePacingSnapshot(
      active: active,
      elapsedSeconds: elapsed,
      frameCount: frameCount,
      fps: rate(fromIntervalsMs: intervalsMs),
      averageFrameMs: average(sorted),
      p95FrameMs: percentile(sorted, 0.95),
      p99FrameMs: percentile(sorted, 0.99),
      maxFrameMs: sorted.last ?? 0,
      over40MsFrames: intervalsMs.filter { $0 > 40.0 }.count,
      captureFrameCount: captureFrameCount,
      captureFps: rate(fromIntervalsMs: captureIntervalsMs),
      averageCaptureMs: average(captureSorted),
      p95CaptureMs: percentile(captureSorted, 0.95),
      overwrittenCaptureFrames: overwrittenCaptureFrames,
      droppedCaptureFrames: droppedCaptureFrames,
      commandCompletionCount: commandCompletionCount,
      uniqueRenderedFrames: uniqueRenderedFrames,
      uniqueRenderedFps: elapsed > 0 ? Double(uniqueRenderedFrames) / elapsed : 0,
      averageCommandCompletionMs: average(completionSorted),
      p95CommandCompletionMs: percentile(completionSorted, 0.95),
      p99CommandCompletionMs: percentile(completionSorted, 0.99),
      maxCommandCompletionMs: completionSorted.last ?? 0
    )
  }

  private func average(_ values: [Double]) -> Double {
    values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
  }

  private func rate(fromIntervalsMs values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let seconds = values.reduce(0, +) / 1000.0
    return seconds > 0 ? Double(values.count) / seconds : 0
  }

  private func percentile(_ sorted: [Double], _ percentile: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let position = Int(ceil(percentile * Double(sorted.count))) - 1
    return sorted[max(0, min(position, sorted.count - 1))]
  }
}

struct GpuFramePacingSnapshot {
  let active: Bool
  let elapsedSeconds: Double
  let frameCount: Int
  let fps: Double
  let averageFrameMs: Double
  let p95FrameMs: Double
  let p99FrameMs: Double
  let maxFrameMs: Double
  let over40MsFrames: Int

  let captureFrameCount: Int
  let captureFps: Double
  let averageCaptureMs: Double
  let p95CaptureMs: Double
  let overwrittenCaptureFrames: Int
  let droppedCaptureFrames: Int

  let commandCompletionCount: Int
  let uniqueRenderedFrames: Int
  let uniqueRenderedFps: Double
  let averageCommandCompletionMs: Double
  let p95CommandCompletionMs: Double
  let p99CommandCompletionMs: Double
  let maxCommandCompletionMs: Double

  func toChannelMap() -> [String: Any] {
    [
      "active": active,
      "elapsedSeconds": elapsedSeconds,
      "frameCount": frameCount,
      "fps": fps,
      "averageFrameMs": averageFrameMs,
      "p95FrameMs": p95FrameMs,
      "p99FrameMs": p99FrameMs,
      "maxFrameMs": maxFrameMs,
      "over40MsFrames": over40MsFrames,
      "captureFrameCount": captureFrameCount,
      "captureFps": captureFps,
      "averageCaptureMs": averageCaptureMs,
      "p95CaptureMs": p95CaptureMs,
      "overwrittenCaptureFrames": overwrittenCaptureFrames,
      "droppedCaptureFrames": droppedCaptureFrames,
      "commandCompletionCount": commandCompletionCount,
      "uniqueRenderedFrames": uniqueRenderedFrames,
      "uniqueRenderedFps": uniqueRenderedFps,
      "averageCommandCompletionMs": averageCommandCompletionMs,
      "p95CommandCompletionMs": p95CommandCompletionMs,
      "p99CommandCompletionMs": p99CommandCompletionMs,
      "maxCommandCompletionMs": maxCommandCompletionMs,
      "source": "mtkView+avcapture+metalCompletion",
    ]
  }
}
