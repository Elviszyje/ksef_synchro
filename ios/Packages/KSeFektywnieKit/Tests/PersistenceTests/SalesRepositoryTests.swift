import Foundation
import Testing
import GRDB
import Domain
@testable import Persistence

@Suite("Faktury sprzedażowe, katalog i nabywcy")
struct SalesRepositoryTests {
    let db: AppDatabase
    let company: Company
    let sales: SalesRepository
    let catalog: CatalogRepository

    init() throws {
        db = try AppDatabase.inMemory()
        company = Company(nip: "1111111111", name: "Firma Demo")
        try db.writer.write { [company] in try company.insert($0) }
        sales = SalesRepository(db: db, companyID: company.id, device: "d")
        catalog = CatalogRepository(db: db, companyID: company.id, device: "d")
    }

    func draft(_ number: String = "FV/2026/0001", items: [OutgoingInvoiceItem], basis: String = "") -> OutgoingInvoice {
        OutgoingInvoice(companyID: company.id, invoiceNumber: number, issueDate: LocalDate(year: 2026, month: 10, day: 12)!,
                        paymentDueDate: LocalDate(year: 2026, month: 10, day: 26)!, bankAccountNumber: "61109010140000071219812874",
                        buyerNIP: "6260181591", buyerName: "Klient", buyerAddress: "ul. Kupiecka 1",
                        exemptionBasis: basis, items: items)
    }

    @Test("Zapis szkicu zapamiętuje pozycje i nabywcę, odczyt zwraca te same dane")
    func saveAndRemember() throws {
        let items = [OutgoingInvoiceItem(name: "Konsultacje IT", unit: "h", quantity: Decimal(string: "12.5")!, unitPriceNet: 200),
                     OutgoingInvoiceItem(name: "Szkolenie BHP", unit: "os.", quantity: 3, unitPriceNet: 350, vatRate: .exempt)]
        let saved = try sales.saveDraft(draft(items: items, basis: "art. 113 ust. 1 ustawy o VAT"), saveBuyer: true)

        let loaded = try #require(try sales.find(saved.id))
        #expect(loaded.items.map(\.name) == ["Konsultacje IT", "Szkolenie BHP"])
        #expect(loaded.items[0].quantity == Decimal(string: "12.5"))
        #expect(loaded.amountGross == 4125)
        #expect(loaded.exemptionBasis == "art. 113 ust. 1 ustawy o VAT")
        #expect(loaded.buyerID != nil)

        let entries = try catalog.items()
        #expect(entries.map(\.name).sorted() == ["Konsultacje IT", "Szkolenie BHP"])
        #expect(try sales.buyers(matching: "626").map(\.name) == ["Klient"])
        #expect(try sales.exemptionSuggestions().first == "art. 113 ust. 1 ustawy o VAT")
    }

    @Test("Ponowne użycie pozycji aktualizuje cenę i licznik, katalog sortuje po użyciu")
    func reuse() throws {
        try sales.saveDraft(draft(items: [OutgoingInvoiceItem(name: "Papier", unit: "ryza", unitPriceNet: 20),
                                          OutgoingInvoiceItem(name: "Toner", unitPriceNet: 300)]), saveBuyer: false)
        try sales.saveDraft(draft("FV/2026/0002", items: [OutgoingInvoiceItem(name: "Papier", unit: "ryza", unitPriceNet: 22, vatRate: .reduced8)]),
                            saveBuyer: false)
        let entries = try catalog.items()
        #expect(entries.first?.name == "Papier")
        #expect(entries.first?.useCount == 2)
        #expect(entries.first?.unitPriceNet == 22)
        #expect(entries.first?.vatRate == .reduced8)
        #expect(try catalog.items(matching: "ton").map(\.name) == ["Toner"])
        #expect(try sales.buyers().isEmpty)

        let made = entries[0].makeItem()
        #expect(made.unitPriceNet == 22 && made.quantity == 1)
    }

    @Test("Usunięcie z katalogu nie zmienia faktur")
    func deleteKeepsInvoices() throws {
        let saved = try sales.saveDraft(draft(items: [OutgoingInvoiceItem(name: "Papier", unitPriceNet: 20)]), saveBuyer: false)
        try catalog.delete(try #require(catalog.items().first).id)
        #expect(try catalog.items().isEmpty)
        #expect(try sales.find(saved.id)?.items.count == 1)
    }

    @Test("Walidacja: ZW bez podstawy i duplikat numeru")
    func validation() throws {
        #expect(throws: SalesError.invalid([.missingExemptionBasis])) {
            try sales.saveDraft(draft(items: [OutgoingInvoiceItem(name: "Szkolenie", unitPriceNet: 1, vatRate: .exempt)]), saveBuyer: false)
        }
        try sales.saveDraft(draft(items: [OutgoingInvoiceItem(name: "A", unitPriceNet: 1)]), saveBuyer: false)
        #expect(throws: SalesError.duplicateNumber("FV/2026/0001")) {
            try sales.saveDraft(draft(items: [OutgoingInvoiceItem(name: "B", unitPriceNet: 1)]), saveBuyer: false)
        }
        #expect(try sales.nextNumber(pattern: company.invoiceNumberPattern, year: 2026, environment: .test) == "FV/2026/0002")
        #expect(try sales.nextNumber(pattern: company.invoiceNumberPattern, year: 2026, environment: .production) == "FV/2026/0001")
    }

    @Test("Edycja szkicu zastępuje pozycje")
    func editReplacesItems() throws {
        var saved = try sales.saveDraft(draft(items: [OutgoingInvoiceItem(name: "A", unitPriceNet: 1),
                                                      OutgoingInvoiceItem(name: "B", unitPriceNet: 2)]), saveBuyer: false)
        saved.items = [OutgoingInvoiceItem(name: "C", unitPriceNet: 3)]
        try sales.saveDraft(saved, saveBuyer: false)
        #expect(try sales.find(saved.id)?.items.map(\.name) == ["C"])
        #expect(try sales.invoices().count == 1)
        try sales.deleteDraft(saved.id)
        #expect(try sales.invoices().isEmpty)
    }

    @Test("Migracja v1 → v2 zachowuje dane")
    func migrationFromV1() throws {
        let queue = try DatabaseQueue()
        var v1 = DatabaseMigrator()
        v1.registerMigration("v1", migrate: Schema.v1)
        try v1.migrate(queue)
        try queue.write { db in
            try db.execute(sql: "INSERT INTO company (id, nip, name, createdAt, updatedAt) VALUES (?, '1111111111', 'F', ?, ?)",
                           arguments: [company.id, Date(), Date()])
            try db.execute(sql: """
                INSERT INTO outgoingInvoice (id, companyId, invoiceNumber, issueDate, paymentDueDate, paymentForm, buyerNip, buyerName,
                buyerAddress, status, environment, createdAt, updatedAt) VALUES (?, ?, 'FV/1', '2026-10-01', '2026-10-15', 'przelew',
                '6260181591', 'K', '', 'draft', 'test', ?, ?)
                """, arguments: [UUID(), company.id, Date(), Date()])
        }
        let migrated = try AppDatabase(queue)
        let invoice = try #require(try SalesRepository(db: migrated, companyID: company.id, device: "d").invoices().first)
        #expect(invoice.exemptionType == .act)
        #expect(invoice.exemptionBasis == "")
    }
}
