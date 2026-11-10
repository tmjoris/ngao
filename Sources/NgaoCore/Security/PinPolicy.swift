import Foundation

/// Rules for the login PIN. Weak PINs are the most common account takeover vector in
/// mobile money, so the client refuses the obvious ones before they reach the bank.
public enum PinPolicy {
    public static let length = 6

    public enum Weakness: Hashable, Sendable {
        case wrongLength
        case notDigits
        case repeated       // 111111
        case sequential     // 123456, 654321
        case pattern        // 121212, 123123
        case dateLike       // 1990xx / xx1990, 0101xx
    }

    public static func weaknesses(of pin: String) -> Set<Weakness> {
        var found: Set<Weakness> = []
        guard pin.count == length else { return [.wrongLength] }
        guard pin.allSatisfy(\.isNumber) else { return [.notDigits] }
        let digits = pin.compactMap { Int(String($0)) }

        if Set(digits).count == 1 { found.insert(.repeated) }

        let diffs = zip(digits.dropFirst(), digits).map { $0 - $1 }
        if diffs.allSatisfy({ $0 == 1 }) || diffs.allSatisfy({ $0 == -1 }) { found.insert(.sequential) }

        let half = Array(digits.prefix(3))
        if Array(digits.suffix(3)) == half { found.insert(.pattern) }
        if digits[0] == digits[2], digits[2] == digits[4], digits[1] == digits[3], digits[3] == digits[5] {
            found.insert(.pattern)
        }

        // Birthdays: yyyy at either end, or a plausible ddmmyy.
        let head = Int(pin.prefix(4)) ?? 0
        let tail = Int(pin.suffix(4)) ?? 0
        let day = Int(pin.prefix(2)) ?? 0
        let month = Int(pin.dropFirst(2).prefix(2)) ?? 0
        if (1930...2030).contains(head) || (1930...2030).contains(tail)
            || ((1...31).contains(day) && (1...12).contains(month)) {
            found.insert(.dateLike)
        }
        return found
    }

    public static func isAcceptable(_ pin: String) -> Bool { weaknesses(of: pin).isEmpty }
}

/// Progressive lockout after wrong PINs, computed from a count and a timestamp so it survives
/// relaunch (store both in the Keychain). Pure: no timers, trivially testable.
public struct PinLockout: Hashable, Sendable, Codable {
    public private(set) var failures: Int
    public private(set) var lastFailureAt: Date?

    public static let hardLockAfter = 5

    public init(failures: Int = 0, lastFailureAt: Date? = nil) {
        self.failures = failures
        self.lastFailureAt = lastFailureAt
    }

    /// 0, 0, 30s, 5min, 30min, then locked until the bank resets it.
    public static func delay(afterFailures failures: Int) -> TimeInterval? {
        switch failures {
        case ..<2: return 0
        case 2: return 30
        case 3: return 300
        case 4: return 1_800
        default: return nil
        }
    }

    public var isHardLocked: Bool { failures >= Self.hardLockAfter }

    /// Seconds until another attempt is allowed. 0 means now; nil means locked for good.
    public func remainingWait(now: Date) -> TimeInterval? {
        guard let delay = Self.delay(afterFailures: failures) else { return nil }
        guard let last = lastFailureAt else { return 0 }
        return max(0, delay - now.timeIntervalSince(last))
    }

    public func canAttempt(now: Date) -> Bool {
        remainingWait(now: now) == 0
    }

    public func recordingFailure(at date: Date) -> PinLockout {
        PinLockout(failures: failures + 1, lastFailureAt: date)
    }

    public func reset() -> PinLockout { PinLockout() }
}
