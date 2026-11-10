import NgaoCore
import XCTest
@testable import Ngao

@MainActor
final class WireDestinationTests: XCTestCase {
    func testAllDestinationsRoundTrip() throws {
        let cases: [Destination] = [
            .mpesa(phone: "254712345678"), .paybill(businessNumber: "888880", account: "12345"),
            .till(number: "55555"), .ownBank(accountNumber: "0110012345678"), .pesalink(bankCode: "11", accountNumber: "99"),
        ]
        for destination in cases {
            let data = try JSONEncoder().encode(WireDestination(destination))
            let decoded = try JSONDecoder().decode(WireDestination.self, from: data)
            XCTAssertEqual(decoded.destination, destination)
        }
    }

    func testSendMoneyValidation() async {
        let account = Account(id: "0110012345678", name: "Current", balanceCents: 10_000_00, currency: "KES")
        let viewModel = SendMoneyViewModel(account: account, outbox: Outbox(storage: MemoryOutboxStorage(), gateway: ScriptedBankAPI()),
                                           limits: .retail)
        XCTAssertNotNil(viewModel.validationMessage(history: []))
        viewModel.primaryField = "0712345678"
        viewModel.amountText = "5000"
        XCTAssertNil(viewModel.validationMessage(history: []))
        XCTAssertEqual(viewModel.destination, .mpesa(phone: "254712345678"))
        viewModel.amountText = "9990"
        XCTAssertEqual(viewModel.validationMessage(history: []), "Insufficient funds (charges apply).")
        viewModel.amountText = "50.5"
        XCTAssertEqual(viewModel.validationMessage(history: []), "Whole shillings only.")
    }
}
