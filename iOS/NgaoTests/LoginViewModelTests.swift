import NgaoCore
import XCTest
@testable import Ngao

@MainActor
final class LoginViewModelTests: XCTestCase {
    func testWrongPinsEscalateToLockout() async {
        let keychain = KeychainStore(service: "ke.ngao.tests.login")
        keychain.wipe()
        let api = ScriptedBankAPI()
        let viewModel = LoginViewModel(api: api, keychain: keychain, biometrics: BiometricAuthenticator())

        await viewModel.submit(pin: "000000")
        guard case .error = viewModel.state else { return XCTFail("first wrong PIN is a plain error") }
        await viewModel.submit(pin: "000000")
        guard case .lockedFor(let seconds) = viewModel.state else { return XCTFail("second wrong PIN starts the 30 s backoff") }
        XCTAssertEqual(seconds, 30)

        // Lockout survives a relaunch because it lives in the Keychain.
        let relaunched = LoginViewModel(api: api, keychain: keychain, biometrics: BiometricAuthenticator())
        guard case .lockedFor = relaunched.state else { return XCTFail("lockout must persist") }
        keychain.wipe()
    }

    func testCorrectPinAuthenticates() async {
        let keychain = KeychainStore(service: "ke.ngao.tests.login2")
        keychain.wipe()
        let viewModel = LoginViewModel(api: ScriptedBankAPI(), keychain: keychain, biometrics: BiometricAuthenticator())
        await viewModel.submit(pin: "739142")
        guard case .authenticated(let customer) = viewModel.state else { return XCTFail() }
        XCTAssertEqual(customer.name, "Wanjiru Kamau")
        keychain.wipe()
    }
}
