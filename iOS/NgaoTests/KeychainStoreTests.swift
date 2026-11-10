import NgaoCore
import XCTest
@testable import Ngao

final class KeychainStoreTests: XCTestCase {
    let store = KeychainStore(service: "ke.ngao.tests")

    override func setUp() { store.wipe() }
    override func tearDown() { store.wipe() }

    func testRoundTripAndOverwrite() throws {
        try store.setString("abc", for: "k", protection: .deviceOnly)
        XCTAssertEqual(try store.string("k"), "abc")
        try store.setString("def", for: "k", protection: .deviceOnly)
        XCTAssertEqual(try store.string("k"), "def")
        try store.delete("k")
        XCTAssertNil(try store.string("k"))
    }

    func testCodableLockoutPersists() throws {
        let lock = PinLockout(failures: 3, lastFailureAt: Date(timeIntervalSince1970: 100))
        try store.setCodable(lock, for: KeychainKeys.pinLockout, protection: .deviceOnly)
        XCTAssertEqual(try store.codable(PinLockout.self, for: KeychainKeys.pinLockout), lock)
    }
}
