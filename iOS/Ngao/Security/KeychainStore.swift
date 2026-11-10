import Foundation
import LocalAuthentication
import Security

/// Thin wrapper over SecItem. Two protection levels:
/// - `.deviceOnly`: available after first unlock, never leaves this device (session tokens).
/// - `.biometric`: readable only after Face ID / Touch ID or passcode, invalidated if the
///   enrolled biometrics change (the refresh token behind "unlock with Face ID").
final class KeychainStore: @unchecked Sendable {
    enum Protection {
        case deviceOnly
        case biometric
    }

    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)
        case accessControl

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status): return "Keychain error \(status)"
            case .accessControl: return "Could not create access control"
            }
        }
    }

    private let service: String

    init(service: String) {
        self.service = service
    }

    func set(_ data: Data, for key: String, protection: Protection) throws {
        var attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData: data,
        ]
        switch protection {
        case .deviceOnly:
            attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .biometric:
            var error: Unmanaged<CFError>?
            guard let control = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.biometryCurrentSet, .or, .devicePasscode], &error) else {
                throw KeychainError.accessControl
            }
            attributes[kSecAttrAccessControl] = control
        }
        try delete(key)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    func get(_ key: String, context: LAContext? = nil) throws -> Data? {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        if let context {
            query[kSecUseAuthenticationContext] = context
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess: return item as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError.unexpectedStatus(status)
        }
    }

    func delete(_ key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.unexpectedStatus(status) }
    }

    /// Removes everything under this service. Used on sign-out from a compromised state and in UI tests.
    func wipe() {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Typed helpers

    func setString(_ value: String, for key: String, protection: Protection) throws {
        try set(Data(value.utf8), for: key, protection: protection)
    }

    func string(_ key: String, context: LAContext? = nil) throws -> String? {
        try get(key, context: context).flatMap { String(data: $0, encoding: .utf8) }
    }

    func setCodable<T: Encodable>(_ value: T, for key: String, protection: Protection) throws {
        try set(JSONEncoder().encode(value), for: key, protection: protection)
    }

    func codable<T: Decodable>(_ type: T.Type, for key: String) throws -> T? {
        try get(key).map { try JSONDecoder().decode(type, from: $0) }
    }
}

enum KeychainKeys {
    static let sessionToken = "session-token"
    static let biometricRefreshToken = "biometric-refresh-token"
    static let pinLockout = "pin-lockout"
    static let customerID = "customer-id"
}
