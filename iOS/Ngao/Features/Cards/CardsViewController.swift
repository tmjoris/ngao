import UIKit

@MainActor
final class CardsViewModel {
    private(set) var cards: [Card] = []
    private let api: BankAPI
    var onChange: (() -> Void)?

    init(api: BankAPI) { self.api = api }

    func load() async {
        cards = (try? await api.cards()) ?? []
        onChange?()
    }

    func toggle(_ card: Card) async throws {
        let updated = try await api.setFrozen(!card.frozen, card: card)
        if let index = cards.firstIndex(where: { $0.id == card.id }) { cards[index] = updated }
        onChange?()
    }
}

final class CardsViewController: UITableViewController {
    private let viewModel: CardsViewModel

    init(viewModel: CardsViewModel) {
        self.viewModel = viewModel
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Cards"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        viewModel.onChange = { [weak self] in self?.tableView.reloadData() }
        Task { await viewModel.load() }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { viewModel.cards.count }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Freezing a card blocks new purchases and ATM withdrawals instantly. Unfreeze any time."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let card = viewModel.cards[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = "\(card.brand) •••• \(card.last4)"
        content.secondaryText = card.frozen ? "Frozen" : "Active"
        content.secondaryTextProperties.color = card.frozen ? Theme.danger : Theme.green
        content.image = UIImage(systemName: card.frozen ? "snowflake" : "creditcard")
        cell.contentConfiguration = content
        let toggle = UISwitch()
        toggle.isOn = card.frozen
        toggle.accessibilityIdentifier = "freeze-\(card.id)"
        toggle.addAction(UIAction { [weak self] _ in
            Task { try? await self?.viewModel.toggle(card) }
        }, for: .valueChanged)
        cell.accessoryView = toggle
        cell.selectionStyle = .none
        return cell
    }
}
