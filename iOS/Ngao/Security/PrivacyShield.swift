import UIKit

/// Covers the window with an opaque view whenever the app is not active, so balances never
/// appear in the app switcher snapshot or on a screen the user has walked away from.
@MainActor
final class PrivacyShield {
    private let window: UIWindow
    private var coverView: UIView?

    init(window: UIWindow) {
        self.window = window
    }

    func cover() {
        guard coverView == nil else { return }
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
        view.frame = window.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let logo = UIImageView(image: UIImage(systemName: "shield.lefthalf.filled"))
        logo.tintColor = Theme.green
        logo.contentMode = .scaleAspectFit
        logo.translatesAutoresizingMaskIntoConstraints = false
        view.contentView.addSubview(logo)
        NSLayoutConstraint.activate([
            logo.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            logo.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            logo.widthAnchor.constraint(equalToConstant: 72),
            logo.heightAnchor.constraint(equalToConstant: 72),
        ])
        window.addSubview(view)
        coverView = view
    }

    func uncover() {
        guard let view = coverView else { return }
        coverView = nil
        UIView.animate(withDuration: 0.2, animations: { view.alpha = 0 }) { _ in view.removeFromSuperview() }
    }
}

/// Blocks screenshots and screen recording of a sensitive view by hosting it inside a
/// secure text field's layer. The system strips secure-entry content from captures.
@MainActor
enum ScreenshotGuard {
    static func protect(_ view: UIView) {
        let field = UITextField()
        field.isSecureTextEntry = true
        field.isUserInteractionEnabled = false
        guard let secureLayer = field.layer.sublayers?.first else { return }
        secureLayer.addSublayer(view.layer)
        view.layer.superlayer?.addSublayer(secureLayer)
    }
}
