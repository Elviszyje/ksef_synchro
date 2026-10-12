import Foundation
import Testing
import GRDB
import Domain
@testable import Persistence

@Suite("Wyciągi: import, dopasowanie, zatwierdzenie")
struct StatementRepositoryTests {
    let db: AppDatabase
    let company: Company
    let invoices: InvoiceRepository
    let statements: StatementRepository

    static let mt940 = """
        :20:MT940
        :25:/PL61109010140000071219812874
        :60F:C261010PLN100000,00
        :61:2610121012D1446,00NTRFNONREF
        :86:Faktura FV/30/09/2026 NIP 5260250274
        :61:2610121012D999,99NTRF
        :86:Bez opisu
        :61:2610131013D50,00NTRF
        :86:Nic wspolnego
        :61:261013C5000,00NTRF
        :86:Wplata
        :62F:C261013PLN97554,01
        """

    init() throws {
        db = try AppDatabase.inMemory()
        company = Company(nip: "1111111111", name: "Firma")
        try db.writer.write { [company] in try company.insert($0) }
        invoices = InvoiceRepository(db: db, companyID: company.id, device: "d")
        statements = StatementRepository(db: db, companyID: company.id, device: "d")
        func inv(_ ref: String, _ number: String, _ nip: String, _ gross: Decimal, _ status: InvoiceStatus) -> Invoice {
            Invoice(companyID: company.id, ksefReferenceNumber: ref, invoiceNumber: number, sellerName: "S \(ref)", sellerNIP: nip,
                    amountGross: gross, issueDate: LocalDate(year: 2026, month: 10, day: 1)!,
                    bankAccountNumber: "11114010100000123456789012", status: status)
        }
        try invoices.upsertFromKSeF([
            inv("A", "FV/0030/09/2026", "5260250274", 1446, .sentForPayment),
            inv("B", "X/1", "1830166138", Decimal(string: "999.99")!, .sentForPayment),
            inv("C", "Y/1", "2860913907", 50, .accepted),
        ])
    }

    func id(_ ref: String) throws -> UUID { try #require(try invoices.fetch().first { $0.ksefReferenceNumber == ref }).id }

    func review(_ statementID: UUID) throws -> [ReviewedTransaction] {
        try statements.review(statementID)
    }

    @Test("Import dopasowuje tylko faktury przekazane do opłacenia, z poziomem pewności jak w Django")
    func importMatches() throws {
        let s = try statements.importStatement(fileName: "wyciag.sta", data: Data(Self.mt940.utf8))
        #expect(s.fileFormat == "mt940")
        #expect(s.statementDate == LocalDate(year: 2026, month: 10, day: 10))
        let rows = try review(s.id)
        #expect(rows.count == 4)
        #expect(rows.last?.transaction.isDebit == false)
        let byAmount = Dictionary(uniqueKeysWithValues: rows.map { ($0.transaction.amount, $0) })
        #expect(byAmount[1446]?.matches.first?.invoice.ksefReferenceNumber == "A")
        #expect(byAmount[1446]?.matches.first?.match.confidence == .high)
        #expect(byAmount[Decimal(string: "999.99")!]?.matches.first?.match.confidence == .low)
        #expect(byAmount[50]?.matches.isEmpty == true, "faktura zaakceptowana nie jest kandydatem automatycznym")
    }

    @Test("Zatwierdzenie oznacza jako opłacone tylko potwierdzone dopasowania")
    func confirmFlow() throws {
        let s = try statements.importStatement(fileName: "wyciag.sta", data: Data(Self.mt940.utf8))
        #expect(throws: StatementRepositoryError.nothingConfirmed) { try statements.confirm(s.id) }

        let rows = try review(s.id)
        let high = try #require(rows.first { $0.transaction.amount == 1446 }?.matches.first?.match)
        try statements.setConfirmed(high.id, true)

        let fifty = try #require(rows.first { $0.transaction.amount == 50 }?.transaction)
        #expect(try statements.manualCandidates(for: fifty).first?.ksefReferenceNumber == "C")
        try statements.assignManually(transactionID: fifty.id, invoiceID: try id("C"))

        #expect(try statements.confirm(s.id) == 2)
        #expect(try invoices.find(try id("A"))?.status == .paid)
        #expect(try invoices.find(try id("B"))?.status == .sentForPayment)
        #expect(try invoices.find(try id("C"))?.status == .paid)
        #expect(try invoices.statusLog(try id("A")).first?.change.note == "Zatwierdzony wyciąg wyciag.sta")
        #expect(try statements.statement(s.id)?.status == .confirmed)
        #expect(throws: StatementRepositoryError.alreadyConfirmed) { try statements.confirm(s.id) }
    }

    @Test("Podsumowania i usuwanie wyciągu")
    func summariesAndDelete() throws {
        let s = try statements.importStatement(fileName: "wyciag.sta", data: Data(Self.mt940.utf8))
        let summary = try #require(try statements.summaries().first)
        #expect(summary.debitCount == 3)
        #expect(summary.matchCount == 2)
        #expect(summary.confirmedCount == 0)
        try statements.delete(s.id)
        #expect(try db.reader.read { try BankTransaction.fetchCount($0) } == 0)
        #expect(try invoices.fetch().count == 3)
    }

    @Test("Nierozpoznany plik")
    func unknownFormat() {
        #expect(throws: StatementError.unrecognizedFormat) {
            try statements.importStatement(fileName: "x.txt", data: Data("to nie wyciąg".utf8))
        }
    }
}
