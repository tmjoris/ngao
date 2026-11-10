import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var appCoordinator: AppCoordinator?
    private var privacyShield: PrivacyShield?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let environment = AppEnvironment.live()
        let coordinator = AppCoordinator(window: window, environment: environment)
        coordinator.start()
        self.window = window
        appCoordinator = coordinator
        privacyShield = PrivacyShield(window: window)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        privacyShield?.cover()
        appCoordinator?.didEnterBackground()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        appCoordinator?.willEnterForeground()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        privacyShield?.uncover()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // App switcher snapshot is taken after this: cover balances before it happens.
        privacyShield?.cover()
    }
}
