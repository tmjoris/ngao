import NgaoCore
import UIKit

final class HomeViewController: UITableViewController {
    private let viewModel: HomeViewModel
    var onSendMoney: ((Account) -> Void)?
    var onCards: (() -> Void)?
    var onSignOut: (() -> Void)?
    var onTransfer: ((TransferMachine) -> Void)?

    private enum Section: Int, CaseIterable { case accounts, actions, transfers }

    init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Ngao"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Sign out", primaryAction: UIAction { [weak self] _ in
            self?.onSignOut?()
        })
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "sign-out"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        refreshControl = UIRefreshControl()
        refreshControl?.addAction(UIAction { [weak self] _ in Task { await self?.reload() } }, for: .valueChanged)
        viewModel.onChange = { [weak self] in
            self?.tableView.reloadData()
            self?.refreshControl?.endRefreshing()
        }
        Task { await reload() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { await reload() }
    }

    private func reload() async {
        await viewModel.load()
        if let error = viewModel.error {
            let alert = UIAlertController(title: "Could not load", message: error, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .accounts: return "Accounts"
        case .actions: return nil
        case .transfers: return viewModel.transfers.isEmpty ? nil : "Recent transfers"
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .accounts: return viewModel.accounts.count
        case .actions: return 2
        case .transfers: return viewModel.transfers.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        cell.accessoryType = .disclosureIndicator
        switch Section(rawValue: indexPath.section)! {
        case .accounts:
            let account = viewModel.accounts[indexPath.row]
            content.text = account.name
            content.secondaryText = Masking.account(account.id)
            let amount = Theme.amount(account.balance, style: .headline)
            amount.accessibilityIdentifier = "balance-\(account.id)"
            cell.accessoryView = amount
            cell.accessoryType = .none
            cell.accessibilityIdentifier = "account-\(account.id)"
        case .actions:
            content.text = indexPath.row == 0 ? "Send money" : "Cards"
            content.image = UIImage(systemName: indexPath.row == 0 ? "paperplane.fill" : "creditcard.fill")
            content.imageProperties.tintColor = Theme.green
            cell.accessibilityIdentifier = indexPath.row == 0 ? "send-money" : "cards"
        case .transfers:
            let machine = viewModel.transfers[indexPath.row]
            content.text = machine.intent.destination.summary
            content.secondaryText = machine.intent.amount.description + " · " + statusText(machine.state)
            content.secondaryTextProperties.color = statusColor(machine.state)
            cell.accessibilityIdentifier = "transfer-\(indexPath.row)"
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .accounts: break
        case .actions:
            if indexPath.row == 0, let account = viewModel.accounts.first { onSendMoney?(account) } else { onCards?() }
        case .transfers:
            onTransfer?(viewModel.transfers[indexPath.row])
        }
    }

    private func statusText(_ state: TransferState) -> String {
        switch state {
        case .pending: return "Pending"
        case .submitted: return "Sending…"
        case .confirmed(let receipt): return "Sent · \(receipt.reference)"
        case .failed(let failure, _): return failure.isRetryable ? "Failed, can retry" : "Declined"
        case .unknown: return "Confirming with bank…"
        }
    }

    private func statusColor(_ state: TransferState) -> UIColor {
        switch state {
        case .confirmed: return Theme.green
        case .failed: return Theme.danger
        case .unknown: return Theme.gold
        default: return .secondaryLabel
        }
    }
}
