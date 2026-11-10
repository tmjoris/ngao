import NgaoCore
import UIKit

final class SendMoneyViewController: UIViewController {
    private let viewModel: SendMoneyViewModel
    var onSubmitted: ((TransferMachine) -> Void)?

    private let kindControl = UISegmentedControl(items: SendMoneyViewModel.Kind.allCases.map(\.title))
    private let primaryField = Theme.field("Phone number", keyboard: .phonePad)
    private let secondaryField = Theme.field("Account reference")
    private let amountField = Theme.field("Amount (KES)", keyboard: .numberPad)
    private let narrationField = Theme.field("Reason (optional)")
    private let hintLabel = Theme.body("")
    private let continueButton = Theme.primaryButton("Continue")
    private var history: [TransferMachine] = []

    init(viewModel: SendMoneyViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Send money"
        view.backgroundColor = .systemBackground

        let from = Theme.body("From \(viewModel.account.name) · \(viewModel.account.balance)")
        kindControl.selectedSegmentIndex = 0
        kindControl.accessibilityIdentifier = "destination-kind"
        kindControl.addAction(UIAction { [weak self] _ in self?.kindChanged() }, for: .valueChanged)

        primaryField.accessibilityIdentifier = "destination-primary"
        secondaryField.accessibilityIdentifier = "destination-secondary"
        amountField.accessibilityIdentifier = "amount"
        narrationField.accessibilityIdentifier = "narration"
        hintLabel.accessibilityIdentifier = "send-hint"
        hintLabel.font = .preferredFont(forTextStyle: .footnote)
        continueButton.accessibilityIdentifier = "continue"
        continueButton.addAction(UIAction { [weak self] _ in self?.confirm() }, for: .touchUpInside)
        [primaryField, secondaryField, amountField, narrationField].forEach {
            $0.addAction(UIAction { [weak self] _ in self?.validate() }, for: .editingChanged)
        }

        let stack = UIStackView.vertical(spacing: 14, [from, kindControl, primaryField, secondaryField, amountField, narrationField, hintLabel, continueButton])
        view.addSubview(stack)
        stack.pin(to: view.safeAreaLayoutGuide)
        kindChanged()
        Task {
            history = await viewModel.history()
            validate()
        }
    }

    private func kindChanged() {
        viewModel.kind = SendMoneyViewModel.Kind(rawValue: kindControl.selectedSegmentIndex) ?? .mpesa
        switch viewModel.kind {
        case .mpesa: primaryField.placeholder = "Phone number"; primaryField.keyboardType = .phonePad
        case .paybill: primaryField.placeholder = "Business number"; primaryField.keyboardType = .numberPad
        case .till: primaryField.placeholder = "Till number"; primaryField.keyboardType = .numberPad
        case .ownBank: primaryField.placeholder = "Account number"; primaryField.keyboardType = .numberPad
        }
        secondaryField.isHidden = viewModel.kind != .paybill
        primaryField.reloadInputViews()
        validate()
    }

    private func validate() {
        viewModel.primaryField = primaryField.text ?? ""
        viewModel.secondaryField = secondaryField.text ?? ""
        viewModel.amountText = amountField.text ?? ""
        viewModel.narration = narrationField.text ?? ""
        let message = viewModel.validationMessage(history: history)
        hintLabel.text = message ?? "Charges: M-Pesa KES 33, Paybill KES 23, Pesalink KES 55."
        hintLabel.textColor = message == nil ? .secondaryLabel : Theme.danger
        continueButton.isEnabled = message == nil
    }

    private func confirm() {
        guard let intent = viewModel.makeIntent() else { return }
        let sheet = UIAlertController(
            title: "Confirm transfer",
            message: "\(intent.amount) to \(intent.destination.summary)\nfrom \(Masking.account(intent.sourceAccount))",
            preferredStyle: .alert)
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        let send = UIAlertAction(title: "Send", style: .default) { [weak self] _ in self?.send(intent) }
        send.accessibilityIdentifier = "confirm-send"
        sheet.addAction(send)
        present(sheet, animated: true)
    }

    private func send(_ intent: TransferIntent) {
        continueButton.isEnabled = false
        continueButton.configuration?.showsActivityIndicator = true
        Task {
            do {
                let machine = try await viewModel.submit(intent)
                onSubmitted?(machine)
            } catch {
                continueButton.configuration?.showsActivityIndicator = false
                hintLabel.text = error.localizedDescription
                hintLabel.textColor = Theme.danger
                validate()
            }
        }
    }
}
