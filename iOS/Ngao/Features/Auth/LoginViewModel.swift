import Foundation
import LocalAuthentication
import NgaoCore

@MainActor
final class LoginViewModel {
    enum State: Equatable {
        case idle
        case checking
        case lockedFor(seconds: Int)
        case hardLocked
        case error(String)
        case authenticated(Customer)
    }

    private(set) var state: State = .idle { didSet { onChange?(state) } }
    var onChange: ((State) -> Void)?

    private let api: BankAPI
    private let keychain: KeychainStore
    private let biometrics: BiometricAuthenticator
    private var lockout: PinLockout

    init(api: BankAPI, keychain: KeychainStore, biometrics: BiometricAuthenticator) {
        self.api = api
        self.keychain = keychain
        self.biometrics = biometrics
        lockout = (try? keychain.codable(PinLockout.self, for: KeychainKeys.pinLockout)) ?? PinLockout()
        refreshLockState()
    }

    var biometricKind: BiometricAuthenticator.Kind { biometrics.available }

    var canOfferBiometrics: Bool {
        biometricKind != .none && (try? keychain.get(KeychainKeys.biometricRefreshToken)) != nil
    }

    func refreshLockState() {
        if lockout.isHardLocked {
            state = .hardLocked
        } else if let wait = lockout.remainingWait(now: Date()), wait > 0 {
            state = .lockedFor(seconds: Int(wait.rounded(.up)))
        } else if case .lockedFor = state {
            state = .idle
        }
    }

    func submit(pin: String) async {
        refreshLockState()
        guard state == .idle || { if case .error = state { return true }; return false }() else { return }
        state = .checking
        do {
            let customer = try await api.login(pin: pin)
            lockout = lockout.reset()
            persistLockout()
            try? keychain.setString(customer.id, for: KeychainKeys.customerID, protection: .deviceOnly)
            state = .authenticated(customer)
        } catch BankError.wrongPIN(let left) {
            lockout = lockout.recordingFailure(at: Date())
            persistLockout()
            if lockout.isHardLocked {
                state = .hardLocked
            } else if let wait = lockout.remainingWait(now: Date()), wait > 0 {
                state = .lockedFor(seconds: Int(wait.rounded(.up)))
            } else {
                state = .error(BankError.wrongPIN(attemptsLeft: left).localizedDescription)
            }
        } catch BankError.locked {
            state = .hardLocked
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func submitWithBiometrics() async {
        state = .checking
        do {
            let context = try await biometrics.authenticate(reason: "Unlock Ngao")
            guard let refresh = try keychain.string(KeychainKeys.biometricRefreshToken, context: context) else {
                state = .error("Face ID is not set up for Ngao yet. Sign in with your PIN first.")
                return
            }
            state = .authenticated(try await api.loginWithRefreshToken(refresh))
        } catch let error as LAError where error.code == .userCancel || error.code == .userFallback {
            state = .idle
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func persistLockout() {
        try? keychain.setCodable(lockout, for: KeychainKeys.pinLockout, protection: .deviceOnly)
    }
}
