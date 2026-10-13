import CoreTransferable
import Domain
import Foundation
import UIKit
import UniformTypeIdentifiers

/// Dane eksportu bieżącej listy faktur. Pliki powstają dopiero w chwili udostępnienia.
nonisolated struct InvoiceExport: Sendable {
    let invoices: [Invoice]
    let companyName: String
    let companyNIP: String
    let today: LocalDate

    var baseName: String { "\(String(localized: "Faktury"))_\(today.iso)" }

    /// Nagłówki kolumn arkusza w języku interfejsu (kolejność jak w eksporcie Excel z wersji webowej).
    static var columnTitles: [String] {
        [String(localized: "Numer faktury"), String(localized: "Nr referencyjny KSeF"), String(localized: "Sprzedawca"),
         String(localized: "NIP sprzedawcy"), String(localized: "Data wystawienia"), String(localized: "Termin płatności"),
         String(localized: "Netto"), String(localized: "VAT"), String(localized: "Brutto"), String(localized: "Waluta"),
         String(localized: "MPP"), String(localized: "Status"), String(localized: "Konto bankowe"), String(localized: "Notatki")]
    }

    func xlsx() -> Data {
        InvoiceSpreadsheet.make(invoices, titles: Self.columnTitles, statusLabel: { String(localized: $0.label) },
                                yes: String(localized: "Tak"), no: String(localized: "Nie"),
                                totalLabel: String(localized: "Razem"), sheetName: String(localized: "Faktury"), today: today).xlsx()
    }

    func write(_ data: Data, ext: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "\(baseName).\(ext)")
        try data.write(to: url, options: .atomic)
        return url
    }
}

nonisolated struct InvoiceXLSXFile: Transferable {
    let export: InvoiceExport
    static let contentType = UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: contentType) { file in
            SentTransferredFile(try file.export.write(file.export.xlsx(), ext: "xlsx"))
        }
    }
}

nonisolated struct InvoicePDFFile: Transferable {
    let export: InvoiceExport

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { file in
            SentTransferredFile(try file.export.write(InvoicePDF(export: file.export).render(), ext: "pdf"))
        }
    }
}

