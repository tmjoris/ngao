import Foundation
import NgaoCore

/// In-process bank for UI tests and previews. PIN 739142. Transfers to a phone ending in
/// 99 lose their response after committing, so the UI test can exercise the unknown state.
actor ScriptedBankAPI: BankAPI {
    private var signedIn = false
    private var balance = Money.kes(184_520)
    private var cardsStore = [Card(id: "card-1", last4: "4521", brand: "Visa", frozen: false, account: "0110012345678")]
    private var ledger: [IdempotencyKey: Receipt] = [:]

    init() {}

    func login(pin: String) async throws -> Customer {
        try await Task.sleep(for: .milliseconds(200))
        guard pin == "739142" else { throw BankError.wrongPIN(attemptsLeft: 4) }
        signedIn = true
        return Customer(id: "cust-1", name: "Wanjiru Kamau")
    }

    func loginWithRefreshToken(_ token: String) async throws -> Customer {
        signedIn = true
        return Customer(id: "cust-1", name: "Wanjiru Kamau")
    }

    nonisolated func clearSession() {
        Task { await self.signOut() }
    }

    private func signOut() { signedIn = false }

    func accounts() async throws -> [Account] {
        guard signedIn else { throw BankError.unauthenticated }
        return [Account(id: "0110012345678", name: "Current account", balanceCents: balance.cents, currency: "KES"),
                Account(id: "0110098765432", name: "Savings", balanceCents: 125_000_000, currency: "KES")]
    }

    func cards() async throws -> [Card] { cardsStore }

    func setFrozen(_ frozen: Bool, card: Card) async throws -> Card {
        guard let index = cardsStore.firstIndex(where: { $0.id == card.id }) else { throw BankError.server("unknown card") }
        cardsStore[index].frozen = frozen
        return cardsStore[index]
    }

    func send(_ intent: TransferIntent, attempt: Int) async -> SendResult {
        try? await Task.sleep(for: .milliseconds(300))
        if let existing = ledger[intent.id] { return .response(.confirmed(existing)) }
        if intent.amount > balance {
            return .response(.failed(TransferFailure(code: "INSUFFICIENT_FUNDS", message: "Insufficient funds", isRetryable: false)))
        }
        let receipt = Receipt(reference: "FT\(ledger.count + 1)TEST", amount: intent.amount, charge: .kes(33),
                              completedAt: Date(), destination: intent.destination)
        ledger[intent.id] = receipt
        balance = balance - intent.amount - receipt.charge
        if case .mpesa(let phone) = intent.destination, phone.hasSuffix("99") { return .noResponse }
        return .response(.confirmed(receipt))
    }

    func status(of key: IdempotencyKey) async throws -> TransferMachine.ReconcileOutcome {
        if let receipt = ledger[key] { return .confirmed(receipt) }
        return .neverReceived
    }
}
