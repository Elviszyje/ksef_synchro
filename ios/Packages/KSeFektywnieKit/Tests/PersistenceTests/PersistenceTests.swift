import Foundation
import Testing
import GRDB
import Domain
@testable import Persistence

@Suite("Baza danych")
struct PersistenceTests {
    let db: AppDatabase
    let company: Company
    let account: CompanyBankAccount
    let invoices: InvoiceRepository
    let payments: PaymentFileRepository

    init() throws {
        db = try AppDatabase.inMemory()
        company = Company(nip: "1132854320", name: "Moja Firma", address: "ul. Żółkiewskiego 15")
        account = CompanyBankAccount(companyID: company.id, accountNumber: "61 1090 1014 0000 0712 1981 2874", isDefault: true)
        try db.writer.write { [company, account] db in
            try company.insert(db)
            try account.insert(db)
        }
        invoices = InvoiceRepository(db: db, companyID: company.id, device: "test-device")
        payments = PaymentFileRepository(db: db, companyID: company.id, device: "test-device")
    }

    func invoice(_ ref: String, gross: Decimal = 1446, status: InvoiceStatus = .new, account: String = "11114010100000123456789012") -> Invoice {
        Invoice(companyID: company.id, ksefReferenceNumber: ref, invoiceNumber: "FV/\(ref)", sellerName: "Sprzedawca \(ref)",
                sellerNIP: "5260250274", amountNet: 1200, amountVAT: 246, amountGross: gross,
                issueDate: LocalDate(year: 2026, month: 10, day: 1)!, paymentDueDate: LocalDate(year: 2026, month: 10, day: 15)!,
                bankAccountNumber: account, status: status)
    }

    @Test("Faktura zapisuje się i odczytuje bez utraty precyzji")
    func roundTrip() throws {
        var inv = invoice("A", gross: Decimal(string: "1234567.89")!)
        inv.vatAmountSplit = Decimal(string: "0.01")
        inv.rawXML = "<xml>ąę</xml>"
        try invoices.upsertFromKSeF([inv])
        let loaded = try #require(try invoices.find(inv.id))
        #expect(loaded.amountGross == Decimal(string: "1234567.89"))
        #expect(loaded.vatAmountSplit == Decimal(string: "0.01"))
        #expect(loaded.issueDate == inv.issueDate)
        #expect(loaded.paymentDueDate == inv.paymentDueDate)
        #expect(loaded.rawXML == inv.rawXML)
        #expect(loaded.companyID == company.id)
    }

    @Test("Ponowna synchronizacja scala zamiast dublować i zachowuje status")
    func upsertMerges() throws {
        let first = invoice("A")
        #expect(try invoices.upsertFromKSeF([first]) == 1)
        try invoices.changeStatus(first.id, to: .accepted, note: "ok")
        try invoices.updateNotes(first.id, notes: "notatka")

        var again = invoice("A", gross: 1500)
        again.bankAccountNumber = ""
        #expect(try invoices.upsertFromKSeF([again, invoice("B")]) == 1)

        let all = try invoices.fetch()
        #expect(all.count == 2)
        let a = try #require(all.first { $0.ksefReferenceNumber == "A" })
        #expect(a.id == first.id)
        #expect(a.status == .accepted)
        #expect(a.notes == "notatka")
        #expect(a.amountGross == 1500)
        #expect(a.bankAccountNumber == "11114010100000123456789012")
    }

    @Test("Zapłata w XML oznacza fakturę jako opłaconą z wpisem w historii")
    func paymentDateMarksPaid() throws {
        let first = invoice("A")
        try invoices.upsertFromKSeF([first])
        var paid = invoice("A")
        paid.paymentDate = LocalDate(year: 2026, month: 10, day: 3)
        try invoices.upsertFromKSeF([paid])
        #expect(try invoices.find(first.id)?.status == .paid)
        #expect(try invoices.statusLog(first.id).first?.change.to == .paid)
    }

    @Test("Zmiana statusu waliduje przejścia i zapisuje historię")
    func statusChange() throws {
        let inv = invoice("A")
        try invoices.upsertFromKSeF([inv])
        try invoices.changeStatus(inv.id, to: .disputed, note: "zła kwota")
        #expect(throws: InvoiceStatusError.self) { try invoices.changeStatus(inv.id, to: .sentForPayment) }
        let log = try invoices.statusLog(inv.id)
        #expect(log.count == 1)
        #expect(log[0].change.note == "zła kwota")
        #expect(log[0].device == "test-device")
    }

