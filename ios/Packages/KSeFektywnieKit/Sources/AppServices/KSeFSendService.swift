import Foundation
import Domain
import KSeFClient
import Persistence

/// Wysyłka faktur sprzedażowych — abstrakcja nad `KSeFClient` dla testów.
public protocol KSeFInvoiceSender: Sendable {
    func authenticate() async throws -> KSeFClient.AccessToken
    func submitInvoices(_ invoices: [Data]) async throws -> [InvoiceSubmission]
    func invoiceStatus(_ submission: InvoiceSubmission) async throws -> SessionInvoiceStatus
    func invoiceUPO(_ submission: InvoiceSubmission) async throws -> Data
}

extension KSeFClient: KSeFInvoiceSender {}

public enum SendError: Error, Equatable, LocalizedError {
    case notFound
    case notSendable
    case environmentMismatch(invoice: KSeFEnvironment, company: KSeFEnvironment)
    case invalid([SalesValidationIssue])

    public var errorDescription: String? {
        switch self {
        case .notFound: "Nie znaleziono faktury."
        case .notSendable: "Fakturę można wysłać tylko jako szkic albo po odrzuceniu przez KSeF."
        case .environmentMismatch: "Szkic utworzono dla innego środowiska KSeF niż obecnie ustawione. Utwórz nową fakturę."
        case .invalid: "Faktura ma niekompletne dane."
        }
    }
}

/// Wysyłka FA(3) do KSeF 2.0: wygenerowanie XML, sesja interaktywna, odpytanie statusu, UPO.
/// Stan zapisywany po każdym kroku, żeby przerwanie (np. zamknięcie aplikacji) nie zgubiło referencji.
public struct KSeFSendService: Sendable {
    let company: Company
    let sender: any KSeFInvoiceSender
    let sales: SalesRepository
    let sleep: @Sendable (Duration) async throws -> Void

    public init(company: Company, sender: any KSeFInvoiceSender, db: AppDatabase, device: String,
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.company = company
        self.sender = sender
        self.sales = SalesRepository(db: db, companyID: company.id, device: device)
        self.sleep = sleep
    }

    /// Wysyła fakturę i czeka do ok. `attempts × 2 s` na wynik. Gdy KSeF nie zdąży,
    /// faktura zostaje w stanie „wysyłanie” i wynik pobierze `refresh`.
    @discardableResult
    public func send(_ invoiceID: UUID, now: Date = Date(), attempts: Int = 10) async throws -> OutgoingInvoice {
        guard let invoice = try sales.find(invoiceID) else { throw SendError.notFound }
        guard invoice.canBeEdited else { throw SendError.notSendable }
        guard invoice.environment == company.ksefEnvironment else {
            throw SendError.environmentMismatch(invoice: invoice.environment, company: company.ksefEnvironment)
        }
        let issues = invoice.validationIssues
        guard issues.isEmpty else { throw SendError.invalid(issues) }

        let seller = FA3Seller(nip: company.nip, name: company.name, address: company.address)
        let xml = try FA3Generator.generate(invoice, seller: seller, now: now)
        _ = try await sender.authenticate()
        guard let submission = try await sender.submitInvoices([Data(xml.utf8)]).first else {
            throw SendError.notFound
        }
        try sales.updateSubmission(invoiceID, now: now) {
            $0.status = .sending
            $0.generatedXML = xml
            $0.ksefSessionReference = submission.sessionReference
            $0.ksefInvoiceReference = submission.invoiceReference
            $0.ksefNumber = ""
            $0.upoXML = ""
            $0.errorMessage = ""
        }
        for attempt in 0..<attempts {
            let updated = try await refresh(invoiceID, now: now)
            if updated.status != .sending { return updated }
            if attempt < attempts - 1 { try await sleep(.seconds(2)) }
        }
        return try sales.find(invoiceID)!
    }

    /// Sprawdza status wysłanej faktury i dociąga UPO.
    @discardableResult
    public func refresh(_ invoiceID: UUID, now: Date = Date()) async throws -> OutgoingInvoice {
        guard let invoice = try sales.find(invoiceID) else { throw SendError.notFound }
        guard !invoice.ksefSessionReference.isEmpty, !invoice.ksefInvoiceReference.isEmpty else { return invoice }
        let submission = InvoiceSubmission(sessionReference: invoice.ksefSessionReference,
                                           invoiceReference: invoice.ksefInvoiceReference)
        var current = invoice
        if invoice.status == .sending {
            let status = try await sender.invoiceStatus(submission)
            if status.isAccepted {
                current = try sales.updateSubmission(invoiceID, now: now) {
                    $0.status = .accepted
                    $0.ksefNumber = status.ksefNumber ?? ""
                    $0.errorMessage = ""
                } ?? current
            } else if status.isRejected {
                return try sales.updateSubmission(invoiceID, now: now) {
                    $0.status = .rejected
                    $0.errorMessage = "KSeF \(status.code): \(status.message)"
                } ?? current
            }
        }
        if current.status == .accepted && current.upoXML.isEmpty {
            // UPO bywa dostępne z opóźnieniem — brak nie jest błędem, spróbujemy przy kolejnym odświeżeniu.
            if let upo = try? await sender.invoiceUPO(submission) {
                current = try sales.updateSubmission(invoiceID, now: now) {
                    $0.upoXML = String(decoding: upo, as: UTF8.self)
                } ?? current
            }
        }
        return current
    }

    /// Odświeża wszystkie faktury czekające na wynik lub UPO (np. przy otwarciu zakładki).
    public func refreshPending(now: Date = Date()) async {
        for invoice in (try? sales.awaitingKSeF()) ?? [] {
            _ = try? await refresh(invoice.id, now: now)
        }
    }
}
