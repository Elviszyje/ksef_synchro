import Foundation
import CryptoKit

/// Link weryfikacyjny faktury (KOD I) do kodu QR na wizualizacji — specyfikacja KSeF 2.0:
/// `https://qr.ksef.mf.gov.pl/invoice/{NIP sprzedawcy}/{DD-MM-RRRR}/{SHA-256 pliku faktury w Base64URL}`.
/// Pod kodem drukuje się numer KSeF faktury.
public enum KSeFVerification {
    public static func url(environment: KSeFEnvironment, sellerNIP: String, issueDate: LocalDate, invoiceXML: Data) -> URL {
        let date = String(format: "%02d-%02d-%04d", issueDate.day, issueDate.month, issueDate.year)
        return environment.qrBaseURL.appending(path: "invoice/\(sellerNIP)/\(date)/\(fileHash(invoiceXML))")
    }

    /// SHA-256 w Base64URL bez dopełnienia `=`.
    public static func fileHash(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension KSeFEnvironment {
    public var qrBaseURL: URL {
        switch self {
        case .test: URL(string: "https://qr-test.ksef.mf.gov.pl")!
        case .production: URL(string: "https://qr.ksef.mf.gov.pl")!
        }
    }
}

extension InvoiceDocument {
    /// Ustawia numer KSeF i link do kodu QR. Bez numeru KSeF faktura nie jest w systemie, więc kodu nie ma.
    public mutating func attachKSeF(number: String, environment: KSeFEnvironment, xml: String) {
        ksefNumber = number
        guard !number.isEmpty, let issueDate, !seller.nip.isEmpty else { verificationURL = nil; return }
        verificationURL = KSeFVerification.url(environment: environment, sellerNIP: seller.nip, issueDate: issueDate,
                                               invoiceXML: Data(xml.utf8))
    }
}
