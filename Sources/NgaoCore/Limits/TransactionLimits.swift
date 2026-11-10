import Foundation

/// Per-transaction and daily caps, the kind the Central Bank of Kenya and the bank's own
/// risk team set. Checked on the phone for fast feedback; the bank checks again.
public struct TransactionLimits: Hashable, Sendable, Codable {
    public let perTransaction: Money
    public let daily: Money
    public let timeZoneIdentifier: String

    public init(perTransaction: Money, daily: Money, timeZoneIdentifier: String = "Africa/Nairobi") {
        self.perTransaction = perTransaction
        self.daily = daily
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    /// Typical retail mobile limits in Kenya.
    public static let retail = TransactionLimits(perTransaction: .kes(250_000), daily: .kes(1_000_000))

    public enum Breach: Hashable, Sendable {
        case perTransaction(limit: Money)
        case daily(limit: Money, usedToday: Money)
    }

    /// Transfers that count against today: anything that may have debited, not just confirmed.
    /// Counting `unknown` is deliberate; the alternative lets a flaky network bypass the cap.
    public func usedToday(_ machines: [TransferMachine], now: Date) -> Money {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        return machines
            .filter { $0.state.mayHaveDebited && calendar.isDate($0.intent.createdAt, inSameDayAs: now) }
            .map(\.intent.amount)
            .reduce(.zero, +)
    }

    public func check(_ amount: Money, against machines: [TransferMachine], now: Date) -> Breach? {
        if amount > perTransaction { return .perTransaction(limit: perTransaction) }
        let used = usedToday(machines, now: now)
        if used + amount > daily { return .daily(limit: daily, usedToday: used) }
        return nil
    }
}
