import Foundation

/// Where money goes. Mirrors what a Kenyan bank app offers on its "Send money" screen.
public enum Destination: Hashable, Sendable, Codable {
    /// Another account at the same bank.
    case ownBank(accountNumber: String)
    /// Send to M-Pesa (B2C).
    case mpesa(phone: String)
    /// Lipa na M-Pesa paybill with account reference (rent, school fees, utilities).
    case paybill(businessNumber: String, account: String)
    /// Buy goods till number.
    case till(number: String)
    /// Pesalink to another Kenyan bank.
    case pesalink(bankCode: String, accountNumber: String)

    /// Short label for lists and receipts, with sensitive digits masked.
    public var summary: String {
        switch self {
        case .ownBank(let account): return "Account \(Masking.account(account))"
        case .mpesa(let phone): return "M-Pesa \(Masking.phone(phone))"
        case .paybill(let business, let account): return "Paybill \(business) · \(account)"
        case .till(let number): return "Till \(number)"
        case .pesalink(let bank, let account): return "Pesalink \(bank) · \(Masking.account(account))"
        }
    }
}

/// The user's decision to move money, fixed at the moment they confirm. Its `id` doubles as
/// the idempotency key: every retry of this intent sends the same key, so the bank can
/// recognise a replay and return the original result instead of debiting again.
public struct TransferIntent: Hashable, Sendable, Codable, Identifiable {
    public let id: IdempotencyKey
    public let sourceAccount: String
    public let destination: Destination
    public let amount: Money
    public let narration: String
    public let createdAt: Date

    public init(id: IdempotencyKey = IdempotencyKey(), sourceAccount: String, destination: Destination,
                amount: Money, narration: String, createdAt: Date = Date()) {
        self.id = id
        self.sourceAccount = sourceAccount
        self.destination = destination
        self.amount = amount
        self.narration = narration
        self.createdAt = createdAt
    }
}

/// Client-generated, globally unique, created once per intent and never per attempt.
public struct IdempotencyKey: Hashable, Sendable, Codable, CustomStringConvertible {
    public let value: String

    public init() { value = UUID().uuidString.lowercased() }
    public init?(_ value: String) {
        guard UUID(uuidString: value) != nil else { return nil }
        self.value = value.lowercased()
    }

    public var description: String { value }
}

public struct Receipt: Hashable, Sendable, Codable {
    public let reference: String
    public let amount: Money
    public let charge: Money
    public let completedAt: Date
    public let destination: Destination

    public init(reference: String, amount: Money, charge: Money, completedAt: Date, destination: Destination) {
        self.reference = reference
        self.amount = amount
        self.charge = charge
        self.completedAt = completedAt
        self.destination = destination
    }
}

public enum Masking {
    /// "1234567890" -> "•••• 7890"
    public static func account(_ number: String) -> String {
        guard number.count > 4 else { return number }
        return "•••• " + number.suffix(4)
    }

    /// "254712345678" -> "0712 ••• 678"
    public static func phone(_ msisdn: String) -> String {
        let digits = msisdn.filter(\.isNumber)
        guard digits.count >= 9 else { return msisdn }
        let local = digits.suffix(9)
        return "0" + local.prefix(3) + " ••• " + local.suffix(3)
    }
}
