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

    @Test("Zestawienie faktur: wiersze, wyróżnienie przeterminowanych, sumy tylko dla jednej waluty")
    func spreadsheet() {
        var overdue = inv("A", "1", 100, 2026, 9, due: LocalDate(year: 2026, month: 9, day: 30))
        overdue.isSplitPayment = true
        let ok = inv("B", "2", 50, 2026, 10)
        let titles = (1...14).map { "K\($0)" }
        let sheet = InvoiceSpreadsheet.make([overdue, ok], titles: titles, statusLabel: { $0.rawValue }, yes: "TAK", no: "NIE",
                                            totalLabel: "Razem", sheetName: "Faktury", today: LocalDate(year: 2026, month: 10, day: 13)!)
        #expect(sheet.rows.count == 2)
        #expect(sheet.rows[0][8] == .amount(100))
        #expect(sheet.rows[0][10] == .text("TAK"))
        #expect(sheet.rows[1][5] == .empty)
        #expect(sheet.highlightedRows == [0])
        #expect(sheet.totalColumns == [6, 7, 8])
        let mixed = InvoiceSpreadsheet.make([ok, inv("C", "3", 10, 2026, 10, currency: "EUR")], titles: titles, statusLabel: { $0.rawValue },
                                            yes: "T", no: "N", totalLabel: "R", sheetName: "F", today: LocalDate(year: 2026, month: 10, day: 13)!)
        #expect(mixed.totalColumns.isEmpty)
    }
}
