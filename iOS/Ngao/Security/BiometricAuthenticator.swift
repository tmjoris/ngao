import Foundation
import LocalAuthentication

/// Face ID / Touch ID gate. Biometrics never replace the server's authentication: a success
/// here only unlocks a Keychain item (the refresh token) that the server then validates.
struct BiometricAuthenticator: Sendable {
    enum Kind { case none, touchID, faceID, opticID }

    var available: Kind {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return .none }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .none
        }
    }

    /// Returns an authenticated context that Keychain reads can be bound to.
    func authenticate(reason: String) async throws -> LAContext {
        let context = LAContext()
        context.localizedCancelTitle = "Use PIN"
        context.localizedFallbackTitle = ""
        _ = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        return context
    }
}
