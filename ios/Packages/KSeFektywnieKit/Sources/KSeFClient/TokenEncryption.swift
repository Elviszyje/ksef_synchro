import Foundation
import Security

/// Szyfrowanie tokena KSeF kluczem publicznym Ministerstwa (RSA-OAEP, SHA-256).
enum TokenEncryption {
    /// `base64(RSA-OAEP-SHA256("{token}|{timestampMs}"))` — jak `_encrypt_token` w Django.
    static func encrypt(token: String, timestampMs: Int64, certificateDER: Data) throws -> String {
        guard let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData),
              let publicKey = SecCertificateCopyKey(certificate) else {
            throw KSeFError.authentication("Nie można odczytać certyfikatu klucza publicznego KSeF.")
        }
        let plaintext = Data("\(token)|\(timestampMs)".utf8)
        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(publicKey, .rsaEncryptionOAEPSHA256, plaintext as CFData, &error) else {
            let message = error.map { CFErrorCopyDescription($0.takeRetainedValue()) as String } ?? "nieznany błąd"
            throw KSeFError.authentication("Szyfrowanie tokena nie powiodło się: \(message)")
        }
        return (encrypted as Data).base64EncodedString()
    }
}
