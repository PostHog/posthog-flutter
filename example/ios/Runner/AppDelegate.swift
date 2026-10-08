import UIKit
import Flutter
import UserNotifications
import MapKit
import MetalKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  // Notification taps only reach the app through a UNUserNotificationCenter delegate; without this
  // the SDK has nothing to observe and never captures $push_notification_opened.
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private var ownWindow: UIWindow?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "Spike593NativeViews") {
      registrar.register(Spike593Factory(), withId: "spike593/native_view")
    }

    let channel = FlutterMethodChannel(
      name: "posthog_flutter_example",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )

    channel.setMethodCallHandler { (call, result) in
      if call.method == "triggerNativeCrash" {
        NativeCrashHelper().triggerCrash()
      } else if call.method == "presentNativeScreen" {
        let captured = (call.arguments as? [String: Any])?["capture"] as? Bool ?? true
        self.presentNativeScreen(captured: captured)
        result(nil)
      } else if call.method == "presentNativeScreenOwnWindow" {
        self.presentNativeScreenOwnWindow()
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func makePaywallViewController(
    captured: Bool = true,
    dismiss: @escaping (UIViewController) -> Void
  ) -> UIViewController {
    let vc = UIViewController()
    vc.modalPresentationStyle = .fullScreen
    vc.view.backgroundColor = captured ? .systemIndigo : .systemOrange
    let onDismiss: () -> Void = { [weak vc] in if let vc { dismiss(vc) } }
    addPaywall(to: vc.view, dismiss: onDismiss)
    vc.view.addGestureRecognizer(DismissTapRecognizer(onTap: onDismiss))
    return vc
  }

  private func presentNativeScreen(captured: Bool) {
    DispatchQueue.main.async {
      guard let root = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .flatMap({ $0.windows })
        .first(where: { $0.isKeyWindow })?.rootViewController else { return }

      let vc = self.makePaywallViewController(captured: captured) { $0.dismiss(animated: true) }
      root.present(vc, animated: true)
    }
  }

  private func addPaywall(to container: UIView, dismiss: @escaping () -> Void) {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 10
    stack.translatesAutoresizingMaskIntoConstraints = false

    func label(_ text: String, size: CGFloat, weight: UIFont.Weight, alpha: CGFloat = 1) -> UILabel {
      let l = UILabel()
      l.text = text
      l.textColor = UIColor.white.withAlphaComponent(alpha)
      l.font = .systemFont(ofSize: size, weight: weight)
      l.textAlignment = .center
      l.numberOfLines = 0
      return l
    }

    let hero = UIImageView(image: Self.makeHeroImage())
    hero.translatesAutoresizingMaskIntoConstraints = false
    hero.widthAnchor.constraint(equalToConstant: 240).isActive = true
    hero.heightAnchor.constraint(equalToConstant: 120).isActive = true
    hero.layer.cornerRadius = 14
    hero.clipsToBounds = true

    let subscribe = UIButton(type: .system, primaryAction: UIAction(title: "Subscribe") { _ in dismiss() })
    subscribe.setTitleColor(.systemIndigo, for: .normal)
    subscribe.backgroundColor = .white
    subscribe.titleLabel?.font = .boldSystemFont(ofSize: 18)
    subscribe.contentEdgeInsets = UIEdgeInsets(top: 12, left: 48, bottom: 12, right: 48)
    subscribe.layer.cornerRadius = 24

    let restore = UIButton(type: .system, primaryAction: UIAction(title: "Restore purchases") { _ in dismiss() })
    restore.setTitleColor(UIColor.white.withAlphaComponent(0.85), for: .normal)

    stack.addArrangedSubview(hero)
    stack.setCustomSpacing(22, after: hero)
    stack.addArrangedSubview(label("Unlock Premium", size: 28, weight: .bold))
    stack.addArrangedSubview(label("Get the most out of your app", size: 15, weight: .regular, alpha: 0.85))
    stack.setCustomSpacing(22, after: stack.arrangedSubviews.last!)
    stack.addArrangedSubview(label("✓  Unlimited session replays", size: 16, weight: .medium))
    stack.addArrangedSubview(label("✓  Priority support", size: 16, weight: .medium))
    stack.addArrangedSubview(label("✓  Advanced analytics", size: 16, weight: .medium))
    stack.setCustomSpacing(22, after: stack.arrangedSubviews.last!)
    stack.addArrangedSubview(label("$9.99 / month", size: 24, weight: .heavy))
    stack.setCustomSpacing(18, after: stack.arrangedSubviews.last!)
    stack.addArrangedSubview(subscribe)
    stack.addArrangedSubview(restore)
    stack.setCustomSpacing(16, after: restore)
    stack.addArrangedSubview(label("Cancel anytime · Terms apply", size: 12, weight: .regular, alpha: 0.6))

    container.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
      stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32),
    ])
  }

  private static func makeHeroImage() -> UIImage {
    let size = CGSize(width: 240, height: 120)
    return UIGraphicsImageRenderer(size: size).image { ctx in
      let cg = ctx.cgContext
      let colors = [UIColor.systemPink.cgColor, UIColor.systemOrange.cgColor] as CFArray
      let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
      cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
      UIColor.white.setFill()
      cg.fillEllipse(in: CGRect(x: 96, y: 36, width: 48, height: 48))
    }
  }

  private func presentNativeScreenOwnWindow() {
    DispatchQueue.main.async {
      guard let windowScene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first(where: { $0.activationState == .foregroundActive })
      else { return }

      let window = UIWindow(windowScene: windowScene)
      window.rootViewController = UIViewController()
      self.ownWindow = window
      window.makeKeyAndVisible()

      let vc = self.makePaywallViewController { [weak self] presented in
        presented.dismiss(animated: true) {
          self?.ownWindow?.isHidden = true
          self?.ownWindow = nil
        }
      }
      window.rootViewController?.present(vc, animated: true)
    }
  }
}

