import Foundation
import CommonCrypto
import CryptoKit
import Security

/// Szyfrowanie faktur dla sesji interaktywnej KSeF 2.0:
/// AES-256-CBC z PKCS#7, klucz 32 B i IV 16 B losowane na sesję,
/// klucz symetryczny szyfrowany RSA-OAEP (SHA-256) certyfikatem `SymmetricKeyEncryption`.
struct InvoiceEncryption: Sendable {
    let key: Data
    let iv: Data

    static func random() throws -> InvoiceEncryption {
        InvoiceEncryption(key: try randomBytes(32), iv: try randomBytes(16))
    }

    static func randomBytes(_ count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        guard status == errSecSuccess else { throw KSeFError.invalidResponse("Brak losowości systemowej (\(status)).") }
        return data
    }

    func encrypt(_ plaintext: Data) throws -> Data {
        try crypt(plaintext, operation: CCOperation(kCCEncrypt))
    }

    func decrypt(_ ciphertext: Data) throws -> Data {
        try crypt(ciphertext, operation: CCOperation(kCCDecrypt))
    }

    private func crypt(_ input: Data, operation: CCOperation) throws -> Data {
        var output = Data(count: input.count + kCCBlockSizeAES128)
        var moved = 0
        let outputCapacity = output.count
        let status = output.withUnsafeMutableBytes { out in
            input.withUnsafeBytes { inp in
                key.withUnsafeBytes { k in
                    iv.withUnsafeBytes { v in
                        CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                k.baseAddress, key.count, v.baseAddress,
                                inp.baseAddress, input.count, out.baseAddress, outputCapacity, &moved)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw KSeFError.invalidResponse("Błąd szyfrowania AES (\(status)).") }
        output.removeSubrange(moved...)
        return output
    }

    /// Klucz symetryczny zaszyfrowany kluczem publicznym MF, w Base64.
    func encryptedKey(certificateDER: Data) throws -> String {
        guard let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData),
              let publicKey = SecCertificateCopyKey(certificate) else {
            throw KSeFError.invalidResponse("Nie można odczytać certyfikatu klucza publicznego KSeF.")
        }
        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(publicKey, .rsaEncryptionOAEPSHA256, key as CFData, &error) else {
            throw KSeFError.invalidResponse("Szyfrowanie klucza nie powiodło się.")
        }
        return (encrypted as Data).base64EncodedString()
    }

    static func sha256Base64(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).base64EncodedString()
    }
}
