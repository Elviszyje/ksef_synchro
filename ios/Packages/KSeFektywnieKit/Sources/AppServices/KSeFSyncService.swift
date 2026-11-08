import Foundation
import Domain
import KSeFClient
import Persistence

/// Synchronizacja faktur z KSeF — port `sync_ksef_invoices` z Celery.
///
/// Różnica względem Django: metadane wszystkich faktur są zapisywane od razu,
/// a treść XML pobierana partiami z trwałej kolejki. KSeF pozwala pobrać ok. 64 XML
/// na godzinę, więc pierwsza synchronizacja większej firmy trwa wiele godzin —
/// kolejka przetrwa zamknięcie aplikacji i jest kontynuowana przy kolejnym uruchomieniu.
///
/// Faktury sprzedażowe wystawione poza aplikacją (firma jako sprzedawca) trafiają do tej
/// samej kolejki, ale za fakturami zakupowymi; powstają dopiero z pobranego XML,
/// bo bez niego nie da się odtworzyć pozycji.
public struct KSeFSyncService: Sendable {
    public struct Result: Equatable, Sendable {
        public var fetched: Int
        public var new: Int
        public var xmlDownloaded: Int
        public var xmlPending: Int
        /// Kiedy KSeF pozwoli pobierać XML dalej (po limicie 429).
        public var xmlResumesAt: Date?
        /// Zaimportowane faktury sprzedażowe wystawione poza aplikacją.
        public var salesNew = 0
        /// Szkice, które dostały nowy numer, bo ich numer był już użyty w KSeF.
        public var salesRenumbered: [String] = []
        /// Faktury sprzedażowe czekające w kolejce na pobranie treści.
        public var salesPending = 0
        /// Błąd etapu sprzedaży — nie przerywa synchronizacji zakupów.
        public var salesError: String?
    }

    /// Pierwszy import sprzedaży sięga do startu obowiązkowego KSeF (1.02.2026), ale nie dalej niż rok wstecz.
    public static func initialSalesFrom(_ now: Date) -> Date {
        let mandatoryStart = ISO8601DateFormatter().date(from: "2026-02-01T00:00:00Z")!
        return max(mandatoryStart, now.addingTimeInterval(-365 * 24 * 3600))
    }

    let company: Company
    let source: any KSeFInvoiceSource
    let invoices: InvoiceRepository
    let sales: SalesRepository
    let store: SyncStore
    let device: String

    public init(company: Company, source: any KSeFInvoiceSource, db: AppDatabase, device: String) {
        self.company = company
        self.source = source
        self.invoices = InvoiceRepository(db: db, companyID: company.id, device: device)
        self.sales = SalesRepository(db: db, companyID: company.id, device: device)
        self.store = SyncStore(db: db, companyID: company.id)
        self.device = device
    }

    /// - Parameters:
    ///   - from: początek zakresu; domyślnie ostatnia synchronizacja albo 30 dni wstecz.
    ///   - xmlBudget: ile XML pobrać w tym przebiegu (limit KSeF ok. 64/h).
    public func run(from: Date? = nil, now: Date = Date(), xmlBudget: Int = 20,
                    progress: @Sendable (String) -> Void = { _ in }) async throws -> Result {
        var log = SyncLogEntry(companyID: company.id, startedAt: now, currentStage: "Autoryzacja…")
        try store.save(log)
        do {
            progress(log.currentStage)
            _ = try await source.authenticate()

            log.currentStage = "Pobieranie listy faktur…"
            try store.save(log)
            progress(log.currentStage)
            let dateFrom = from ?? company.lastSyncAt ?? now.addingTimeInterval(-30 * 24 * 3600)
            let headers = try await source.purchaseInvoiceMetadata(from: dateFrom, to: now, pageSize: 250)
            let today = LocalDate(now)
            let fromMetadata = headers
                .map { InvoiceMapping.parsed(fromMetadata: $0, buyerNIPFallback: company.nip) }
                .filter { !$0.ksefReferenceNumber.isEmpty }
                .map { InvoiceMapping.invoice(from: $0, companyID: company.id, today: today, now: now, device: device) }
            let newCount = try invoices.upsertFromKSeF(fromMetadata, now: now)
            try store.enqueueMissingXML(now: now)
            try store.markSynced(at: now)
            log.invoicesFetched = fromMetadata.count
            log.invoicesNew = newCount

            log.currentStage = "Pobieranie listy faktur sprzedażowych…"
            try store.save(log)
            progress(log.currentStage)
            let salesError = await enqueueSales(from: from, now: now)

            log.currentStage = "Pobieranie treści faktur…"
            try store.save(log)
            progress(log.currentStage)
            let report = try await downloadQueue(now: now, budget: xmlBudget, today: today)

            log.status = .success
            log.currentStage = ""
            log.finishedAt = Date()
            try store.save(log)
            return Result(fetched: fromMetadata.count, new: newCount, xmlDownloaded: report.downloaded,
                          xmlPending: try store.pendingXMLCount(), xmlResumesAt: report.resumesAt,
                          salesNew: report.salesNew, salesRenumbered: report.salesRenumbered,
                          salesPending: try store.pendingXMLCount(kind: .sale), salesError: salesError)
        } catch {
            log.status = .error
            log.errorMessage = error.localizedDescription
            log.currentStage = ""
            log.finishedAt = Date()
            try? store.save(log)
            throw error
        }
    }

