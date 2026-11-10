import XCTest
@testable import NgaoCore

final class TransferMachineTests: XCTestCase {
    static let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    let t0 = TransferMachineTests.t0
    let intent = TransferIntent(sourceAccount: "0110012345678", destination: .mpesa(phone: "254712345678"),
                                amount: .kes(5_000), narration: "Rent", createdAt: TransferMachineTests.t0)
    let receipt = Receipt(reference: "FT26110ABCD", amount: .kes(5_000), charge: .kes(33), completedAt: TransferMachineTests.t0,
                          destination: .mpesa(phone: "254712345678"))
    let timeout = TransferFailure(code: "BANK_TIMEOUT", message: "Core banking timed out", isRetryable: true)
    let noFunds = TransferFailure(code: "INSUFFICIENT_FUNDS", message: "Insufficient funds", isRetryable: false)

    func testHappyPath() throws {
        var m = TransferMachine(intent: intent)
        XCTAssertEqual(m.state, .pending)
        m = try m.sending(at: t0)
        XCTAssertEqual(m.state, .submitted(attempt: 1, at: t0))
        XCTAssertTrue(m.state.mayHaveDebited)
        m = try m.responded(.confirmed(receipt))
        XCTAssertEqual(m.state, .confirmed(receipt))
        XCTAssertTrue(m.state.isTerminal)
        XCTAssertEqual(m.history.count, 3)
    }

    func testCannotSendWhileInFlightOrUnknown() throws {
        let inFlight = try TransferMachine(intent: intent).sending(at: t0)
        XCTAssertThrowsError(try inFlight.sending(at: t0))
        let unknown = try inFlight.lostResponse(at: t0)
        XCTAssertThrowsError(try unknown.sending(at: t0))
        XCTAssertThrowsError(try unknown.responded(.confirmed(receipt)))
        XCTAssertTrue(unknown.state.mayHaveDebited)
        XCTAssertFalse(unknown.state.isTerminal)
    }

    func testLostResponseResolvesThreeWays() throws {
        let unknown = try TransferMachine(intent: intent).sending(at: t0).lostResponse(at: t0)

        let paid = try unknown.reconciled(.confirmed(receipt))
        XCTAssertEqual(paid.state, .confirmed(receipt))

        let refused = try unknown.reconciled(.failed(noFunds))
        XCTAssertEqual(refused.state, .failed(noFunds, attempt: 1))
        XCTAssertTrue(refused.state.isTerminal)

        let never = try unknown.reconciled(.neverReceived)
        guard case .failed(let failure, let attempt) = never.state else { return XCTFail() }
        XCTAssertTrue(failure.isRetryable)
        XCTAssertEqual(attempt, 1)
        XCTAssertFalse(never.state.mayHaveDebited)
        let resent = try never.sending(at: t0)
        XCTAssertEqual(resent.state, .submitted(attempt: 2, at: t0))
        XCTAssertEqual(resent.intent.id, intent.id, "retry keeps the idempotency key")
    }

    func testNonRetryableFailureIsTerminal() throws {
        let m = try TransferMachine(intent: intent).sending(at: t0).responded(.failed(noFunds))
        XCTAssertTrue(m.state.isTerminal)
        XCTAssertThrowsError(try m.sending(at: t0))
    }

    func testAttemptsAreCapped() throws {
        var m = TransferMachine(intent: intent)
        for _ in 0..<TransferMachine.maxAttempts {
            m = try m.sending(at: t0).responded(.failed(timeout))
        }
        XCTAssertThrowsError(try m.sending(at: t0)) { error in
            XCTAssertEqual(error as? TransferError, .tooManyAttempts(max: 3))
        }
    }

    func testReconcileOnlyFromUnknown() {
        XCTAssertThrowsError(try TransferMachine(intent: intent).reconciled(.neverReceived))
    }

    func testCodableRoundTrip() throws {
        let m = try TransferMachine(intent: intent).sending(at: t0).lostResponse(at: t0)
        let data = try JSONEncoder().encode(m)
        XCTAssertEqual(try JSONDecoder().decode(TransferMachine.self, from: data), m)
    }
}
