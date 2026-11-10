import NgaoCore
import UIKit

/// Owns the window and the session. Decides between the locked and unlocked worlds.
@MainActor
final class AppCoordinator: Coordinator {
    var children: [Coordinator] = []
    private let window: UIWindow
    private let environment: AppEnvironment
    private var session: Session?
    private var inactivityTimer: Timer?

    init(window: UIWindow, environment: AppEnvironment) {
        self.window = window
        self.environment = environment
    }

    func start() {
        window.makeKeyAndVisible()
        if environment.integrity.isCompromised {
            showCompromised()
        } else {
            showLogin()
        }
    }

    // MARK: - Session lifecycle

    func didEnterBackground() {
        session = session?.backgrounded(at: Date())
    }

    func willEnterForeground() {
        guard let current = session else { return }
        if let revived = current.foregrounded(at: Date()) {
            session = revived
        } else {
            lock(reason: "You were away for a while. Sign in again.")
        }
    }

    private func startSession() {
        session = Session(startedAt: Date())
        inactivityTimer?.invalidate()
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkSession() }
        }
    }

    private func checkSession() {
        guard let current = session else { return }
        if let expiry = current.expiry(now: Date()) {
            let reason: String
            switch expiry {
            case .inactivity: reason = "Signed out after 2 minutes of inactivity."
            case .background: reason = "You were away for a while. Sign in again."
            case .lifetime: reason = "Session expired. Sign in again."
            }
            lock(reason: reason)
        }
    }

    /// Any user interaction extends the session. Called by `TouchTrackingWindow`-style hooks
    /// or, as here, from the main navigation controller's delegate.
    func userDidInteract() {
        session = session?.touched(at: Date())
    }

    private func lock(reason: String?) {
        inactivityTimer?.invalidate()
        session = nil
        environment.api.clearSession()
        children.removeAll()
        showLogin(message: reason)
    }

    // MARK: - Flows

    private func showLogin(message: String? = nil) {
        let navigation = UINavigationController()
        navigation.setNavigationBarHidden(true, animated: false)
        let auth = AuthCoordinator(navigation: navigation, environment: environment, message: message) { [weak self] in
            self?.showMain()
        }
        add(auth)
        auth.start()
        transition(to: navigation)
    }

    private func showMain() {
        children.removeAll()
        startSession()
        let navigation = InteractionTrackingNavigationController()
        navigation.onInteraction = { [weak self] in self?.userDidInteract() }
        let main = MainCoordinator(navigation: navigation, environment: environment) { [weak self] in
            self?.lock(reason: nil)
        }
        add(main)
        main.start()
        transition(to: navigation)
    }

    private func showCompromised() {
        let controller = MessageViewController(
            title: "Device not supported",
            message: "This device appears to be jailbroken. For your safety Ngao will not run here.\n\n"
                + environment.integrity.signals.joined(separator: "\n"),
            symbol: "exclamationmark.shield.fill")
        transition(to: controller)
    }

    private func transition(to root: UIViewController) {
        guard window.rootViewController != nil else {
            window.rootViewController = root
            return
        }
        UIView.transition(with: window, duration: 0.25, options: .transitionCrossDissolve) {
            self.window.rootViewController = root
        }
    }
}

/// Reports touches so the session timeout is measured from real activity.
final class InteractionTrackingNavigationController: UINavigationController {
    var onInteraction: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        onInteraction?()
    }

    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        super.pushViewController(viewController, animated: animated)
        onInteraction?()
    }
}
