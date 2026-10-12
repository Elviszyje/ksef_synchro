import Foundation
import Domain
import KSeFClient
import Persistence

/// Synchronizacja faktur zakupowych — port `sync_ksef_invoices` z Celery.
///
/// Różnica względem Django: metadane wszystkich faktur są zapisywane od razu,
/// a treść XML pobierana partiami z trwałej kolejki. KSeF pozwala pobrać ok. 64 XML
/// na godzinę, więc pierwsza synchronizacja większej firmy trwa wiele godzin —
/// kolejka przetrwa zamknięcie aplikacji i jest kontynuowana przy kolejnym uruchomieniu.
public struct KSeFSyncService: Sendable {
    public struct Result: Equatable, Sendable {
        public var fetched: Int
        public var new: Int
        public var xmlDownloaded: Int
        public var xmlPending: Int
        /// Kiedy KSeF pozwoli pobierać XML dalej (po limicie 429).
        public var xmlResumesAt: Date?
    }

    let company: Company
    let source: any KSeFInvoiceSource
    let invoices: InvoiceRepository
    let store: SyncStore
    let device: String

    public init(company: Company, source: any KSeFInvoiceSource, db: AppDatabase, device: String) {
        self.company = company
        self.source = source
        self.invoices = InvoiceRepository(db: db, companyID: company.id, device: device)
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

            log.currentStage = "Pobieranie treści faktur…"
            try store.save(log)
            progress(log.currentStage)
            let (downloaded, resumesAt) = try await downloadXML(now: now, budget: xmlBudget, today: today)

            log.status = .success
            log.currentStage = ""
            log.finishedAt = Date()
            try store.save(log)
            return Result(fetched: fromMetadata.count, new: newCount, xmlDownloaded: downloaded,
                          xmlPending: try store.pendingXMLCount(), xmlResumesAt: resumesAt)
        } catch {
            log.status = .error
            log.errorMessage = error.localizedDescription
            log.currentStage = ""
            log.finishedAt = Date()
            try? store.save(log)
            throw error
        }
    }

    /// Pobiera XML z kolejki. Przy 429 wstrzymuje kolejkę do czasu podanego przez KSeF.
    public func downloadXML(now: Date = Date(), budget: Int, today: LocalDate? = nil) async throws -> (Int, Date?) {
        var downloaded = 0
        for ksefNumber in try store.pendingXML(now: now, limit: budget) {
            let xml: Data?
            do {
                xml = try await source.invoiceXML(ksefNumber: ksefNumber)
            } catch KSeFError.rateLimited(let seconds) {
                let until = now.addingTimeInterval(TimeInterval(seconds))
                try store.postponeQueue(until: until)
                return (downloaded, until)
            }
            if let xml {
                let parsed = FAParser.parse(xml, ksefReferenceNumber: ksefNumber)
                let invoice = InvoiceMapping.invoice(from: parsed, companyID: company.id, today: today ?? LocalDate(now),
                                                     now: now, device: device)
                try invoices.upsertFromKSeF([invoice], now: now)
                downloaded += 1
            }
            // 404: KSeF nie udostępnia treści — faktura zostaje z metadanymi.
            try store.dequeue(ksefNumber)
        }
        return (downloaded, try store.nextQueueAttempt())
    }
}
