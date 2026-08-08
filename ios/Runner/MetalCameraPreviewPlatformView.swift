import Flutter
import MetalKit
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

  init(frame: CGRect, rendererId: String, registry: MetalRendererRegistry) {
    self.rendererId = rendererId
    self.registry = registry
    self.metalView = PixelCraftMetalView(frame: frame)
    super.init()

    metalView.onLayout = { [weak self] view in
      self?.updateOrientation(for: view)
    }

    do {
      try registry.attach(
        id: rendererId,
        view: metalView,
        orientation: currentOrientation(for: metalView)
      )

      // The renderer remains the real MTKViewDelegate. In debug diagnostics we
      // insert a lightweight proxy that timestamps each actual MTKView draw
      // callback, then forwards it to the renderer unchanged. No frame pixels
      // or Metal resources cross Flutter/Dart.
      let renderer = try registry.renderer(id: rendererId)
      let monitor = GpuFramePacingDiagnostics.shared.monitor(rendererId: rendererId)
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
    if let orientation = view.window?.windowScene?.interfaceOrientation {
      return orientation
    }
    return .portrait
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
  static let shared = GpuFramePacingDiagnostics()
  static let channelName = "dev.pixelcraft/gpu_frame_pacing_v1"

  private let lock = NSLock()
  private var monitors: [String: GpuFramePacingMonitor] = [:]
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

  func remove(rendererId: String) {
    lock.lock()
    monitors.removeValue(forKey: rendererId)
    lock.unlock()
  }

  private func handle(call: FlutterMethodCall, result: FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    guard let rendererId = args["rendererId"] as? String, !rendererId.isEmpty else {
      result(FlutterError(
        code: "gpu_frame_pacing_invalid",
        message: "rendererId is required",
        details: nil
      ))
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

  func start() {
    lock.lock()
    defer { lock.unlock() }
    active = true
    startedAt = CACurrentMediaTime()
    lastFrameAt = nil
    frameCount = 0
    intervalsMs.removeAll(keepingCapacity: true)
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
    let average = sorted.isEmpty ? 0 : sorted.reduce(0, +) / Double(sorted.count)
    let fps: Double
    if intervalsMs.isEmpty {
      fps = 0
    } else {
      let intervalSeconds = intervalsMs.reduce(0, +) / 1000.0
      fps = intervalSeconds > 0 ? Double(intervalsMs.count) / intervalSeconds : 0
    }

    return GpuFramePacingSnapshot(
      active: active,
      elapsedSeconds: elapsed,
      frameCount: frameCount,
      fps: fps,
      averageFrameMs: average,
      p95FrameMs: percentile(sorted, 0.95),
      p99FrameMs: percentile(sorted, 0.99),
      maxFrameMs: sorted.last ?? 0,
      over40MsFrames: intervalsMs.filter { $0 > 40.0 }.count
    )
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
      "source": "mtkViewDrawCadence",
    ]
  }
}