/// Zestawienie faktur w PDF: A4 poziomo, tabela z powtarzanym nagłówkiem, sumy według walut, numeracja stron.
nonisolated struct InvoicePDF {
    let export: InvoiceExport

    static let page = CGRect(x: 0, y: 0, width: 842, height: 595)
    static let margin: CGFloat = 32
    static let rowHeight: CGFloat = 24
    static let headerRowHeight: CGFloat = 28
    static let titleBlockHeight: CGFloat = 64
    static let footerHeight: CGFloat = 28

    static let brand = UIColor(red: 0x1A / 255, green: 0x56 / 255, blue: 0xDB / 255, alpha: 1)
    static let overdue = UIColor(red: 0xFE / 255, green: 0xE2 / 255, blue: 0xE2 / 255, alpha: 1)
    static let stripe = UIColor(white: 0.96, alpha: 1)
    static let secondary = UIColor(white: 0.42, alpha: 1)

    struct Column {
        let title: String
        let width: CGFloat
        let alignment: NSTextAlignment
    }

    var columns: [Column] {
        [Column(title: String(localized: "Lp."), width: 24, alignment: .right),
         Column(title: String(localized: "Numer faktury"), width: 108, alignment: .left),
         Column(title: String(localized: "Sprzedawca"), width: 142, alignment: .left),
         Column(title: String(localized: "Data wystawienia"), width: 62, alignment: .left),
         Column(title: String(localized: "Termin płatności"), width: 62, alignment: .left),
         Column(title: String(localized: "Netto"), width: 74, alignment: .right),
         Column(title: String(localized: "VAT"), width: 64, alignment: .right),
         Column(title: String(localized: "Brutto"), width: 78, alignment: .right),
         Column(title: String(localized: "Waluta"), width: 44, alignment: .center),
         Column(title: String(localized: "MPP"), width: 28, alignment: .center),
         Column(title: String(localized: "Status"), width: 92, alignment: .left)]
    }

    static func amount(_ d: Decimal) -> String { d.formatted(.number.precision(.fractionLength(2))) }
    static func date(_ d: LocalDate?) -> String { d.map { $0.date().formatted(date: .numeric, time: .omitted) } ?? "—" }

    /// Podział wierszy na strony; pierwsza strona ma blok tytułowy.
    func pages() -> [Range<Int>] {
        let usable = Self.page.height - 2 * Self.margin - Self.footerHeight - Self.headerRowHeight
        let first = max(1, Int((usable - Self.titleBlockHeight) / Self.rowHeight))
        let next = max(1, Int(usable / Self.rowHeight))
        var result: [Range<Int>] = [], start = 0
        let count = export.invoices.count
        while start < count || result.isEmpty {
            let size = result.isEmpty ? first : next
            result.append(start..<min(count, start + size))
            start += size
        }
        return result
    }

    var totals: [(currency: String, net: Decimal, vat: Decimal, gross: Decimal)] {
        Dictionary(grouping: export.invoices, by: \.currency).map { currency, list in
            (currency, list.reduce(0) { $0 + $1.amountNet }, list.reduce(0) { $0 + $1.amountVAT }, list.reduce(0) { $0 + $1.amountGross })
        }.sorted { $0.currency < $1.currency }
    }

    func render() -> Data {
        var pageRanges = pages()
        let summaryHeight = 30 + CGFloat(totals.count) * 16
        let lastUsed = (pageRanges.count == 1 ? Self.titleBlockHeight : 0) + Self.headerRowHeight + CGFloat(pageRanges.last!.count) * Self.rowHeight
        let available = Self.page.height - 2 * Self.margin - Self.footerHeight
        let summaryOnOwnPage = lastUsed + summaryHeight > available
        if summaryOnOwnPage { pageRanges.append(export.invoices.count..<export.invoices.count) }

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: String(localized: "Zestawienie faktur kosztowych"),
                               kCGPDFContextCreator as String: "KS-eFektywnie"]
        let renderer = UIGraphicsPDFRenderer(bounds: Self.page, format: format)
        return renderer.pdfData { context in
            for (index, range) in pageRanges.enumerated() {
                context.beginPage()
                var y = Self.margin
                if index == 0 { y = drawTitle(y) }
                let isSummaryPage = summaryOnOwnPage && index == pageRanges.count - 1
                if !isSummaryPage {
                    y = drawHeaderRow(y)
                    for row in range { y = drawRow(row, y) }
                }
                if index == pageRanges.count - 1 { drawSummary(y + 12) }
                drawFooter(page: index + 1, of: pageRanges.count)
            }
        }
    }

    // MARK: Rysowanie

    static func attributes(_ size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor = .black,
                           alignment: NSTextAlignment = .left) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        let font = weight == .regular && size < 10 ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
                                                    : UIFont.systemFont(ofSize: size, weight: weight)
        return [.font: font, .foregroundColor: color, .paragraphStyle: style]
    }

    /// Tekst w jednej linii, wyśrodkowany pionowo w prostokącie.
    static func draw(_ text: String, in rect: CGRect, _ attrs: [NSAttributedString.Key: Any]) {
        let font = attrs[.font] as! UIFont
        let line = font.lineHeight
        let r = CGRect(x: rect.minX, y: rect.midY - line / 2, width: rect.width, height: line)
        (text as NSString).draw(with: r, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs, context: nil)
    }

    /// Tekst do dwóch linii (nagłówki kolumn), wyśrodkowany pionowo.
    static func drawWrapped(_ text: String, in rect: CGRect, _ attrs: [NSAttributedString.Key: Any]) {
        var attrs = attrs
        let style = (attrs[.paragraphStyle] as! NSParagraphStyle).mutableCopy() as! NSMutableParagraphStyle
        style.lineBreakMode = .byWordWrapping
        attrs[.paragraphStyle] = style
        let font = attrs[.font] as! UIFont
        let options: NSStringDrawingOptions = [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        let maxHeight = ceil(font.lineHeight * 2) + 1
        let bounds = (text as NSString).boundingRect(with: CGSize(width: rect.width, height: maxHeight), options: options,
                                                     attributes: attrs, context: nil)
        let height = min(maxHeight, ceil(bounds.height))
        (text as NSString).draw(with: CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height),
                                options: options, attributes: attrs, context: nil)
    }

    func drawTitle(_ y: CGFloat) -> CGFloat {
        let width = Self.page.width - 2 * Self.margin
        Self.draw(String(localized: "Zestawienie faktur kosztowych"), in: CGRect(x: Self.margin, y: y, width: width, height: 22),
                  Self.attributes(16, weight: .bold))
        Self.draw("KS-eFektywnie", in: CGRect(x: Self.margin, y: y, width: width, height: 22),
                  Self.attributes(10, weight: .semibold, color: Self.brand, alignment: .right))
        var company = export.companyName
        if !export.companyNIP.isEmpty { company += " · NIP \(export.companyNIP)" }
        Self.draw(company, in: CGRect(x: Self.margin, y: y + 24, width: width, height: 14), Self.attributes(10))
        let info = String(localized: "Wygenerowano: \(Self.date(export.today)) · Liczba faktur: \(export.invoices.count)")
        Self.draw(info, in: CGRect(x: Self.margin, y: y + 40, width: width, height: 14), Self.attributes(9, color: Self.secondary))
        return y + Self.titleBlockHeight
    }

    func drawHeaderRow(_ y: CGFloat) -> CGFloat {
        Self.brand.setFill()
        UIRectFill(CGRect(x: Self.margin, y: y, width: Self.page.width - 2 * Self.margin, height: Self.headerRowHeight))
        var x = Self.margin
        for column in columns {
            Self.drawWrapped(column.title, in: CGRect(x: x + 3, y: y, width: column.width - 6, height: Self.headerRowHeight),
                             Self.attributes(7.5, weight: .bold, color: .white, alignment: column.alignment))
            x += column.width
        }
        return y + Self.headerRowHeight
    }

    func drawRow(_ index: Int, _ y: CGFloat) -> CGFloat {
        let invoice = export.invoices[index]
        let rect = CGRect(x: Self.margin, y: y, width: Self.page.width - 2 * Self.margin, height: Self.rowHeight)
        if invoice.isOverdue(today: export.today) {
            Self.overdue.setFill(); UIRectFill(rect)
        } else if index % 2 == 1 {
            Self.stripe.setFill(); UIRectFill(rect)
        }
        let values = [String(index + 1), invoice.invoiceNumber, invoice.sellerName, Self.date(invoice.issueDate),
                      Self.date(invoice.paymentDueDate), Self.amount(invoice.amountNet), Self.amount(invoice.amountVAT),
                      Self.amount(invoice.amountGross), invoice.currency, invoice.isSplitPayment ? String(localized: "Tak") : "—",
                      String(localized: invoice.status.label)]
        var x = Self.margin
        for (column, value) in zip(columns, values) {
            let cell = CGRect(x: x + 3, y: y, width: column.width - 6, height: Self.rowHeight)
            if column.title == String(localized: "Sprzedawca") && !invoice.sellerNIP.isEmpty {
                Self.draw(value, in: cell.offsetBy(dx: 0, dy: -5), Self.attributes(8.5, alignment: column.alignment))
                Self.draw("NIP \(invoice.sellerNIP)", in: cell.offsetBy(dx: 0, dy: 5),
                          Self.attributes(6.5, color: Self.secondary, alignment: column.alignment))
            } else if column.title == String(localized: "Status") {
                Self.drawWrapped(value, in: cell, Self.attributes(8, alignment: column.alignment))
            } else {
                let weight: UIFont.Weight = column.title == String(localized: "Brutto") ? .semibold : .regular
                Self.draw(value, in: cell, Self.attributes(8.5, weight: weight, alignment: column.alignment))
            }
            x += column.width
        }
        return y + Self.rowHeight
    }

    func drawSummary(_ y: CGFloat) {
        let width = Self.page.width - 2 * Self.margin
        UIColor(white: 0.6, alpha: 1).setFill()
        UIRectFill(CGRect(x: Self.margin, y: y, width: width, height: 0.75))
        Self.draw(String(localized: "Razem"), in: CGRect(x: Self.margin, y: y + 6, width: 200, height: 16), Self.attributes(10, weight: .bold))
        // Sumy wyrównane do kolumn Netto, VAT, Brutto, Waluta.
        let offsets = columns.reduce(into: [CGFloat]()) { $0.append(($0.last ?? Self.margin) + $1.width) }
        func columnRect(_ i: Int, _ rowY: CGFloat) -> CGRect {
            CGRect(x: offsets[i] - columns[i].width + 3, y: rowY, width: columns[i].width - 6, height: 16)
        }
        var rowY = y + 6
        for total in totals {
            Self.draw(Self.amount(total.net), in: columnRect(5, rowY), Self.attributes(9, weight: .semibold, alignment: .right))
            Self.draw(Self.amount(total.vat), in: columnRect(6, rowY), Self.attributes(9, weight: .semibold, alignment: .right))
            Self.draw(Self.amount(total.gross), in: columnRect(7, rowY), Self.attributes(9, weight: .bold, alignment: .right))
            Self.draw(total.currency, in: columnRect(8, rowY), Self.attributes(9, weight: .semibold, alignment: .center))
            rowY += 16
        }
        if export.invoices.contains(where: { $0.isOverdue(today: export.today) }) {
            let legend = CGRect(x: Self.margin, y: rowY + 6, width: 10, height: 10)
            Self.overdue.setFill(); UIRectFill(legend)
            Self.draw(String(localized: "Po terminie płatności"), in: CGRect(x: Self.margin + 16, y: rowY + 3, width: 300, height: 16),
                      Self.attributes(8, color: Self.secondary))
        }
    }

    func drawFooter(page: Int, of total: Int) {
        let y = Self.page.height - Self.margin - 12
        let width = Self.page.width - 2 * Self.margin
        Self.draw("KS-eFektywnie · \(Self.date(export.today))", in: CGRect(x: Self.margin, y: y, width: width, height: 12),
                  Self.attributes(7.5, color: Self.secondary))
        Self.draw(String(localized: "Strona \(page) z \(total)"), in: CGRect(x: Self.margin, y: y, width: width, height: 12),
                  Self.attributes(7.5, color: Self.secondary, alignment: .right))
    }
}
