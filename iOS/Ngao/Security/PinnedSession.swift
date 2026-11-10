import CryptoKit
import Foundation
import Security

/// URLSession whose delegate rejects any server certificate chain that does not contain a
/// public key with one of the pinned SPKI hashes. Pinning the key (not the certificate)
/// survives routine certificate renewals; pin the intermediate as well as the leaf and
/// rotate ahead of time.
///
/// App Transport Security still applies underneath (TLS 1.2+, forward secrecy). Pinning
/// adds protection against a compromised or coerced CA, which is the threat model for a
/// banking app on untrusted Wi-Fi.
final class PinnedSession: NSObject, URLSessionDelegate, Sendable {
    private let pins: Set<String>
    private let allowUnpinned: Bool

    /// `pins` are base64 SHA-256 digests of the DER-encoded SubjectPublicKeyInfo.
    /// `allowUnpinned` must only ever be true in debug builds pointing at a local server.
    init(pins: [String], allowUnpinned: Bool) {
        self.pins = Set(pins)
        #if DEBUG
        self.allowUnpinned = allowUnpinned
        #else
        self.allowUnpinned = false
        #endif
    }

    var urlSession: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            return (.cancelAuthenticationChallenge, nil)
        }
        // System validation first: hostname, expiry, chain to a trusted root.
        var error: CFError?
        guard SecTrustEvaluateWithError(trust, &error) else {
            return (.cancelAuthenticationChallenge, nil)
        }
        if pins.isEmpty {
            return allowUnpinned ? (.useCredential, URLCredential(trust: trust)) : (.cancelAuthenticationChallenge, nil)
        }
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else {
            return (.cancelAuthenticationChallenge, nil)
        }
        for certificate in chain {
            if let hash = Self.spkiHash(of: certificate), pins.contains(hash) {
                return (.useCredential, URLCredential(trust: trust))
            }
        }
        return (.cancelAuthenticationChallenge, nil)
    }

    /// Base64(SHA-256(SPKI)). Matches `openssl x509 -pubkey | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64`.
    static func spkiHash(of certificate: SecCertificate) -> String? {
        guard let key = SecCertificateCopyKey(certificate),
              let keyData = SecKeyCopyExternalRepresentation(key, nil) as Data?,
              let attributes = SecKeyCopyAttributes(key) as? [CFString: Any],
              let type = attributes[kSecAttrKeyType] as? String,
              let size = attributes[kSecAttrKeySizeInBits] as? Int else { return nil }
        guard let header = spkiHeader(type: type, bits: size) else { return nil }
        let spki = header + keyData
        return Data(SHA256.hash(data: spki)).base64EncodedString()
    }

    /// SecKey gives the raw key; SPKI needs the ASN.1 algorithm header prepended.
    private static func spkiHeader(type: String, bits: Int) -> Data? {
        switch (type, bits) {
        case (kSecAttrKeyTypeRSA as String, 2048):
            return Data([0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
                         0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00])
        case (kSecAttrKeyTypeRSA as String, 4096):
            return Data([0x30, 0x82, 0x02, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
                         0x01, 0x05, 0x00, 0x03, 0x82, 0x02, 0x0f, 0x00])
        case (kSecAttrKeyTypeECSECPrimeRandom as String, 256):
            return Data([0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a,
                         0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00])
        case (kSecAttrKeyTypeECSECPrimeRandom as String, 384):
            return Data([0x30, 0x76, 0x30, 0x10, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x05, 0x2b,
                         0x81, 0x04, 0x00, 0x22, 0x03, 0x62, 0x00])
        default:
            return nil
        }
    }
}
