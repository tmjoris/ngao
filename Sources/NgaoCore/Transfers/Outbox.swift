import Foundation

/// The bank's answer to one request, from the outbox's point of view.
public enum SendResult: Sendable {
    case response(TransferMachine.Outcome)
    /// Timeout, connection reset, app killed: we sent bytes and heard nothing.
    case noResponse
}

/// Talks to the bank. The real one uses URLSession with certificate pinning; tests use a
/// scripted fake that can lose responses after the server committed.
public protocol TransferGateway: Sendable {
    func send(_ intent: TransferIntent, attempt: Int) async -> SendResult
    func status(of key: IdempotencyKey) async throws -> TransferMachine.ReconcileOutcome
}

/// Durable record of every transfer the user confirmed. Written before the first byte goes
/// out, so a crash between "confirm" and "response" leaves a row that the next launch
/// reconciles instead of a user who does not know whether to pay again.
public protocol OutboxStorage: Sendable {
    func load() async throws -> [TransferMachine]
    func save(_ machine: TransferMachine) async throws
}

public actor Outbox {
    private let storage: any OutboxStorage
    private let gateway: any TransferGateway
    private var machines: [IdempotencyKey: TransferMachine] = [:]
    private let clock: @Sendable () -> Date

    public init(storage: any OutboxStorage, gateway: any TransferGateway,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.storage = storage
        self.gateway = gateway
        self.clock = clock
    }

    public func restore() async throws {
        for machine in try await storage.load() {
            machines[machine.intent.id] = machine
        }
    }

    public func machine(for key: IdempotencyKey) -> TransferMachine? {
        machines[key]
    }

    public var all: [TransferMachine] {
        machines.values.sorted { $0.intent.createdAt > $1.intent.createdAt }
    }

    /// Persists the intent, then sends it. Returns the final machine for this attempt.
    public func submit(_ intent: TransferIntent) async throws -> TransferMachine {
        guard intent.amount.isPositive else { throw TransferError.nonPositiveAmount }
        guard intent.amount.isWholeShillings else { throw TransferError.notWholeShillings }
        if let existing = machines[intent.id] { return existing }
        let machine = TransferMachine(intent: intent)
        try await persist(machine)
        return try await attempt(machine)
    }

    /// Retries a retryable failure with the same idempotency key.
    public func retry(_ key: IdempotencyKey) async throws -> TransferMachine {
        guard let machine = machines[key] else { throw TransferError.invalidTransition(from: "missing", on: "retry") }
        return try await attempt(machine)
    }

    /// Resolves every `unknown` transfer by asking the bank. Also catches transfers left in
    /// `submitted` by a crash, which are `unknown` by definition.
    public func reconcile() async throws -> [TransferMachine] {
        var resolved: [TransferMachine] = []
        for var machine in machines.values {
            if case .submitted = machine.state {
                machine = try machine.lostResponse(at: clock())
                try await persist(machine)
            }
            guard case .unknown = machine.state else { continue }
            let outcome = try await gateway.status(of: machine.intent.id)
            machine = try machine.reconciled(outcome)
            try await persist(machine)
            resolved.append(machine)
        }
        return resolved
    }

    private func attempt(_ machine: TransferMachine) async throws -> TransferMachine {
        var current = try machine.sending(at: clock())
        try await persist(current)
        switch await gateway.send(current.intent, attempt: current.state.attempt) {
        case .response(let outcome):
            current = try current.responded(outcome)
        case .noResponse:
            current = try current.lostResponse(at: clock())
        }
        try await persist(current)
        return current
    }

    private func persist(_ machine: TransferMachine) async throws {
        machines[machine.intent.id] = machine
        try await storage.save(machine)
    }
}

/// In-memory storage for tests and previews.
public actor MemoryOutboxStorage: OutboxStorage {
    private var rows: [IdempotencyKey: TransferMachine] = [:]
    public init() {}
    public func load() async throws -> [TransferMachine] { Array(rows.values) }
    public func save(_ machine: TransferMachine) async throws { rows[machine.intent.id] = machine }
    public var count: Int { rows.count }
}
