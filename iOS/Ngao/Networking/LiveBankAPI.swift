import Foundation
import NgaoCore

/// Talks to the real (or mock) bank over the pinned URLSession. Session token lives in the
/// Keychain, device-only, and is cleared on lock.
final class LiveBankAPI: BankAPI, @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let keychain: KeychainStore
    private let lock = NSLock()
    private var token: String?

    init(baseURL: URL, session: URLSession, keychain: KeychainStore) {
        self.baseURL = baseURL
        self.session = session
        self.keychain = keychain
        token = try? keychain.string(KeychainKeys.sessionToken)
    }

    private struct LoginResponse: Decodable { let token: String; let customer: Customer }
    private struct ErrorResponse: Decodable { let error: String; let message: String?; let attemptsLeft: Int?; let retryable: Bool? }
    private struct Wire<T: Decodable>: Decodable { let accounts: T?; let cards: T? }

    func login(pin: String) async throws -> Customer {
        let response: LoginResponse = try await send("POST", "auth/pin", body: ["pin": pin], authenticated: false)
        store(token: response.token)
        return response.customer
    }

    func loginWithRefreshToken(_ refresh: String) async throws -> Customer {
        // The mock bank has no refresh endpoint; a real one exchanges the long-lived token here.
        let response: LoginResponse = try await send("POST", "auth/refresh", body: ["refreshToken": refresh], authenticated: false)
        store(token: response.token)
        return response.customer
    }

    func clearSession() {
        lock.withLock { token = nil }
        try? keychain.delete(KeychainKeys.sessionToken)
    }

    func accounts() async throws -> [Account] {
        let wire: Wire<[Account]> = try await send("GET", "accounts")
        return wire.accounts ?? []
    }

    func cards() async throws -> [Card] {
        let wire: Wire<[Card]> = try await send("GET", "cards")
        return wire.cards ?? []
    }

    func setFrozen(_ frozen: Bool, card: Card) async throws -> Card {
        try await send("POST", "cards/\(card.id)/\(frozen ? "freeze" : "unfreeze")", body: [String: String]())
    }

    // MARK: - TransferGateway

    private struct TransferBody: Encodable {
        let sourceAccount: String
        let amountCents: Int64
        let destination: WireDestination
        let narration: String
    }

    private struct ReceiptBody: Decodable {
        let reference: String
        let amountCents: Int64
        let chargeCents: Int64
        let completedAt: Date
        let destination: WireDestination
    }

    func send(_ intent: TransferIntent, attempt: Int) async -> SendResult {
        let body = TransferBody(sourceAccount: intent.sourceAccount, amountCents: intent.amount.cents,
                                destination: WireDestination(intent.destination), narration: intent.narration)
        do {
            let receipt: ReceiptBody = try await send("POST", "transfers", body: body,
                                                      headers: ["Idempotency-Key": intent.id.value])
            return .response(.confirmed(receipt.receipt))
        } catch let error as TransferRefused {
            return .response(.failed(TransferFailure(code: error.code, message: error.message, isRetryable: error.retryable)))
        } catch {
            // Timeout, reset, no route: the request may or may not have been processed.
            return .noResponse
        }
    }

    func status(of key: IdempotencyKey) async throws -> TransferMachine.ReconcileOutcome {
        do {
            let receipt: ReceiptBody = try await send("GET", "transfers/\(key.value)")
            return .confirmed(receipt.receipt)
        } catch BankError.server(let message) where message.contains("unknown idempotency key") {
            return .neverReceived
        } catch let refused as TransferRefused {
            return .failed(TransferFailure(code: refused.code, message: refused.message, isRetryable: refused.retryable))
        }
    }

    private struct TransferRefused: Error { let code: String; let message: String; let retryable: Bool }

    // MARK: - Plumbing

    private func store(token: String) {
        lock.withLock { self.token = token }
        try? keychain.setString(token, for: KeychainKeys.sessionToken, protection: .deviceOnly)
    }

    private func send<Out: Decodable>(_ method: String, _ path: String, headers: [String: String] = [:],
                                      authenticated: Bool = true) async throws -> Out {
        try await send(method, path, body: Optional<Int>.none, headers: headers, authenticated: authenticated)
    }

    private func send<Body: Encodable, Out: Decodable>(_ method: String, _ path: String, body: Body?,
                                                       headers: [String: String] = [:], authenticated: Bool = true) async throws -> Out {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        if authenticated {
            guard let token = lock.withLock({ token }) else { throw BankError.unauthenticated }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw BankError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if (200..<300).contains(http.statusCode) {
            return try decoder.decode(Out.self, from: data)
        }
        let failure = try? decoder.decode(ErrorResponse.self, from: data)
        switch http.statusCode {
        case 401 where failure?.error == "wrong_pin": throw BankError.wrongPIN(attemptsLeft: failure?.attemptsLeft ?? 0)
        case 401: clearSession(); throw BankError.unauthenticated
        case 423: throw BankError.locked
        case 400, 402, 404 where path == "transfers":
            throw TransferRefused(code: failure?.error ?? "REFUSED", message: failure?.message ?? "Transfer refused",
                                  retryable: failure?.retryable ?? false)
        default: throw BankError.server(failure?.message ?? failure?.error ?? "Server error \(http.statusCode)")
        }
    }
}

/// JSON shape of a destination on the wire: `{"type": "mpesa", "phone": "..."}` etc.
struct WireDestination: Codable, Hashable {
    let type: String
    var phone: String?
    var accountNumber: String?
    var businessNumber: String?
    var account: String?
    var number: String?
    var bankCode: String?

    init(_ destination: Destination) {
        switch destination {
        case .ownBank(let accountNumber): type = "ownBank"; self.accountNumber = accountNumber
        case .mpesa(let phone): type = "mpesa"; self.phone = phone
        case .paybill(let business, let account): type = "paybill"; businessNumber = business; self.account = account
        case .till(let number): type = "till"; self.number = number
        case .pesalink(let bank, let accountNumber): type = "pesalink"; bankCode = bank; self.accountNumber = accountNumber
        }
    }

    var destination: Destination {
        switch type {
        case "mpesa": return .mpesa(phone: phone ?? "")
        case "paybill": return .paybill(businessNumber: businessNumber ?? "", account: account ?? "")
        case "till": return .till(number: number ?? "")
        case "pesalink": return .pesalink(bankCode: bankCode ?? "", accountNumber: accountNumber ?? "")
        default: return .ownBank(accountNumber: accountNumber ?? "")
        }
    }
}

private extension LiveBankAPI.ReceiptBody {
    var receipt: Receipt {
        Receipt(reference: reference, amount: Money(cents: amountCents), charge: Money(cents: chargeCents),
                completedAt: completedAt, destination: destination.destination)
    }
}
