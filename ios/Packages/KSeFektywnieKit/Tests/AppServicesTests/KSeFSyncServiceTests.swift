import Foundation
import Synchronization
import Testing
import Domain
import KSeFClient
import Persistence
@testable import AppServices

/// Atrapa KSeF: metadane, XML dla wybranych numerów, opcjonalny limit 429 po N pobraniach.
final class FakeKSeF: KSeFInvoiceSource {
    let headers: [JSONValue]
    let xml: [String: Data]
    let rateLimitAfter: Int?
    let downloads = Mutex(0)

    init(headers: [JSONValue], xml: [String: Data], rateLimitAfter: Int? = nil) {
        self.headers = headers
        self.xml = xml
        self.rateLimitAfter = rateLimitAfter
    }

    func authenticate() async throws -> KSeFClient.AccessToken { .init(token: "T", validUntil: nil) }

    func purchaseInvoiceMetadata(from: Date, to: Date, pageSize: Int) async throws -> [JSONValue] { headers }

    func invoiceXML(ksefNumber: String) async throws -> Data? {
        let n = downloads.withLock { $0 += 1; return $0 }
        if let limit = rateLimitAfter, n > limit { throw KSeFError.rateLimited(retryAfter: 600) }
        return xml[ksefNumber]
    }
}

@Suite("Synchronizacja KSeF")
struct KSeFSyncServiceTests {
    let db = try! AppDatabase.inMemory()
    let company = Company(nip: "1132854320", name: "Moja Firma")

    init() throws {
        try db.writer.write { [company] in try company.insert($0) }
    }

    static func header(_ ref: String, gross: String) -> JSONValue {
        .object(["ksefNumber": .string(ref), "invoiceNumber": .string("FV/\(ref)"), "invoiceIssueDate": .string("2026-10-01"),
                 "subjectBy": .object(["identifier": .object(["value": .string("5260250274")]), "name": .string("Hurtownia")]),
                 "gross": .string(gross)])
    }

    static let xml = Data("""
        <Faktura xmlns="http://crd.gov.pl/wzor/2025/06/25/13775/"><Podmiot1><DaneIdentyfikacyjne><NIP>5260250274</NIP>
        <Nazwa>Hurtownia Łódzka</Nazwa></DaneIdentyfikacyjne></Podmiot1><Fa><P_1>2026-10-01</P_1><P_2>FV/A</P_2>
        <P_13_1>100</P_13_1><P_14_1>23</P_14_1><P_15>123</P_15><Platnosc><TerminPlatnosci><Termin>2026-10-15</Termin></TerminPlatnosci>
        <RachunekBankowy><NrRB>11114010100000123456789012</NrRB></RachunekBankowy></Platnosc></Fa></Faktura>
        """.utf8)

    @Test("Metadane zapisane od razu, XML uzupełnia dane, kolejka się opróżnia")
    func fullSync() async throws {
        let source = FakeKSeF(headers: [Self.header("A", gross: "123"), Self.header("B", gross: "50")], xml: ["A": Self.xml])
        let service = KSeFSyncService(company: company, source: source, db: db, device: "d")
        let result = try await service.run(now: Date(timeIntervalSince1970: 1_790_000_000))
        #expect(result == .init(fetched: 2, new: 2, xmlDownloaded: 1, xmlPending: 0, xmlResumesAt: nil))

        let repo = InvoiceRepository(db: db, companyID: company.id, device: "d")
        let a = try #require(try repo.fetch().first { $0.ksefReferenceNumber == "A" })
        #expect(a.sellerName == "Hurtownia Łódzka")
        #expect(a.bankAccountNumber == "11114010100000123456789012")
        #expect(a.paymentDueDate == LocalDate(year: 2026, month: 10, day: 15))
        let b = try #require(try repo.fetch().first { $0.ksefReferenceNumber == "B" })
        #expect(b.rawXML.isEmpty)
        #expect(b.sellerName == "Hurtownia")

        let logs = try SyncStore(db: db, companyID: company.id).logs()
        #expect(logs.first?.status == .success)
        #expect(logs.first?.invoicesNew == 2)
    }

    @Test("Limit 429 wstrzymuje kolejkę, kolejny przebieg ją kontynuuje")
    func rateLimitedQueueResumes() async throws {
        let headers = (1...3).map { Self.header("R\($0)", gross: "10") }
        let xml = Dictionary(uniqueKeysWithValues: (1...3).map { ("R\($0)", Self.xml) })
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let limited = KSeFSyncService(company: company, source: FakeKSeF(headers: headers, xml: xml, rateLimitAfter: 1), db: db, device: "d")
        let first = try await limited.run(now: now)
        #expect(first.xmlDownloaded == 1)
        #expect(first.xmlPending == 2)
        #expect(first.xmlResumesAt == now.addingTimeInterval(600))

        let store = SyncStore(db: db, companyID: company.id)
        #expect(try store.pendingXML(now: now.addingTimeInterval(60), limit: 10).isEmpty)

        let later = KSeFSyncService(company: company, source: FakeKSeF(headers: [], xml: xml), db: db, device: "d")
        let (downloaded, resumesAt) = try await later.downloadXML(now: now.addingTimeInterval(700), budget: 10)
        #expect(downloaded == 2)
        #expect(resumesAt == nil)
        #expect(try store.pendingXMLCount() == 0)
    }

    @Test("Błąd autoryzacji trafia do logu")
    func errorLogged() async throws {
        struct Failing: KSeFInvoiceSource {
            func authenticate() async throws -> KSeFClient.AccessToken { throw KSeFError.api(status: 401, message: "x") }
            func purchaseInvoiceMetadata(from: Date, to: Date, pageSize: Int) async throws -> [JSONValue] { [] }
            func invoiceXML(ksefNumber: String) async throws -> Data? { nil }
        }
        let service = KSeFSyncService(company: company, source: Failing(), db: db, device: "d")
        await #expect(throws: KSeFError.self) { try await service.run() }
        let log = try #require(try SyncStore(db: db, companyID: company.id).logs().first)
        #expect(log.status == .error)
        #expect(log.errorMessage.contains("401"))
    }
}
