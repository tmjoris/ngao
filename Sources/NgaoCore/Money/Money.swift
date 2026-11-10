import Foundation

/// Exact money in minor units. Ngao is a KES-only banking client, so the type is
/// deliberately smaller than a multi-currency one: one integer, formatted for Kenya.
public struct Money: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    /// Cents. KES 1,250.50 is 125050.
    public let cents: Int64

    public init(cents: Int64) { self.cents = cents }

    public static func kes(_ shillings: Int64, cents: Int64 = 0) -> Money {
        precondition((0..<100).contains(cents))
        return Money(cents: shillings * 100 + (shillings < 0 ? -cents : cents))
    }

    public static let zero = Money(cents: 0)

    public var shillings: Int64 { cents / 100 }
    public var isPositive: Bool { cents > 0 }
    public var isNegative: Bool { cents < 0 }
    public var isWholeShillings: Bool { cents % 100 == 0 }

    public static func + (lhs: Money, rhs: Money) -> Money { Money(cents: lhs.cents + rhs.cents) }
    public static func - (lhs: Money, rhs: Money) -> Money { Money(cents: lhs.cents - rhs.cents) }
    public static func < (lhs: Money, rhs: Money) -> Bool { lhs.cents < rhs.cents }

    /// "KES 1,250.50"
    public var description: String { "KES " + formatted }

    /// "1,250.50", locale independent so screenshots and tests never drift.
    public var formatted: String {
        let sign = cents < 0 ? "-" : ""
        let magnitude = abs(cents)
        var whole = Array(String(magnitude / 100))
        var grouped: [Character] = []
        var count = 0
        while let digit = whole.popLast() {
            if count > 0 && count % 3 == 0 { grouped.append(",") }
            grouped.append(digit)
            count += 1
        }
        let fraction = String(magnitude % 100)
        return sign + String(grouped.reversed()) + "." + (fraction.count == 1 ? "0" + fraction : fraction)
    }

    /// Parses "1,250.50", "1250", "KES 300". Rejects more than two decimals.
    public init?(parsing text: String) {
        var cleaned = text.uppercased().replacingOccurrences(of: "KES", with: "")
            .replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        var negative = false
        if cleaned.hasPrefix("-") { negative = true; cleaned.removeFirst() }
        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }
        guard let whole = Int64(parts[0].isEmpty ? "0" : String(parts[0])) else { return nil }
        var fraction: Int64 = 0
        if parts.count == 2 {
            guard parts[1].count <= 2 else { return nil }
            fraction = Int64(String(parts[1]) + (parts[1].count == 1 ? "0" : "")) ?? 0
        }
        let total = whole * 100 + fraction
        self.init(cents: negative ? -total : total)
    }
}