    @Test("Cofnięcie zmiany statusu z listy")
    func revert() throws {
        let inv = invoice("A")
        try invoices.upsertFromKSeF([inv])
        try invoices.changeStatus(inv.id, to: .accepted)
        // Reguły nie pozwalają wrócić z "Do zapłaty" do "Nowa" — cofnięcie musi to umieć.
        #expect(try invoices.revertStatus(inv.id, from: .accepted, to: .new))
        #expect(try invoices.find(inv.id)?.status == .new)
        #expect(try invoices.statusLog(inv.id).first?.change.note == "Cofnięto zmianę statusu.")
        // Gdy w międzyczasie status się zmienił, cofnięcie niczego nie robi.
        try invoices.changeStatus(inv.id, to: .disputed)
        #expect(try !invoices.revertStatus(inv.id, from: .accepted, to: .new))
        #expect(try invoices.find(inv.id)?.status == .disputed)
    }

    @Test("Filtry listy")
    func filters() throws {
        try invoices.upsertFromKSeF([invoice("A"), invoice("B", status: .accepted), invoice("C", status: .paid)])
        var f = InvoiceFilter()
        f.statuses = [.accepted, .paid]
        #expect(try invoices.fetch(f).count == 2)
        f = InvoiceFilter()
        f.search = "FV/B"
        #expect(try invoices.fetch(f).map(\.ksefReferenceNumber) == ["B"])
        f = InvoiceFilter()
        f.overdueOnly = true
        #expect(try invoices.fetch(f, today: LocalDate(year: 2026, month: 10, day: 20)!).count == 2)
    }

    @Test("Dane innej firmy są niewidoczne")
    func companyIsolation() throws {
        let other = Company(nip: "5260250274", name: "Inna")
        try db.writer.write { try other.insert($0) }
        let otherRepo = InvoiceRepository(db: db, companyID: other.id, device: "x")
        try otherRepo.upsertFromKSeF([invoice("A")])
        try invoices.upsertFromKSeF([invoice("A")])
        #expect(try invoices.fetch().count == 1)
        #expect(try otherRepo.fetch().count == 1)
    }

    @Test("Generowanie pliku przelewów i reset paczki")
    func paymentFileLifecycle() throws {
        let a = invoice("A", status: .accepted)
        let b = invoice("B", gross: 100, status: .accepted)
        let notAccepted = invoice("C")
        try invoices.upsertFromKSeF([a, b, notAccepted])
        #expect(Set(try payments.payableInvoices().map(\.id)) == [a.id, b.id])

        #expect(throws: PaymentFileError.invoiceNotPayable(invoiceNumber: "FV/C")) {
            try payments.generate(invoiceIDs: [notAccepted.id], debitAccount: account,
                                  payer: PaymentPayer(debitAccount: account.accountNumber, name: "Moja Firma", address: ""))
        }

        let file = try payments.generate(
            invoiceIDs: [a.id, b.id], debitAccount: account,
            payer: PaymentPayer(debitAccount: account.accountNumber, name: company.name, address: company.address),
            date: LocalDate(year: 2026, month: 10, day: 11)!)
        #expect(file.format == .erste)
        #expect(file.fileName == "przelewy_20261011_Erste_Bank.txt")
        #expect(file.totalAmount == 1546)
        #expect(CP1250.decode(file.content)?.hasPrefix("4120414|1\r\n1|61109010140000071219812874|") == true)
        #expect(try invoices.find(a.id)?.status == .sentForPayment)
        #expect(try payments.invoices(in: file.id).map(\.id) == [a.id, b.id])

        try payments.reset(file.id)
        #expect(try invoices.find(a.id)?.status == .accepted)
        #expect(try payments.files().isEmpty)
        #expect(try invoices.statusLog(a.id).map(\.change.to) == [.accepted, .sentForPayment])
    }

    @Test("Reset paczki z opłaconą fakturą jest zablokowany")
    func resetBlockedWhenPaid() throws {
        let a = invoice("A", status: .accepted)
        try invoices.upsertFromKSeF([a])
        let file = try payments.generate(invoiceIDs: [a.id], debitAccount: account,
                                         payer: PaymentPayer(debitAccount: account.accountNumber, name: "F", address: ""))
        try invoices.changeStatus(a.id, to: .paid)
        #expect(throws: PaymentFileError.paidInvoiceInBatch) { try payments.reset(file.id) }
    }

    @Test("Usunięcie firmy usuwa jej dane")
    func cascade() throws {
        try invoices.upsertFromKSeF([invoice("A")])
        _ = try db.writer.write { [company] in try company.delete($0) }
        #expect(try db.reader.read { try Invoice.fetchCount($0) } == 0)
    }
}
