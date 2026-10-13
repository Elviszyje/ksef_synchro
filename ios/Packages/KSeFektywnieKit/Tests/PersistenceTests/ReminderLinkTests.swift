import Foundation
import Testing
import GRDB
import Domain
@testable import Persistence

@Suite("Powiązania z Przypomnieniami")
struct ReminderLinkTests {
    let db: AppDatabase
    let company: Company
    let invoices: InvoiceRepository
    let links: ReminderLinkRepository
    let account: CompanyBankAccount

    init() throws {
        db = try AppDatabase.inMemory()
        company = Company(nip: "1111111111", name: "F")
        account = CompanyBankAccount(companyID: company.id, accountNumber: "61109010140000071219812874")
        try db.writer.write { [company, account] in try company.insert($0); try account.insert($0) }
        invoices = InvoiceRepository(db: db, companyID: company.id, device: "d")
        links = ReminderLinkRepository(db: db, companyID: company.id)
    }

    func invoice(_ ref: String) -> Invoice {
        Invoice(companyID: company.id, ksefReferenceNumber: ref, invoiceNumber: ref, amountGross: 10,
                issueDate: LocalDate(year: 2026, month: 10, day: 1)!, bankAccountNumber: "11114010100000123456789012", status: .accepted)
    }

    @Test("Zapis, nadpisanie i usunięcie powiązania")
    func linkLifecycle() throws {
        let a = invoice("A")
        try invoices.upsertFromKSeF([a])
        #expect(try links.identifier(for: .invoice(a.id)) == nil)
        try links.link(.invoice(a.id), identifier: "R1")
        try links.link(.invoice(a.id), identifier: "R2")
        #expect(try links.identifier(for: .invoice(a.id)) == "R2")
        try links.unlink(.invoice(a.id))
        #expect(try links.identifier(for: .invoice(a.id)) == nil)
    }

    @Test("Do odhaczenia: opłacona faktura i w pełni rozliczona paczka")
    func finished() throws {
        let a = invoice("A"), b = invoice("B"), c = invoice("C")
        try invoices.upsertFromKSeF([a, b, c])
        let payments = PaymentFileRepository(db: db, companyID: company.id, device: "d")
        let file = try payments.generate(invoiceIDs: [a.id, b.id], debitAccount: account,
                                         payer: PaymentPayer(debitAccount: account.accountNumber, name: "F", address: ""))
        try links.link(.invoice(a.id), identifier: "inv-A")
        try links.link(.invoice(c.id), identifier: "inv-C")
        try links.link(.paymentFile(file.id), identifier: "file")
        #expect(try links.finished().isEmpty)

        try invoices.changeStatus(a.id, to: .paid)
        #expect(try links.finished().map(\.identifier) == ["inv-A"])

        try invoices.changeStatus(b.id, to: .paid)
        #expect(Set(try links.finished().map(\.identifier)) == ["inv-A", "file"])
        #expect(!(try links.finished().map(\.identifier)).contains("inv-C"))
    }
}
