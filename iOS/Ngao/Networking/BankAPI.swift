import Foundation
import NgaoCore

struct Account: Hashable, Sendable, Codable, Identifiable {
    let id: String
    let name: String
    let balanceCents: Int64
    let currency: String

    var balance: Money { Money(cents: balanceCents) }

    enum CodingKeys: String, CodingKey {
        case id, name, currency
        case balanceCents = "balance_cents"
    }
}

struct Card: Hashable, Sendable, Codable, Identifiable {
    let id: String
    let last4: String
    let brand: String
    var frozen: Bool
    let account: String
}

struct Customer: Hashable, Sendable, Codable {
    let id: String
    let name: String
}

enum BankError: LocalizedError, Sendable {
    case wrongPIN(attemptsLeft: Int)
    case locked
    case unauthenticated
    case server(String)
    case offline

    var errorDescription: String? {
        switch self {
        case .wrongPIN(let left): return left > 0 ? "Wrong PIN. \(left) attempts left." : "Wrong PIN."
        case .locked: return "Your PIN is locked. Call the bank to unlock it."
        case .unauthenticated: return "Please sign in again."
        case .server(let message): return message
        case .offline: return "No connection. Check your network and try again."
        }
    }
}

/// Everything the app asks the bank. Also the `TransferGateway` for the outbox, so transfers
/// and their reconciliation go through the one pinned session.
protocol BankAPI: TransferGateway {
    func login(pin: String) async throws -> Customer
    func loginWithRefreshToken(_ token: String) async throws -> Customer
    func clearSession()
    func accounts() async throws -> [Account]
    func cards() async throws -> [Card]
    func setFrozen(_ frozen: Bool, card: Card) async throws -> Card
}
