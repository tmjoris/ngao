import Foundation

/// When a signed-in session stops being trusted. Values are the ones banks in Kenya use.
public struct SessionPolicy: Hashable, Sendable {
    /// No touches for this long and the session ends.
    public let inactivityTimeout: TimeInterval
    /// In the background for longer than this and the user must re-authenticate.
    public let backgroundGrace: TimeInterval
    /// Absolute cap regardless of activity.
    public let maxLifetime: TimeInterval

    public init(inactivityTimeout: TimeInterval = 120, backgroundGrace: TimeInterval = 30, maxLifetime: TimeInterval = 900) {
        self.inactivityTimeout = inactivityTimeout
        self.backgroundGrace = backgroundGrace
        self.maxLifetime = maxLifetime
    }

    public static let banking = SessionPolicy()
}

public struct Session: Hashable, Sendable {
    public let startedAt: Date
    public private(set) var lastActivityAt: Date
    public private(set) var backgroundedAt: Date?
    public let policy: SessionPolicy

    public init(startedAt: Date, policy: SessionPolicy = .banking) {
        self.startedAt = startedAt
        self.lastActivityAt = startedAt
        self.policy = policy
    }

    public enum Expiry: Hashable, Sendable {
        case inactivity, background, lifetime
    }

    public func expiry(now: Date) -> Expiry? {
        if now.timeIntervalSince(startedAt) > policy.maxLifetime { return .lifetime }
        if let backgroundedAt, now.timeIntervalSince(backgroundedAt) > policy.backgroundGrace { return .background }
        if now.timeIntervalSince(lastActivityAt) > policy.inactivityTimeout { return .inactivity }
        return nil
    }

    public func isValid(now: Date) -> Bool { expiry(now: now) == nil }

    public func touched(at date: Date) -> Session {
        var copy = self
        copy.lastActivityAt = date
        return copy
    }

    public func backgrounded(at date: Date) -> Session {
        var copy = self
        copy.backgroundedAt = date
        return copy
    }

    /// Returns nil if the session died while in the background.
    public func foregrounded(at date: Date) -> Session? {
        guard isValid(now: date) else { return nil }
        var copy = self
        copy.backgroundedAt = nil
        copy.lastActivityAt = date
        return copy
    }
}
