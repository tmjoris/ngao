import Foundation
import NgaoCore

@MainActor
final class HomeViewModel {
    private(set) var accounts: [Account] = []
    private(set) var transfers: [TransferMachine] = []
    private(set) var error: String?
    var onChange: (() -> Void)?

    private let api: BankAPI
    private let outbox: Outbox

    init(api: BankAPI, outbox: Outbox) {
        self.api = api
        self.outbox = outbox
    }

    /// Reconciles the outbox before anything else: a transfer left `unknown` by a crash or
    /// a dead network is resolved before the user sees a balance that might be stale.
    func load() async {
        do {
            try await outbox.restore()
            _ = try? await outbox.reconcile()
            transfers = await outbox.all
            accounts = try await api.accounts()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        onChange?()
    }

    var hasUnresolvedTransfers: Bool {
        transfers.contains { if case .unknown = $0.state { return true }; return false }
    }
}
