import NgaoCore
import UIKit

@MainActor
final class MainCoordinator: Coordinator {
    var children: [Coordinator] = []
    private let navigation: UINavigationController
    private let environment: AppEnvironment
    private let onSignOut: () -> Void

    init(navigation: UINavigationController, environment: AppEnvironment, onSignOut: @escaping () -> Void) {
        self.navigation = navigation
        self.environment = environment
        self.onSignOut = onSignOut
    }

    func start() {
        let viewModel = HomeViewModel(api: environment.api, outbox: environment.outbox)
        let home = HomeViewController(viewModel: viewModel)
        home.onSendMoney = { [weak self] account in self?.showSendMoney(from: account) }
        home.onCards = { [weak self] in self?.showCards() }
        home.onSignOut = { [weak self] in self?.onSignOut() }
        home.onTransfer = { [weak self] machine in self?.showStatus(for: machine) }
        navigation.setViewControllers([home], animated: false)
    }

    private func showSendMoney(from account: Account) {
        let viewModel = SendMoneyViewModel(account: account, outbox: environment.outbox, limits: environment.limits)
        let controller = SendMoneyViewController(viewModel: viewModel)
        controller.onSubmitted = { [weak self] machine in
            self?.navigation.popToRootViewController(animated: false)
            self?.showStatus(for: machine)
        }
        navigation.pushViewController(controller, animated: true)
    }

    private func showStatus(for machine: TransferMachine) {
        let controller = TransferStatusViewController(machine: machine, outbox: environment.outbox)
        controller.onDone = { [weak self] in self?.navigation.popToRootViewController(animated: true) }
        navigation.pushViewController(controller, animated: true)
    }

    private func showCards() {
        let controller = CardsViewController(viewModel: CardsViewModel(api: environment.api))
        navigation.pushViewController(controller, animated: true)
    }
}
