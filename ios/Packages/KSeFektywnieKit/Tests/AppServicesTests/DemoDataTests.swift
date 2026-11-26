import Foundation
import Testing
import Domain
import Persistence
@testable import AppServices

@Suite("Dane demo")
struct DemoDataTests {
    @Test("Fikcyjne identyfikatory są poprawne, a XML parsuje się do tych samych kwot")
    func demo() throws {
        let db = try AppDatabase.inMemory()
        let company = try DemoData.seed(db: db, device: "d", today: LocalDate(year: 2026, month: 10, day: 11)!)
        #expect(Validation.isValidNIP(company.nip))
        for seller in DemoData.sellers {
            #expect(Validation.isValidNIP(seller.nip), "\(seller.nip)")
            #expect(Validation.isValidNRB(seller.account), "\(seller.account)")
        }
        #expect(Validation.isValidNRB("61109010140000071219812874"))
        #expect(!Validation.isValidNRB("61109010140000071219812875"))

        let sales = try SalesRepository(db: db, companyID: company.id, device: "d").invoices()
        #expect(sales.count == 2)
        #expect(sales.allSatisfy { $0.validationIssues.isEmpty })
        #expect(try CatalogRepository(db: db, companyID: company.id, device: "d").items().first?.name == "Konsultacje IT")

        let statement = try #require(try StatementRepository(db: db, companyID: company.id, device: "d").summaries().first)
        // Trzy zapłaty faktur (dwie z pełnym opisem, jedna rozpoznana po kwocie) i opłata bankowa.
        #expect(statement.debitCount == 4)
        #expect(statement.matchCount == 3)

        let invoices = try InvoiceRepository(db: db, companyID: company.id, device: "d").fetch()
        // 8 bieżących + 2 czekające na wyciąg + historia: 11 miesięcy × 2 stałe koszty + 6 większych zakupów.
        #expect(invoices.count == 8 + 2 + 22 + 6)
        #expect(invoices.filter { $0.issueDate < LocalDate(year: 2026, month: 9, day: 1)! }.allSatisfy { $0.status == .paid })
        #expect(Set(invoices.map(\.status)) == Set(InvoiceStatus.allCases))
        // Dane demo pokazują ostrzeżenie o zmianie rachunku dokładnie przy jednej fakturze (serwis IT).
        #expect(Validation.isValidNRB(DemoData.previousServiceAccount))
        let changed = SellerAccountCheck.changedAccounts(in: invoices, history: invoices)
        #expect(invoices.filter { changed.contains($0.id) }.map(\.invoiceNumber) == ["FV/2026/0002"])
        for invoice in invoices {
            let parsed = FAParser.parse(Data(invoice.rawXML.utf8))
            #expect(parsed.amountGross == invoice.amountGross, "\(invoice.invoiceNumber)")
            #expect(parsed.bankAccountNumber == invoice.bankAccountNumber)
            #expect(parsed.isSplitPayment == invoice.isSplitPayment)
        }
    }
}
