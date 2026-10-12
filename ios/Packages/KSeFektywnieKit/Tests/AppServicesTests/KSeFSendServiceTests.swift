import Foundation
import Synchronization
import Testing
import Domain
import KSeFClient
import Persistence
@testable import AppServices

final class FakeSender: KSeFInvoiceSender {
    let statuses: Mutex<[SessionInvoiceStatus]>
    let upoAvailable: Mutex<Bool>
    let submitted = Mutex<[Data]>([])

    init(statuses: [SessionInvoiceStatus], upoAvailable: Bool = true) {
        self.statuses = Mutex(statuses)
        self.upoAvailable = Mutex(upoAvailable)
    }

    func authenticate() async throws -> KSeFClient.AccessToken { .init(token: "T", validUntil: nil) }

    func submitInvoices(_ invoices: [Data]) async throws -> [InvoiceSubmission] {
        submitted.withLock { $0 += invoices }
        return [InvoiceSubmission(sessionReference: "S", invoiceReference: "I")]
    }

    func invoiceStatus(_ submission: InvoiceSubmission) async throws -> SessionInvoiceStatus {
        statuses.withLock { $0.count > 1 ? $0.removeFirst() : $0[0] }
    }

    func invoiceUPO(_ submission: InvoiceSubmission) async throws -> Data {
        guard upoAvailable.withLock({ $0 }) else { throw KSeFError.api(status: 404, message: "brak UPO") }
        return Data("<UPO/>".utf8)
    }
}

func status(_ code: Int, ksef: String? = nil, _ description: String = "", details: [String] = []) -> SessionInvoiceStatus {
    SessionInvoiceStatus(code: code, description: description, details: details, ksefNumber: ksef)
}

@Suite("Wysyłka faktur do KSeF")
struct KSeFSendServiceTests {
    let db = try! AppDatabase.inMemory()
    let company = Company(nip: "1111111111", name: "Firma Demo", address: "ul. Testowa 1", ksefEnvironment: .test)
    let sales: SalesRepository
    let draftID: UUID

    init() throws {
        try db.writer.write { [company] in try company.insert($0) }
        sales = SalesRepository(db: db, companyID: company.id, device: "d")
        let draft = OutgoingInvoice(companyID: company.id, invoiceNumber: "FV/2026/0001",
                                    issueDate: LocalDate(year: 2026, month: 10, day: 12)!,
                                    paymentDueDate: LocalDate(year: 2026, month: 10, day: 26)!,
                                    bankAccountNumber: "61109010140000071219812874", buyerNIP: "6260181591", buyerName: "Klient",
                                    environment: .test, items: [OutgoingInvoiceItem(name: "Usługa", unitPriceNet: 100)])
        draftID = try sales.saveDraft(draft, saveBuyer: false).id
    }

    func service(_ sender: FakeSender) -> KSeFSendService {
        KSeFSendService(company: company, sender: sender, db: db, device: "d", sleep: { _ in })
    }

    @Test("Przyjęta: numer KSeF, XML FA(3) i UPO zapisane")
    func accepted() async throws {
        let sender = FakeSender(statuses: [status(150), status(200, ksef: "1111111111-20261012-AAAA-01")])
        let result = try await service(sender).send(draftID)
        #expect(result.status == .accepted)
        #expect(result.ksefNumber == "1111111111-20261012-AAAA-01")
        #expect(result.upoXML == "<UPO/>")
        #expect(result.generatedXML.contains("<P_2>FV/2026/0001</P_2>"))
        #expect(sender.submitted.withLock { $0 }.first.map { String(decoding: $0, as: UTF8.self) } == result.generatedXML)
        #expect(try sales.find(draftID)?.ksefSessionReference == "S")
    }

    @Test("Odrzucona: komunikat KSeF, możliwa poprawka i ponowna wysyłka")
    func rejectedThenFixed() async throws {
        let rejected = try await service(FakeSender(statuses: [status(450, "Błąd semantyki", details: ["Zły NIP"])])).send(draftID)
        #expect(rejected.status == .rejected)
        #expect(rejected.errorMessage == "KSeF 450: Błąd semantyki\nZły NIP")
        #expect(rejected.canBeEdited)

        var fixed = try #require(try sales.find(draftID))
        fixed.buyerName = "Klient poprawiony"
        try sales.saveDraft(fixed, saveBuyer: false)
        #expect(try sales.find(draftID)?.status == .draft)

        let accepted = try await service(FakeSender(statuses: [status(200, ksef: "K")])).send(draftID)
        #expect(accepted.status == .accepted)
        #expect(accepted.errorMessage.isEmpty)
    }

    @Test("Wynik nieznany po limicie prób, UPO dociągane później")
    func pendingThenRefresh() async throws {
        let slow = FakeSender(statuses: [status(150)], upoAvailable: false)
        let pending = try await service(slow).send(draftID, attempts: 3)
        #expect(pending.status == .sending)

        let later = FakeSender(statuses: [status(200, ksef: "K")], upoAvailable: false)
        let accepted = try await service(later).refresh(draftID)
        #expect(accepted.status == .accepted && accepted.upoXML.isEmpty)
        #expect(try sales.awaitingKSeF().map(\.id) == [draftID])

        later.upoAvailable.withLock { $0 = true }
        await service(later).refreshPending()
        #expect(try sales.find(draftID)?.upoXML == "<UPO/>")
        #expect(try sales.awaitingKSeF().isEmpty)
    }

    @Test("Blokady: przyjętej nie wysyłamy ponownie, środowisko musi się zgadzać")
    func guards() async throws {
        _ = try await service(FakeSender(statuses: [status(200, ksef: "K")])).send(draftID)
        await #expect(throws: SendError.notSendable) { try await service(FakeSender(statuses: [status(200)])).send(draftID) }
        #expect(throws: SalesError.notEditable) { try sales.deleteDraft(draftID) }

        var prod = company
        prod.ksefEnvironment = .production
        let other = try sales.saveDraft(OutgoingInvoice(companyID: company.id, invoiceNumber: "FV/2026/0002",
                                                        issueDate: LocalDate(year: 2026, month: 10, day: 12)!,
                                                        paymentDueDate: LocalDate(year: 2026, month: 10, day: 26)!,
                                                        paymentForm: .cash, buyerNIP: "6260181591", buyerName: "K", environment: .test,
                                                        items: [OutgoingInvoiceItem(name: "A", unitPriceNet: 1)]), saveBuyer: false)
        let prodService = KSeFSendService(company: prod, sender: FakeSender(statuses: [status(200)]), db: db, device: "d", sleep: { _ in })
        await #expect(throws: SendError.environmentMismatch(invoice: .test, company: .production)) { try await prodService.send(other.id) }
    }
}
