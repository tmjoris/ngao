import Foundation
import NgaoCore

@MainActor
final class SendMoneyViewModel {
    enum Kind: Int, CaseIterable {
        case mpesa, paybill, till, ownBank
        var title: String {
            switch self {
            case .mpesa: return "M-Pesa"
            case .paybill: return "Paybill"
            case .till: return "Till"
            case .ownBank: return "Co-op account"
            }
        }
    }

    let account: Account
    private let outbox: Outbox
    private let limits: TransactionLimits

    var kind: Kind = .mpesa
    var primaryField = ""     // phone, business number, till, account
    var secondaryField = ""   // paybill account reference
    var amountText = ""
    var narration = ""

    init(account: Account, outbox: Outbox, limits: TransactionLimits) {
        self.account = account
        self.outbox = outbox
        self.limits = limits
    }

    var amount: Money? { Money(parsing: amountText) }

    var destination: Destination? {
        let primary = primaryField.trimmingCharacters(in: .whitespaces)
        guard !primary.isEmpty else { return nil }
        switch kind {
        case .mpesa:
            let digits = primary.filter(\.isNumber)
            guard digits.count >= 9 else { return nil }
            let normalised = digits.hasPrefix("0") ? "254" + digits.dropFirst() : digits
            return .mpesa(phone: normalised)
        case .paybill:
            let reference = secondaryField.trimmingCharacters(in: .whitespaces)
            guard !reference.isEmpty else { return nil }
            return .paybill(businessNumber: primary, account: reference)
        case .till:
            return .till(number: primary)
        case .ownBank:
            guard primary.count >= 10 else { return nil }
            return .ownBank(accountNumber: primary)
        }
    }

    /// Why the Continue button is disabled, or nil when the form is valid.
    func validationMessage(history: [TransferMachine]) -> String? {
        guard destination != nil else { return "Enter a valid \(kind.title) destination." }
        guard let amount else { return "Enter an amount." }
        guard amount.isPositive else { return "Amount must be more than zero." }
        guard amount.isWholeShillings else { return "Whole shillings only." }
        if amount + .kes(33) > account.balance { return "Insufficient funds (charges apply)." }
        if let breach = limits.check(amount, against: history, now: Date()) {
            switch breach {
            case .perTransaction(let limit): return "Maximum \(limit) per transaction."
            case .daily(let limit, let used): return "Daily limit \(limit); \(used) already used today."
            }
        }
        return nil
    }

    func makeIntent() -> TransferIntent? {
        guard let destination, let amount else { return nil }
        return TransferIntent(sourceAccount: account.id, destination: destination, amount: amount,
                              narration: narration.isEmpty ? kind.title : narration)
    }

    func history() async -> [TransferMachine] { await outbox.all }

    func submit(_ intent: TransferIntent) async throws -> TransferMachine {
        try await outbox.submit(intent)
    }
}
