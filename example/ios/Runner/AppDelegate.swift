import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  private var ownWindow: UIWindow?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

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
