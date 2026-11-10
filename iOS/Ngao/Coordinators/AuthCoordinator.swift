import NgaoCore
import UIKit

@MainActor
final class AuthCoordinator: Coordinator {
    var children: [Coordinator] = []
    private let navigation: UINavigationController
    private let environment: AppEnvironment
    private let message: String?
    private let onAuthenticated: () -> Void

    init(navigation: UINavigationController, environment: AppEnvironment, message: String?, onAuthenticated: @escaping () -> Void) {
        self.navigation = navigation
        self.environment = environment
        self.message = message
        self.onAuthenticated = onAuthenticated
    }

    func start() {
        let viewModel = LoginViewModel(api: environment.api, keychain: environment.keychain, biometrics: environment.biometrics)
        let controller = LoginViewController(viewModel: viewModel, message: message)
        controller.onAuthenticated = { [weak self] in self?.onAuthenticated() }
        navigation.setViewControllers([controller], animated: false)
    }
}
