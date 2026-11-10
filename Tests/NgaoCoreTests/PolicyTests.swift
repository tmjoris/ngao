import XCTest
@testable import NgaoCore

final class PolicyTests: XCTestCase {
    func testMoneyFormattingAndParsing() {
        XCTAssertEqual(Money.kes(1_250, cents: 50).description, "KES 1,250.50")
        XCTAssertEqual(Money.kes(1_000_000).formatted, "1,000,000.00")
        XCTAssertEqual(Money.kes(-7, cents: 5).formatted, "-7.05")
        XCTAssertEqual(Money(parsing: "1,250.5"), .kes(1_250, cents: 50))
        XCTAssertEqual(Money(parsing: "KES 300"), .kes(300))
        XCTAssertNil(Money(parsing: "1.234"))
        XCTAssertNil(Money(parsing: "abc"))
        XCTAssertTrue(Money.kes(5).isWholeShillings)
        XCTAssertFalse(Money(cents: 501).isWholeShillings)
    }

    func testMasking() {
        XCTAssertEqual(Masking.account("0110012345678"), "•••• 5678")
        XCTAssertEqual(Masking.phone("254712345678"), "0712 ••• 678")
        XCTAssertEqual(Masking.phone("0712345678"), "0712 ••• 678")
        XCTAssertEqual(Destination.mpesa(phone: "254712345678").summary, "M-Pesa 0712 ••• 678")
    }

    func testPinPolicyRejectsTheUsualSuspects() {
        XCTAssertEqual(PinPolicy.weaknesses(of: "1234"), [.wrongLength])
        XCTAssertEqual(PinPolicy.weaknesses(of: "12a456"), [.notDigits])
        XCTAssertTrue(PinPolicy.weaknesses(of: "111111").contains(.repeated))
        XCTAssertTrue(PinPolicy.weaknesses(of: "123456").contains(.sequential))
        XCTAssertTrue(PinPolicy.weaknesses(of: "654321").contains(.sequential))
        XCTAssertTrue(PinPolicy.weaknesses(of: "121212").contains(.pattern))
        XCTAssertTrue(PinPolicy.weaknesses(of: "123123").contains(.pattern))
        XCTAssertTrue(PinPolicy.weaknesses(of: "199012").contains(.dateLike))
        XCTAssertTrue(PinPolicy.weaknesses(of: "121990").contains(.dateLike))
        XCTAssertTrue(PinPolicy.weaknesses(of: "250887").contains(.dateLike)) // 25 Aug 87
        XCTAssertTrue(PinPolicy.isAcceptable("739142"))
        XCTAssertTrue(PinPolicy.isAcceptable("804619"))
    }

    func testLockoutBackoff() {
        let t0 = Date(timeIntervalSince1970: 0)
        var lock = PinLockout()
        XCTAssertTrue(lock.canAttempt(now: t0))
        lock = lock.recordingFailure(at: t0).recordingFailure(at: t0)
        XCTAssertEqual(lock.remainingWait(now: t0), 30)
        XCTAssertFalse(lock.canAttempt(now: t0.addingTimeInterval(29)))
        XCTAssertTrue(lock.canAttempt(now: t0.addingTimeInterval(30)))
        lock = lock.recordingFailure(at: t0.addingTimeInterval(30))
        XCTAssertEqual(lock.remainingWait(now: t0.addingTimeInterval(30)), 300)
        lock = lock.recordingFailure(at: t0).recordingFailure(at: t0)
        XCTAssertTrue(lock.isHardLocked)
        XCTAssertNil(lock.remainingWait(now: t0.addingTimeInterval(1_000_000)))
        XCTAssertTrue(lock.reset().canAttempt(now: t0))
    }

    func testSessionExpiry() {
        let t0 = Date(timeIntervalSince1970: 0)
        let session = Session(startedAt: t0)
        XCTAssertTrue(session.isValid(now: t0.addingTimeInterval(119)))
        XCTAssertEqual(session.expiry(now: t0.addingTimeInterval(121)), .inactivity)
        let active = session.touched(at: t0.addingTimeInterval(100))
        XCTAssertTrue(active.isValid(now: t0.addingTimeInterval(200)))

        let backgrounded = active.backgrounded(at: t0.addingTimeInterval(110))
        XCTAssertNotNil(backgrounded.foregrounded(at: t0.addingTimeInterval(130)))
        XCTAssertNil(backgrounded.foregrounded(at: t0.addingTimeInterval(141)), "30 s grace exceeded")
        XCTAssertEqual(backgrounded.expiry(now: t0.addingTimeInterval(141)), .background)

        var longLived = session
        for i in 1...20 { longLived = longLived.touched(at: t0.addingTimeInterval(Double(i) * 60)) }
        XCTAssertEqual(longLived.expiry(now: t0.addingTimeInterval(901)), .lifetime)
    }

    func testLimitsCountUnknownTransfers() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let limits = TransactionLimits(perTransaction: .kes(100_000), daily: .kes(150_000))
        func intent(_ amount: Money) -> TransferIntent {
            TransferIntent(sourceAccount: "1", destination: .till(number: "1"), amount: amount, narration: "", createdAt: now)
        }
        let confirmed = try TransferMachine(intent: intent(.kes(60_000))).sending(at: now)
            .responded(.confirmed(Receipt(reference: "a", amount: .kes(60_000), charge: .zero, completedAt: now, destination: .till(number: "1"))))
        let unknown = try TransferMachine(intent: intent(.kes(50_000))).sending(at: now).lostResponse(at: now)
        let failed = try TransferMachine(intent: intent(.kes(90_000))).sending(at: now)
            .responded(.failed(TransferFailure(code: "x", message: "", isRetryable: false)))
        let yesterday = try TransferMachine(intent: TransferIntent(sourceAccount: "1", destination: .till(number: "1"), amount: .kes(90_000),
                                                                   narration: "", createdAt: now.addingTimeInterval(-86_400 * 2)))
            .sending(at: now).responded(.confirmed(Receipt(reference: "b", amount: .kes(90_000), charge: .zero, completedAt: now, destination: .till(number: "1"))))
        let history = [confirmed, unknown, failed, yesterday]

        XCTAssertEqual(limits.usedToday(history, now: now), .kes(110_000))
        XCTAssertEqual(limits.check(.kes(100_001), against: history, now: now), .perTransaction(limit: .kes(100_000)))
        XCTAssertEqual(limits.check(.kes(40_001), against: history, now: now), .daily(limit: .kes(150_000), usedToday: .kes(110_000)))
        XCTAssertNil(limits.check(.kes(40_000), against: history, now: now))
    }
}
