import Foundation
import Testing
@testable import Domain

@Suite("Podsumowanie kosztów i eksport CSV")
struct CostSummaryTests {
    let company = UUID()

    func inv(_ seller: String, _ nip: String, _ gross: Decimal, _ y: Int, _ m: Int, _ d: Int = 5,
             currency: String = "PLN", status: InvoiceStatus = .new, due: LocalDate? = nil) -> Invoice {
        Invoice(companyID: company, ksefReferenceNumber: UUID().uuidString, invoiceNumber: "FV/\(m)", sellerName: seller,
                sellerNIP: nip, amountGross: gross, currency: currency, issueDate: LocalDate(year: y, month: m, day: d)!,
                paymentDueDate: due, status: status)
    }

    @Test("Okno 12 miesięcy przez przełom roku, top sprzedawcy, tylko PLN")
    func summary() {
        let today = LocalDate(year: 2026, month: 2, day: 10)!
        let invoices = [
            inv("A", "1", 100, 2026, 2), inv("A", "1", 50, 2026, 2, 9), inv("B", "2", 120, 2026, 2),
            inv("C", "3", 999, 2026, 2, 11),                        // po dacie "dziś"
            inv("D", "4", 300, 2025, 3), inv("E", "5", 700, 2025, 2), // poza oknem
            inv("F", "6", 1000, 2026, 1, currency: "EUR"),
            inv("G", "7", 10, 2026, 1, status: .paid),
            inv("H", "8", 20, 2025, 12, due: LocalDate(year: 2026, month: 1, day: 1)),
        ]
        let s = CostSummary.make(invoices, today: today)
        #expect(s.months.count == 12)
        #expect(s.months.first?.id == "2025-03" && s.months.last?.id == "2026-02")
        #expect(s.months.last?.gross == 270)
        #expect(s.totalGross == 600)
        #expect(s.averageGross == 50)
        #expect(s.invoiceCount == 6)
        #expect(s.topSellers.map(\.name) == ["A", "B"])
        #expect(s.topSellers.first?.gross == 150 && s.topSellers.first?.count == 2)
        #expect(s.otherCurrencyCount == 1)
        #expect(s.overdueCount == 1)
        #expect(s.unpaidGross == Decimal(100 + 50 + 120 + 999 + 300 + 700 + 20))
    }

    @Test("CSV: średniki, przecinek dziesiętny, cytowanie, BOM")
    func csv() throws {
        var i = inv("Firma; \"Cytat\"", "5260250274", Decimal(string: "1234.5")!, 2026, 10)
        i.notes = "linia 1\nlinia 2"
        i.isSplitPayment = true
        let data = InvoiceCSV.export([i]) { $0.rawValue }
        #expect(data.prefix(3) == Data([0xEF, 0xBB, 0xBF]))
        let text = String(decoding: data.dropFirst(3), as: UTF8.self)
        let lines = text.components(separatedBy: "\r\n")
        #expect(lines[0].hasPrefix("Numer faktury;Nr referencyjny KSeF;Sprzedawca"))
        #expect(lines[1].contains(";\"Firma; \"\"Cytat\"\"\";5260250274;2026-10-05;"))
        #expect(lines[1].contains(";1234,50;PLN;TAK;nowa;"))
        #expect(lines[1].hasSuffix("\"linia 1\nlinia 2\""))
    }
}
