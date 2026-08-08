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
    } catch {
      // The Dart control plane receives renderer failures through the channel.
    }
  }

  func view() -> UIView {
    metalView
  }

  deinit {
    registry.detach(id: rendererId, view: metalView)
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
