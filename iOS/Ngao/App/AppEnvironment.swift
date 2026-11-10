import Foundation
import NgaoCore

/// Dependency container. One `live()` for the app, hand-built ones for tests and previews.
struct AppEnvironment {
    let api: BankAPI
    let keychain: KeychainStore
    let biometrics: BiometricAuthenticator
    let outbox: Outbox
    let limits: TransactionLimits
    let integrity: IntegrityReport

    static func live() -> AppEnvironment {
        let args = ProcessInfo.processInfo.arguments
        let uiTesting = args.contains("-ui-testing")
        let baseURL = URL(string: Bundle.main.object(forInfoDictionaryKey: "NGAO_API_BASE_URL") as? String ?? "")
            ?? URL(string: "http://127.0.0.1:8090")!
        let pin = (Bundle.main.object(forInfoDictionaryKey: "NGAO_PIN_SHA256") as? String).flatMap { $0.isEmpty ? nil : $0 }

        let session = PinnedSession(pins: pin.map { [$0] } ?? [], allowUnpinned: pin == nil)
        let keychain = KeychainStore(service: uiTesting ? "ke.ngao.uitest" : "ke.ngao")
        if uiTesting { keychain.wipe() }
        let api: BankAPI = uiTesting ? ScriptedBankAPI() : LiveBankAPI(baseURL: baseURL, session: session.urlSession, keychain: keychain)
        let storage: any OutboxStorage = uiTesting ? MemoryOutboxStorage() : FileOutboxStorage.default()
        return AppEnvironment(
            api: api,
            keychain: keychain,
            biometrics: BiometricAuthenticator(),
            outbox: Outbox(storage: storage, gateway: api),
            limits: .retail,
            integrity: IntegrityReport.collect())
    }
}

/// Jailbreak and debugger signals from the Objective-C module, read once at launch.
struct IntegrityReport: Sendable {
    let signals: [String]
    let debuggerAttached: Bool

    var isCompromised: Bool { !signals.isEmpty }

    static func collect() -> IntegrityReport {
        IntegrityReport(signals: NGDeviceIntegrity.suspiciousSignals(), debuggerAttached: NGDeviceIntegrity.isDebuggerAttached())
    }
}