    /// Kolejkuje faktury sprzedażowe, których jeszcze nie znamy. Kursor przesuwa się tylko po udanym
    /// zapytaniu; błąd jest zwracany (nie rzucany), żeby nie przerywać synchronizacji zakupów.
    func enqueueSales(from: Date?, now: Date) async -> String? {
        do {
            let salesFrom = try from ?? store.lastSalesSync() ?? Self.initialSalesFrom(now)
            let headers = try await source.salesInvoiceMetadata(from: salesFrom, to: now, pageSize: 250)
            var unknown: [String] = []
            for header in headers {
                let ksefNumber = JSONValue.firstTruthy(header["ksefNumber"], header["ksefReferenceNumber"]).stringValue
                guard !ksefNumber.isEmpty else { continue }
                let number = JSONValue.firstTruthy(header["invoiceNumber"], header["invoiceNo"]).stringValue
                if try !sales.isKnown(ksefNumber: ksefNumber, invoiceNumber: number, environment: company.ksefEnvironment) {
                    unknown.append(ksefNumber)
                }
            }
            try store.enqueueSales(unknown, now: now)
            try store.markSalesSynced(at: now)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Pobiera XML z kolejki. Przy 429 wstrzymuje kolejkę do czasu podanego przez KSeF.
    public func downloadXML(now: Date = Date(), budget: Int, today: LocalDate? = nil) async throws -> (Int, Date?) {
        let report = try await downloadQueue(now: now, budget: budget, today: today)
        return (report.downloaded, report.resumesAt)
    }

    struct DownloadReport {
        var downloaded = 0
        var resumesAt: Date?
        var salesNew = 0
        var salesRenumbered: [String] = []
    }

    func downloadQueue(now: Date, budget: Int, today: LocalDate?) async throws -> DownloadReport {
        var report = DownloadReport()
        for entry in try store.pendingXML(now: now, limit: budget) {
            let xml: Data?
            do {
                xml = try await source.invoiceXML(ksefNumber: entry.ksefNumber)
            } catch KSeFError.rateLimited(let seconds) {
                let until = now.addingTimeInterval(TimeInterval(seconds))
                try store.postponeQueue(until: until)
                report.resumesAt = until
                return report
            }
            if let xml {
                report.downloaded += 1
                switch entry.kind {
                case .purchase:
                    let parsed = FAParser.parse(xml, ksefReferenceNumber: entry.ksefNumber)
                    let invoice = InvoiceMapping.invoice(from: parsed, companyID: company.id, today: today ?? LocalDate(now),
                                                         now: now, device: device)
                    try invoices.upsertFromKSeF([invoice], now: now)
                case .sale:
                    // Nieczytelny XML: faktura zostaje pominięta (bez pozycji nie da się jej odtworzyć).
                    // Błąd zapisu jednej faktury nie blokuje kolejki — wpis i tak jest usuwany.
                    if let invoice = SalesImport.invoice(xml: xml, ksefNumber: entry.ksefNumber, companyID: company.id,
                                                         environment: company.ksefEnvironment, now: now, device: device) {
                        switch try? sales.importFromKSeF(invoice, numberPattern: company.invoiceNumberPattern, now: now) {
                        case .imported: report.salesNew += 1
                        case .importedRenumberingDraft(let from, _):
                            report.salesNew += 1
                            report.salesRenumbered.append(from)
                        case .alreadyKnown, nil: break
                        }
                    }
                }
            }
            // 404: KSeF nie udostępnia treści — faktura zakupowa zostaje z metadanymi, sprzedażowa jest pomijana.
            try store.dequeue(entry.ksefNumber)
        }
        report.resumesAt = try store.nextQueueAttempt()
        return report
    }
}
