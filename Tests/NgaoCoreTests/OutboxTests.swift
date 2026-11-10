import XCTest
@testable import NgaoCore

/// A bank that really debits, so the tests can count debits. `script` decides what the
/// client *sees* for each attempt, independent of what the bank *did*.
actor FakeBank: TransferGateway {
    enum Behaviour { case ok, refuse, timeoutBeforeCommit, dropAfterCommit }

    private var script: [Behaviour]
    private(set) var ledger: [IdempotencyKey: Receipt] = [:]
    private(set) var debits: [Money] = []
    private(set) var requests = 0

    init(script: [Behaviour]) { self.script = script }

    func send(_ intent: TransferIntent, attempt: Int) async -> SendResult {
        requests += 1
        // Idempotency on the server side: a key we have seen gets the original answer.
        if let existing = ledger[intent.id] { return .response(.confirmed(existing)) }
        let behaviour = script.isEmpty ? .ok : script.removeFirst()
        switch behaviour {
        case .ok:
            return .response(.confirmed(commit(intent)))
        case .refuse:
            return .response(.failed(TransferFailure(code: "INSUFFICIENT_FUNDS", message: "no", isRetryable: false)))
        case .timeoutBeforeCommit:
            return .noResponse
        case .dropAfterCommit:
            _ = commit(intent)
            return .noResponse
        }
    }

    func status(of key: IdempotencyKey) async throws -> TransferMachine.ReconcileOutcome {
        if let receipt = ledger[key] { return .confirmed(receipt) }
        return .neverReceived
    }

    private func commit(_ intent: TransferIntent) -> Receipt {
        let receipt = Receipt(reference: "FT\(debits.count + 1)", amount: intent.amount, charge: .kes(33),
                              completedAt: Date(), destination: intent.destination)
        ledger[intent.id] = receipt
        debits.append(intent.amount)
        return receipt
    }
}

final class OutboxTests: XCTestCase {
    func intent() -> TransferIntent {
        TransferIntent(sourceAccount: "0110012345678", destination: .paybill(businessNumber: "888880", account: "123456"),
                       amount: .kes(1_500), narration: "KPLC")
    }

    func testPersistsBeforeSending() async throws {
        let storage = MemoryOutboxStorage()
        let bank = FakeBank(script: [.ok])
        let outbox = Outbox(storage: storage, gateway: bank)
        let result = try await outbox.submit(intent())
        guard case .confirmed = result.state else { return XCTFail("expected confirmed") }
        let v1 = await storage.count
        XCTAssertEqual(v1, 1)
        let v2 = await bank.debits.count
        XCTAssertEqual(v2, 1)
    }

    func testRejectsCentsAndZero() async {
        let outbox = Outbox(storage: MemoryOutboxStorage(), gateway: FakeBank(script: []))
        let cents = TransferIntent(sourceAccount: "1", destination: .till(number: "1"), amount: Money(cents: 150), narration: "")
        let zero = TransferIntent(sourceAccount: "1", destination: .till(number: "1"), amount: .zero, narration: "")
        do { _ = try await outbox.submit(cents); XCTFail() } catch { XCTAssertEqual(error as? TransferError, .notWholeShillings) }
        do { _ = try await outbox.submit(zero); XCTFail() } catch { XCTAssertEqual(error as? TransferError, .nonPositiveAmount) }
    }

    /// The scenario that double-charges real apps: the bank debits, the response is lost,
    /// the user is shown "failed" and taps again. Here the user cannot tap again, and
    /// reconciliation finds the receipt.
    func testDroppedResponseAfterCommitNeverDoubleDebits() async throws {
        let bank = FakeBank(script: [.dropAfterCommit])
        let outbox = Outbox(storage: MemoryOutboxStorage(), gateway: bank)
        let intent = intent()

        let afterSend = try await outbox.submit(intent)
        guard case .unknown = afterSend.state else { return XCTFail("expected unknown, got \(afterSend.state)") }

        // UI would be blocked, but even a bug that calls retry must be refused.
        do { _ = try await outbox.retry(intent.id); XCTFail("retry from unknown must throw") } catch {}

        let resolved = try await outbox.reconcile()
        XCTAssertEqual(resolved.count, 1)
        guard case .confirmed(let receipt) = resolved[0].state else { return XCTFail() }
        XCTAssertEqual(receipt.reference, "FT1")
        let v3 = await bank.debits.count
        XCTAssertEqual(v3, 1)
        let v4 = await bank.requests
        XCTAssertEqual(v4, 1)
    }

    func testTimeoutBeforeCommitIsSafelyRetried() async throws {
        let bank = FakeBank(script: [.timeoutBeforeCommit, .ok])
        let outbox = Outbox(storage: MemoryOutboxStorage(), gateway: bank)
        let intent = intent()

        _ = try await outbox.submit(intent)
        let resolved = try await outbox.reconcile()
        guard case .failed(let failure, 1) = resolved[0].state, failure.isRetryable else { return XCTFail() }

        let second = try await outbox.retry(intent.id)
        guard case .confirmed = second.state else { return XCTFail() }
        XCTAssertEqual(second.state.attempt, 0)
        XCTAssertEqual(second.history.count, 6) // pending, submitted, unknown, failed, submitted, confirmed
        let v5 = await bank.debits.count
        XCTAssertEqual(v5, 1)
    }

    /// Server-side idempotency as belt and braces: even if the client did resend after a
    /// committed-but-lost response, the same key returns the original receipt.
    func testServerIdempotencyReturnsOriginalReceiptOnReplay() async throws {
        let bank = FakeBank(script: [.ok])
        let intent = intent()
        let first = await bank.send(intent, attempt: 1)
        let second = await bank.send(intent, attempt: 2)
        guard case .response(.confirmed(let a)) = first, case .response(.confirmed(let b)) = second else { return XCTFail() }
        XCTAssertEqual(a, b)
        let v6 = await bank.debits.count
        XCTAssertEqual(v6, 1)
    }

    func testCrashMidFlightIsReconciledOnRestore() async throws {
        let storage = MemoryOutboxStorage()
        let bank = FakeBank(script: [])
        // Simulate a row left in `submitted` by a crash: write it straight to storage.
        let stuck = try TransferMachine(intent: intent()).sending(at: Date())
        try await storage.save(stuck)
        _ = await bank.send(stuck.intent, attempt: 1) // the bank did process it

        let outbox = Outbox(storage: storage, gateway: bank)
        try await outbox.restore()
        let resolved = try await outbox.reconcile()
        guard case .confirmed = resolved.first?.state else { return XCTFail("expected confirmed") }
        let v7 = await bank.debits.count
        XCTAssertEqual(v7, 1)
    }

    func testSubmittingTheSameIntentTwiceIsANoOp() async throws {
        let bank = FakeBank(script: [.ok])
        let outbox = Outbox(storage: MemoryOutboxStorage(), gateway: bank)
        let intent = intent()
        let a = try await outbox.submit(intent)
        let b = try await outbox.submit(intent)
        XCTAssertEqual(a, b)
        let v8 = await bank.requests
        XCTAssertEqual(v8, 1)
    }
}
