import Foundation

/// Why a transfer failed, and whether sending the same intent again could succeed.
public struct TransferFailure: Hashable, Sendable, Codable {
    public let code: String
    public let message: String
    /// True for transient problems (bank timeout, downstream busy). False for insufficient
    /// funds, limits, blocked account, invalid destination.
    public let isRetryable: Bool

    public init(code: String, message: String, isRetryable: Bool) {
        self.code = code
        self.message = message
        self.isRetryable = isRetryable
    }
}

/// Where a transfer is. The dangerous state is `unknown`: the request left the phone and
/// nothing came back. The money may or may not have moved. Treating that as `failed` and
/// letting the user tap again is how apps double-charge.
public enum TransferState: Hashable, Sendable, Codable {
    /// Confirmed by the user and written to the outbox. Nothing sent yet.
    case pending
    /// Request in flight for attempt `attempt`.
    case submitted(attempt: Int, at: Date)
    /// Bank acknowledged the debit.
    case confirmed(Receipt)
    /// Bank refused. Retry allowed only if the failure says so, and with the same key.
    case failed(TransferFailure, attempt: Int)
    /// Sent, no answer. Must be reconciled with the bank before anything else happens.
    case unknown(attempt: Int, since: Date)

    public var isTerminal: Bool {
        switch self {
        case .confirmed: return true
        case .failed(let failure, _): return !failure.isRetryable
        case .pending, .submitted, .unknown: return false
        }
    }

    /// Money may have left the account: block the UI from offering "send again".
    public var mayHaveDebited: Bool {
        switch self {
        case .submitted, .unknown, .confirmed: return true
        case .pending, .failed: return false
        }
    }

    public var attempt: Int {
        switch self {
        case .pending: return 0
        case .submitted(let attempt, _), .failed(_, let attempt), .unknown(let attempt, _): return attempt
        case .confirmed: return 0
        }
    }
}

public enum TransferError: Error, Hashable, Sendable {
    case invalidTransition(from: String, on: String)
    case tooManyAttempts(max: Int)
    case exceedsLimit(TransactionLimits.Breach)
    case notWholeShillings
    case nonPositiveAmount
}

/// Pure transition function for one transfer. No I/O, fully unit tested, drives both the
/// outbox and the UI. Every transition is a value in, value out.
public struct TransferMachine: Hashable, Sendable, Codable {
    public let intent: TransferIntent
    public private(set) var state: TransferState
    public private(set) var history: [TransferState]

    public static let maxAttempts = 3

    public init(intent: TransferIntent) {
        self.intent = intent
        state = .pending
        history = [.pending]
    }

    /// The outbox is about to put the request on the wire. Allowed from `pending` and from a
    /// retryable `failed`; never from `submitted` or `unknown`, where a debit may have happened.
    public func sending(at date: Date) throws -> TransferMachine {
        let next: Int
        switch state {
        case .pending:
            next = 1
        case .failed(let failure, let attempt) where failure.isRetryable:
            next = attempt + 1
        default:
            throw TransferError.invalidTransition(from: label, on: "send")
        }
        guard next <= Self.maxAttempts else { throw TransferError.tooManyAttempts(max: Self.maxAttempts) }
        return advancing(to: .submitted(attempt: next, at: date))
    }

    /// The bank answered the in-flight request.
    public func responded(_ outcome: Outcome) throws -> TransferMachine {
        guard case .submitted(let attempt, _) = state else {
            throw TransferError.invalidTransition(from: label, on: "response")
        }
        switch outcome {
        case .confirmed(let receipt): return advancing(to: .confirmed(receipt))
        case .failed(let failure): return advancing(to: .failed(failure, attempt: attempt))
        }
    }

    /// The connection died before an answer arrived. We do not know what the bank did.
    public func lostResponse(at date: Date) throws -> TransferMachine {
        guard case .submitted(let attempt, _) = state else {
            throw TransferError.invalidTransition(from: label, on: "lostResponse")
        }
        return advancing(to: .unknown(attempt: attempt, since: date))
    }

    /// Result of asking the bank "what happened to idempotency key X?".
    public func reconciled(_ outcome: ReconcileOutcome) throws -> TransferMachine {
        guard case .unknown(let attempt, _) = state else {
            throw TransferError.invalidTransition(from: label, on: "reconcile")
        }
        switch outcome {
        case .confirmed(let receipt): return advancing(to: .confirmed(receipt))
        case .failed(let failure): return advancing(to: .failed(failure, attempt: attempt))
        case .neverReceived:
            // The bank has no record of this key, so no debit happened. Sending again with
            // the same key is safe; if we are wrong, the key makes the bank return the original.
            return advancing(to: .failed(TransferFailure(code: "NGAO_LOST", message: "Request never reached the bank",
                                                         isRetryable: true), attempt: attempt))
        }
    }

    public enum Outcome: Hashable, Sendable {
        case confirmed(Receipt)
        case failed(TransferFailure)
    }

    public enum ReconcileOutcome: Hashable, Sendable {
        case confirmed(Receipt)
        case failed(TransferFailure)
        case neverReceived
    }

    private func advancing(to next: TransferState) -> TransferMachine {
        var copy = self
        copy.state = next
        copy.history.append(next)
        return copy
    }

    private var label: String {
        switch state {
        case .pending: return "pending"
        case .submitted: return "submitted"
        case .confirmed: return "confirmed"
        case .failed: return "failed"
        case .unknown: return "unknown"
        }
    }
}
