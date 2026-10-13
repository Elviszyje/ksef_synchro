import Foundation

/// Podsumowanie kosztów jak w dashboardzie Django: 12 miesięcy, średnia, top sprzedawcy.
/// Sumowane są tylko faktury w PLN (inne waluty wymagałyby kursów).
public struct CostSummary: Equatable, Sendable {
    public struct Month: Equatable, Sendable, Identifiable {
        public var year: Int
        public var month: Int
        public var gross: Decimal
        public var count: Int
        public var id: String { String(format: "%04d-%02d", year, month) }
    }

    public struct Seller: Equatable, Sendable, Identifiable {
        public var nip: String
        public var name: String
        public var gross: Decimal
        public var count: Int
        public var id: String { nip }
    }

    public var months: [Month]
    public var totalGross: Decimal
    public var averageGross: Decimal
    public var invoiceCount: Int
    public var topSellers: [Seller]
    public var unpaidGross: Decimal
    public var overdueCount: Int
    public var otherCurrencyCount: Int

    /// - Parameter today: koniec okna; okno obejmuje bieżący miesiąc i 11 poprzednich.
    public static func make(_ invoices: [Invoice], today: LocalDate, topCount: Int = 5) -> CostSummary {
        var windows: [(Int, Int)] = []
        var y = today.year, m = today.month
        for _ in 0..<12 {
            windows.insert((y, m), at: 0)
            m -= 1
            if m == 0 { m = 12; y -= 1 }
        }
        let start = LocalDate(year: windows[0].0, month: windows[0].1, day: 1)!
        let pln = invoices.filter { $0.currency == "PLN" }
        let inWindow = pln.filter { $0.issueDate >= start && $0.issueDate <= today }

        var byMonth: [String: (Decimal, Int)] = [:]
        for invoice in inWindow {
            let key = String(format: "%04d-%02d", invoice.issueDate.year, invoice.issueDate.month)
            let current = byMonth[key] ?? (0, 0)
            byMonth[key] = (current.0 + invoice.amountGross, current.1 + 1)
        }
        let months = windows.map { (year, month) -> Month in
            let value = byMonth[String(format: "%04d-%02d", year, month)] ?? (0, 0)
            return Month(year: year, month: month, gross: value.0, count: value.1)
        }
        let total = months.reduce(Decimal(0)) { $0 + $1.gross }

        let currentMonth = inWindow.filter { $0.issueDate.year == today.year && $0.issueDate.month == today.month }
        var sellers: [String: Seller] = [:]
        for invoice in currentMonth {
            var s = sellers[invoice.sellerNIP] ?? Seller(nip: invoice.sellerNIP, name: invoice.sellerName, gross: 0, count: 0)
            s.gross += invoice.amountGross
            s.count += 1
            sellers[invoice.sellerNIP] = s
        }
        let top = sellers.values.sorted { ($0.gross, $1.name) > ($1.gross, $0.name) }.prefix(topCount)

        let unpaid = pln.filter { $0.status != .paid && !$0.isCorrection }
        return CostSummary(
            months: months, totalGross: total, averageGross: (total / 12).rounded(scale: 2, mode: .plain),
            invoiceCount: inWindow.count, topSellers: Array(top),
            unpaidGross: unpaid.reduce(0) { $0 + $1.amountGross },
            overdueCount: invoices.filter { $0.isOverdue(today: today) }.count,
            otherCurrencyCount: invoices.count - pln.count)
    }
}

/// Zestawienie faktur do eksportu (kolumny jak w eksporcie Excel z Django).
public enum InvoiceSpreadsheet {
    /// Nagłówki kolumn w języku interfejsu dostarcza warstwa aplikacji (14 pozycji, kolejność jak niżej).
    public static let columnWidths: [Double] = [24, 34, 36, 14, 14, 14, 14, 12, 14, 8, 6, 22, 32, 36]

    public static func make(_ invoices: [Invoice], titles: [String], statusLabel: (InvoiceStatus) -> String,
                            yes: String, no: String, totalLabel: String, sheetName: String, today: LocalDate) -> Spreadsheet {
        precondition(titles.count == columnWidths.count)
        var sheet = Spreadsheet(
            sheetName: sheetName,
            columns: zip(titles, columnWidths).map { Spreadsheet.Column($0, width: $1) },
            rows: invoices.map { i in
                [.text(i.invoiceNumber), .text(i.ksefReferenceNumber), .text(i.sellerName), .text(i.sellerNIP),
                 .date(i.issueDate), i.paymentDueDate.map { .date($0) } ?? .empty,
                 .amount(i.amountNet), .amount(i.amountVAT), .amount(i.amountGross), .text(i.currency),
                 .text(i.isSplitPayment ? yes : no), .text(statusLabel(i.status)), .text(i.bankAccountNumber), .text(i.notes)]
            })
        sheet.highlightedRows = Set(invoices.indices.filter { invoices[$0].isOverdue(today: today) })
        // Sumy tylko dla jednej waluty — sumowanie PLN z EUR nie ma sensu.
        if Set(invoices.map(\.currency)).count <= 1 { sheet.totalColumns = [6, 7, 8] }
        sheet.totalLabel = totalLabel
        return sheet
    }
}
