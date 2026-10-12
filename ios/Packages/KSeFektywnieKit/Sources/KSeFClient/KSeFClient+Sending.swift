import Foundation
import Domain

/// Identyfikatory wysłanej faktury: sesja interaktywna + numer referencyjny faktury w sesji.
public struct InvoiceSubmission: Hashable, Sendable, Codable {
    public let sessionReference: String
    public let invoiceReference: String

    public init(sessionReference: String, invoiceReference: String) {
        self.sessionReference = sessionReference
        self.invoiceReference = invoiceReference
    }
}

/// Status faktury w sesji (`InvoiceStatusInfo`): 100/150 — w toku, 200 — przyjęta, ≥ 400 — odrzucona.
public struct SessionInvoiceStatus: Hashable, Sendable {
    public let code: Int
    public let description: String
    public let details: [String]
    public let ksefNumber: String?

    public init(code: Int, description: String, details: [String] = [], ksefNumber: String? = nil) {
        self.code = code
        self.description = description
        self.details = details
        self.ksefNumber = ksefNumber
    }

    public var isProcessing: Bool { code < 200 }
    public var isAccepted: Bool { code == 200 }
    public var isRejected: Bool { code >= 400 }

    /// Komunikat dla użytkownika: opis + szczegóły walidacji.
    public var message: String {
        ([description] + details).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

extension KSeFClient {
    /// FA(3): `FA (3)`, wersja schematu `1-0E`, wartość `FA`.
    static let fa3FormCode: [String: String] = ["systemCode": "FA (3)", "schemaVersion": "1-0E", "value": "FA"]

    /// Wysyła faktury w jednej sesji interaktywnej: otwarcie (nowy klucz AES), wysłanie,
    /// zamknięcie. Status i numer KSeF sprawdza się potem `invoiceStatus`.
    public func submitInvoices(_ invoices: [Data]) async throws -> [InvoiceSubmission] {
        let token = try await validToken()
        let encryption = try InvoiceEncryption.random()
        let certificate = try await certificate(usage: "SymmetricKeyEncryption")
        var encryptionInfo: [String: Any] = [
            "encryptedSymmetricKey": try encryption.encryptedKey(certificateDER: certificate.der),
            "initializationVector": encryption.iv.base64EncodedString(),
        ]
        if let keyID = certificate.publicKeyId { encryptionInfo["publicKeyId"] = keyID }

        let opened = try await json(try await send("sessions/online", method: "POST",
                                                   body: ["formCode": Self.fa3FormCode, "encryption": encryptionInfo],
                                                   bearer: token))
        guard let session = opened["referenceNumber"] as? String else {
            throw KSeFError.invalidResponse("Brak numeru sesji interaktywnej.")
        }

        var submissions: [InvoiceSubmission] = []
        for xml in invoices {
            let encrypted = try encryption.encrypt(xml)
            let body: [String: Any] = [
                "invoiceHash": InvoiceEncryption.sha256Base64(xml),
                "invoiceSize": xml.count,
                "encryptedInvoiceHash": InvoiceEncryption.sha256Base64(encrypted),
                "encryptedInvoiceSize": encrypted.count,
                "encryptedInvoiceContent": encrypted.base64EncodedString(),
            ]
            let sent = try await json(try await send("sessions/online/\(session)/invoices", method: "POST", body: body, bearer: token))
            guard let reference = sent["referenceNumber"] as? String else {
                throw KSeFError.invalidResponse("Brak numeru referencyjnego wysłanej faktury.")
            }
            submissions.append(InvoiceSubmission(sessionReference: session, invoiceReference: reference))
        }
        // Zamknięcie rozpoczyna generowanie UPO; faktury są przetwarzane niezależnie od niego.
        _ = try await send("sessions/online/\(session)/close", method: "POST", bearer: token)
        return submissions
    }

    public func invoiceStatus(_ submission: InvoiceSubmission) async throws -> SessionInvoiceStatus {
        let data = try await send("sessions/\(submission.sessionReference)/invoices/\(submission.invoiceReference)",
                                  method: "GET", bearer: try await validToken())
        let object = try await json(data)
        guard let status = object["status"] as? [String: Any], let code = (status["code"] as? NSNumber)?.intValue else {
            throw KSeFError.invalidResponse("Brak statusu faktury w odpowiedzi.")
        }
        return SessionInvoiceStatus(code: code, description: status["description"] as? String ?? "",
                                    details: status["details"] as? [String] ?? [],
                                    ksefNumber: object["ksefNumber"] as? String)
    }

    /// UPO faktury (XML). KSeF udostępnia je po przetworzeniu faktury; wcześniej zwraca błąd.
    public func invoiceUPO(_ submission: InvoiceSubmission) async throws -> Data {
        try await send("sessions/\(submission.sessionReference)/invoices/\(submission.invoiceReference)/upo",
                       method: "GET", bearer: try await validToken(), accept: "application/xml")
    }
}