final class DismissTapRecognizer: UITapGestureRecognizer {
  private let onTap: () -> Void

  init(onTap: @escaping () -> Void) {
    self.onTap = onTap
    super.init(target: nil, action: nil)
    addTarget(self, action: #selector(handleTap))
  }

  @objc private func handleTap() {
    onTap()
  }
}

// SPIKE (#593): native platform views for iOS replay capture experiments.
final class Spike593Factory: NSObject, FlutterPlatformViewFactory {
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    let kind = (args as? [String: Any])?["kind"] as? String ?? "uikit"
    return Spike593PlatformView(kind: kind)
  }
}

final class Spike593PlatformView: NSObject, FlutterPlatformView {
  private let root: UIView
  private var renderer: Spike593MetalRenderer?

  init(kind: String) {
    switch kind {
    case "mapkit":
      let map = MKMapView()
      map.setRegion(
        MKCoordinateRegion(
          center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
          latitudinalMeters: 8000, longitudinalMeters: 8000),
        animated: false)
      root = map
    case "metal", "metal_fbo_false":
      let mtk = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
      mtk.framebufferOnly = kind == "metal"
      let r = Spike593MetalRenderer(view: mtk)
      mtk.delegate = r
      renderer = r
      root = mtk
    case "secret":
      let v = UIView()
      v.backgroundColor = .systemRed
      let l = UILabel()
      l.text = "SECRET"
      l.font = .boldSystemFont(ofSize: 40)
      l.textColor = .white
      l.translatesAutoresizingMaskIntoConstraints = false
      v.addSubview(l)
      l.centerXAnchor.constraint(equalTo: v.centerXAnchor).isActive = true
      l.centerYAnchor.constraint(equalTo: v.centerYAnchor).isActive = true
      root = v
    default:
      let v = UIView()
      v.backgroundColor = .systemTeal
      let l = UILabel()
      l.text = "UIKIT VIEW"
      l.font = .boldSystemFont(ofSize: 32)
      l.textColor = .black
      l.translatesAutoresizingMaskIntoConstraints = false
      v.addSubview(l)
      l.centerXAnchor.constraint(equalTo: v.centerXAnchor).isActive = true
      l.centerYAnchor.constraint(equalTo: v.centerYAnchor).isActive = true
      root = v
    }
    super.init()
  }

  func view() -> UIView { root }
}

/// Draws four coloured quadrants plus a moving white bar, so a blank or
/// frozen capture is easy to tell apart from a real one.
final class Spike593MetalRenderer: NSObject, MTKViewDelegate {
  private let queue: MTLCommandQueue
  private let pipeline: MTLRenderPipelineState
  private let start = CACurrentMediaTime()

  init?(view: MTKView) {
    guard let device = view.device, let queue = device.makeCommandQueue() else { return nil }
    let src = """
    #include <metal_stdlib>
    using namespace metal;
    struct V { float4 pos [[position]]; float2 uv; };
    vertex V vmain(uint vid [[vertex_id]]) {
      float2 p = float2((vid << 1) & 2, vid & 2);
      V o; o.pos = float4(p * 2.0 - 1.0, 0, 1); o.uv = float2(p.x, 1.0 - p.y); return o;
    }
    fragment float4 fmain(V in [[stage_in]], constant float &t [[buffer(0)]]) {
      if (abs(in.uv.x - fract(t * 0.25)) < 0.03) return float4(1, 1, 1, 1);
      bool r = in.uv.x > 0.5; bool b = in.uv.y > 0.5;
      if (!r && !b) return float4(1, 0, 0, 1);
      if (r && !b) return float4(0, 0, 1, 1);
      if (!r && b) return float4(1, 1, 0, 1);
      return float4(1, 0, 1, 1);
    }
    """
    guard let lib = try? device.makeLibrary(source: src, options: nil) else { return nil }
    let desc = MTLRenderPipelineDescriptor()
    desc.vertexFunction = lib.makeFunction(name: "vmain")
    desc.fragmentFunction = lib.makeFunction(name: "fmain")
    desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
    guard let pipeline = try? device.makeRenderPipelineState(descriptor: desc) else { return nil }
    self.queue = queue
    self.pipeline = pipeline
  }

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

  func draw(in view: MTKView) {
    guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
          let cmd = queue.makeCommandBuffer(),
          let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
    var t = Float(CACurrentMediaTime() - start)
    enc.setRenderPipelineState(pipeline)
    enc.setFragmentBytes(&t, length: MemoryLayout<Float>.size, index: 0)
    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    enc.endEncoding()
    cmd.present(drawable)
    cmd.commit()
  }
}
