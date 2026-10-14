import CoreImage
import CoreImage.CIFilterBuiltins
import CoreTransferable
import Domain
import UIKit
import UniformTypeIdentifiers

/// Wizualizacja pojedynczej faktury w PDF (A4 pionowo): nagłówek, strony, pozycje z powtarzanym
/// nagłówkiem tabeli, podsumowanie VAT, płatność, kod QR KSeF, adnotacje i stopka z numeracją stron.
/// Wygląd zależy od szablonu (układ, kolor, logo, język etykiet).
nonisolated struct InvoiceVisualizationPDF {
    let prepared: PreparedInvoiceDocument
    let template: InvoiceTemplate
    /// Faktura kosztowa: stopka informuje, że dokumentem jest XML w KSeF.
    var isCostInvoice = false

    typealias Attrs = [NSAttributedString.Key: Any]

    static let page = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
    static let margin: CGFloat = 36
    static let width = page.width - 2 * margin
    static let ink = UIColor(white: 0.1, alpha: 1)
    static let secondary = UIColor(white: 0.42, alpha: 1)
    static let rule = UIColor(white: 0.8, alpha: 1)
    static let stripe = UIColor(white: 0.965, alpha: 1)

    var doc: InvoiceDocument { prepared.document }
    var labels: InvoiceLabels { InvoiceLabels(template.language) }
    var layout: InvoiceLayout { template.layout }

    var accent: UIColor { mix(1) }
    /// Kolor akcentu rozjaśniony do bieli (`amount` = udział akcentu), bez przezroczystości.
    func mix(_ amount: Double) -> UIColor {
        let c = template.accentRGB
        return UIColor(red: 1 - (1 - c.red) * amount, green: 1 - (1 - c.green) * amount, blue: 1 - (1 - c.blue) * amount, alpha: 1)
    }

    // MARK: - Składanie stron

    /// Fragment strony o stałej wysokości. `header` (nagłówek tabeli) jest powtarzany po przejściu na nową stronę.
    struct Block {
        var height: CGFloat
        var spacing: CGFloat = 0
        var header: Header?
        var draw: (CGFloat) -> Void
    }

    struct Header {
        var height: CGFloat
        var draw: (CGFloat) -> Void
    }

    func render() -> Data {
        let footer = footerHeight
        let top = Self.margin, bottom = Self.page.height - Self.margin - footer - 8
        var pages: [[(draw: (CGFloat) -> Void, y: CGFloat)]] = [[]]
        var y = top
        for block in blocks() {
            if !pages[pages.count - 1].isEmpty && y + block.spacing + block.height > bottom {
                pages.append([])
                y = top
                if let header = block.header {
                    pages[pages.count - 1].append((header.draw, y))
                    y += header.height
                }
            } else if !pages[pages.count - 1].isEmpty {
                y += block.spacing
            }
            pages[pages.count - 1].append((block.draw, y))
            y += block.height
        }

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "\(labels.title(doc.kind)) \(doc.number)",
                               kCGPDFContextAuthor as String: doc.seller.name,
                               kCGPDFContextCreator as String: "KS-eFektywnie"]
        return UIGraphicsPDFRenderer(bounds: Self.page, format: format).pdfData { context in
            for (index, items) in pages.enumerated() {
                context.beginPage()
                if prepared.isDraft { drawWatermark(context.cgContext) }
                for item in items { item.draw(item.y) }
                drawFooter(page: index + 1, of: pages.count, height: footer)
            }
        }
    }

    func blocks() -> [Block] {
        var result = [headerBlock(), partiesBlock()]
        if let correction = correctionBlock() { result.append(correction) }
        result += itemBlocks()
        result.append(summaryBlock())
        result.append(totalsBlock())
        result.append(paymentBlock())
        if let notes = notesBlock() { result.append(notes) }
        if template.showSignatureFields { result.append(signaturesBlock()) }
        return result
    }

    // MARK: - Tekst

    static func attrs(_ size: CGFloat, _ weight: UIFont.Weight = .regular, _ color: UIColor = ink,
                      align: NSTextAlignment = .left, mono: Bool = false, italic: Bool = false) -> Attrs {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineBreakMode = .byWordWrapping
        // Cyfry o stałej szerokości w drobnym tekście, żeby kwoty w kolumnach się wyrównywały.
        var font = mono ? UIFont.monospacedSystemFont(ofSize: size, weight: weight)
            : size < 11 ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : UIFont.systemFont(ofSize: size, weight: weight)
        if italic, let descriptor = font.fontDescriptor.withSymbolicTraits(.traitItalic) { font = UIFont(descriptor: descriptor, size: size) }
        return [.font: font, .foregroundColor: color, .paragraphStyle: style]
    }

    static func text(_ string: String, _ attrs: Attrs) -> NSAttributedString { NSAttributedString(string: string, attributes: attrs) }

    /// „Etykieta: wartość” — etykieta szara, wartość w kolorze tekstu.
    static func pair(_ label: String, _ value: String, size: CGFloat = 8.5, bold: Bool = false) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text("\(label): ", attrs(size, .regular, secondary)))
        result.append(text(value, attrs(size, bold ? .semibold : .regular)))
        return result
    }

    static func lines(_ items: [NSAttributedString]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, item) in items.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n", attributes: item.attributes(at: 0, effectiveRange: nil))) }
            result.append(item)
        }
        return result
    }

    static func height(_ string: NSAttributedString, _ width: CGFloat) -> CGFloat {
        guard string.length > 0 else { return 0 }
        return ceil(string.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                        options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
    }

    static func draw(_ string: NSAttributedString, _ rect: CGRect) {
        string.draw(with: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(rect.height, height(string, rect.width))),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }

    static func fill(_ rect: CGRect, _ color: UIColor, radius: CGFloat = 0) {
        color.setFill()
        if radius > 0 { UIBezierPath(roundedRect: rect, cornerRadius: radius).fill() } else { UIRectFill(rect) }
    }

    static func stroke(_ rect: CGRect, _ color: UIColor, width: CGFloat = 0.6, radius: CGFloat = 0) {
        color.setStroke()
        let path = radius > 0 ? UIBezierPath(roundedRect: rect.insetBy(dx: width / 2, dy: width / 2), cornerRadius: radius)
                              : UIBezierPath(rect: rect.insetBy(dx: width / 2, dy: width / 2))
        path.lineWidth = width
        path.stroke()
    }

    static func hline(_ y: CGFloat, from x: CGFloat = margin, width: CGFloat = width, color: UIColor = rule, thickness: CGFloat = 0.6) {
        fill(CGRect(x: x, y: y, width: width, height: thickness), color)
    }

    func money(_ value: Decimal) -> String { "\(labels.amount(value)) \(doc.currency)" }

    // MARK: - Nagłówek

    var logo: UIImage? { template.logoPNG.flatMap(UIImage.init(data:)) }

    func logoRect(_ image: UIImage, in box: CGRect) -> CGRect {
        let scale = min(box.width / image.size.width, box.height / image.size.height, 1.5)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(x: box.minX, y: box.minY + (box.height - size.height) / 2, width: size.width, height: size.height)
    }

    var headerDates: [NSAttributedString] {
        var rows: [NSAttributedString] = []
        if let date = doc.issueDate { rows.append(Self.pair(labels.issueDate, labels.date(date), size: 9, bold: true)) }
        if !doc.issuePlace.isEmpty { rows.append(Self.pair(labels.issuePlace, doc.issuePlace, size: 9)) }
        if let period = doc.salePeriod {
            rows.append(Self.pair(labels.salePeriod, "\(labels.date(period.lowerBound)) – \(labels.date(period.upperBound))", size: 9))
        } else if let sale = doc.saleDate {
            rows.append(Self.pair(labels.saleDate, labels.date(sale), size: 9))
        }
        return rows
    }

    func headerBlock() -> Block {
        let title = labels.title(doc.kind)
        let number = "\(labels.numberPrefix) \(doc.number)"
        switch layout {
        case .modern:
            // Pas w kolorze akcentu od krawędzi strony; daty pod pasem w jednym wierszu.
            let band: CGFloat = 104
            let dates = Self.text(headerDates.map(\.string).joined(separator: "   ·   "), Self.attrs(9, .regular, Self.secondary))
            let datesHeight = Self.height(dates, Self.width)
            return Block(height: band - Self.margin + 14 + datesHeight) { y in
                Self.fill(CGRect(x: 0, y: 0, width: Self.page.width, height: band), accent)
                let textWidth = Self.width - (logo == nil ? 0 : 150)
                Self.draw(Self.text(title, Self.attrs(22, .bold, .white)), CGRect(x: Self.margin, y: 30, width: textWidth, height: 28))
                Self.draw(Self.text(number, Self.attrs(13, .semibold, UIColor(white: 1, alpha: 0.9))),
                          CGRect(x: Self.margin, y: 60, width: textWidth, height: 18))
                if let logo {
                    let box = CGRect(x: Self.page.width - Self.margin - 140, y: 22, width: 140, height: 60)
                    Self.fill(box, .white, radius: 8)
                    var rect = logoRect(logo, in: box.insetBy(dx: 10, dy: 8))
                    rect.origin.x = box.midX - rect.width / 2
                    logo.draw(in: rect)
                }
                Self.draw(dates, CGRect(x: Self.margin, y: band + 10, width: Self.width, height: datesHeight))
            }
        case .classic, .minimal:
            let rightWidth: CGFloat = 220
            let leftWidth = Self.width - rightWidth - 16
            let titleColor = layout == .classic ? accent : Self.ink
            let heading = Self.lines([Self.text(title, Self.attrs(layout == .classic ? 20 : 18, .bold, titleColor)),
                                      Self.text(number, Self.attrs(12, .semibold))])
            let logoHeight: CGFloat = logo == nil ? 0 : 62
            let leftHeight = logoHeight + Self.height(heading, leftWidth)
            let dates = Self.lines(headerDates.map { row in
                let m = NSMutableAttributedString(attributedString: row)
                let style = NSMutableParagraphStyle()
                style.alignment = .right
                m.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: m.length))
                return m
            })
            let rightHeight = Self.height(dates, rightWidth)
            let height = max(leftHeight, rightHeight) + 12
            return Block(height: height) { y in
                var top = y
                if let logo {
                    logo.draw(in: logoRect(logo, in: CGRect(x: Self.margin, y: y, width: 170, height: 52)))
                    top += logoHeight
                }
                Self.draw(heading, CGRect(x: Self.margin, y: top, width: leftWidth, height: 0))
                Self.draw(dates, CGRect(x: Self.page.width - Self.margin - rightWidth, y: y + (logo == nil ? 4 : 0), width: rightWidth, height: 0))
                Self.hline(y + height - 2, color: layout == .minimal ? accent : Self.rule, thickness: layout == .minimal ? 1.2 : 0.6)
            }
        }
    }

    // MARK: - Strony faktury

    func partyText(_ party: InvoiceParty, registry: [InvoiceKeyValue]) -> NSAttributedString {
        var rows = [Self.text(party.name.isEmpty ? "—" : party.name, Self.attrs(10.5, .semibold))]
        if !party.nip.isEmpty { rows.append(Self.pair(labels.nip, party.nip, size: 9)) }
        if !party.otherTaxID.isEmpty { rows.append(Self.pair(labels.taxID, party.otherTaxID, size: 9)) }
        rows += party.addressLines.map { Self.text($0, Self.attrs(9)) }
        if !party.email.isEmpty { rows.append(Self.pair(labels.email, party.email, size: 8.5)) }
        if !party.phone.isEmpty { rows.append(Self.pair(labels.phone, party.phone, size: 8.5)) }
        rows += registry.map { Self.pair($0.key, $0.value, size: 8.5) }
        return Self.lines(rows)
    }

    func partiesBlock() -> Block {
        let gap: CGFloat = 14
        let column = (Self.width - gap) / 2
        let pad: CGFloat = layout == .minimal ? 0 : 10
        let caption = Self.attrs(7.5, .bold, layout == .minimal ? accent : Self.secondary)
        let seller = partyText(doc.seller, registry: doc.sellerRegistry)
        let buyer = partyText(doc.buyer, registry: [])
        let body = max(Self.height(seller, column - 2 * pad), Self.height(buyer, column - 2 * pad))
        let height = 2 * pad + 14 + body + (layout == .minimal ? 6 : 0)
        return Block(height: height, spacing: 14) { y in
            for (index, (label, content)) in [(labels.seller, seller), (labels.buyer, buyer)].enumerated() {
                let box = CGRect(x: Self.margin + CGFloat(index) * (column + gap), y: y, width: column, height: height)
                switch layout {
                case .classic: Self.stroke(box, Self.rule, radius: 4)
                case .modern: Self.fill(box, mix(0.08), radius: 8)
                case .minimal: Self.hline(y, from: box.minX, width: column, color: accent, thickness: 1)
                }
                let inner = box.insetBy(dx: pad, dy: pad).offsetBy(dx: 0, dy: layout == .minimal ? 6 : 0)
                Self.draw(Self.text(label.uppercased(), caption), CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: 12))
                Self.draw(content, CGRect(x: inner.minX, y: inner.minY + 14, width: inner.width, height: 0))
            }
        }
    }

    func correctionBlock() -> Block? {
        guard doc.kind.isCorrection, !doc.correctedInvoices.isEmpty || !doc.correctionReason.isEmpty else { return nil }
        var rows = doc.correctedInvoices.map { ref -> NSAttributedString in
            var value = ref.number
            if let date = ref.issueDate { value += " (\(labels.date(date)))" }
            if !ref.ksefNumber.isEmpty { value += " · KSeF \(ref.ksefNumber)" }
            return Self.pair(labels.correctedInvoice, value, size: 9)
        }
        if !doc.correctionReason.isEmpty { rows.append(Self.pair(labels.correctionReason, doc.correctionReason, size: 9)) }
        let content = Self.lines(rows)
        let height = Self.height(content, Self.width - 20) + 16
        return Block(height: height, spacing: 10) { y in
            let box = CGRect(x: Self.margin, y: y, width: Self.width, height: height)
            Self.fill(box, mix(0.06), radius: 4)
            Self.fill(CGRect(x: box.minX, y: box.minY, width: 3, height: box.height), accent)
            Self.draw(content, box.insetBy(dx: 10, dy: 8))
        }
    }

    // MARK: - Pozycje

    struct Column {
        var title: String
        var width: CGFloat
        var align: NSTextAlignment
        var value: (InvoiceDocumentLine) -> String
    }

    var columns: [Column] {
        let l = labels
        let lines = doc.lines
        var columns = [Column(title: l.colNumber, width: 24, align: .center) { $0.number }]
        columns.append(Column(title: l.colName, width: 0, align: .left) { $0.name })
        if lines.contains(where: { $0.quantity != nil || !$0.unit.isEmpty }) {
            columns.append(Column(title: l.colUnit, width: 36, align: .center) { $0.unit })
            columns.append(Column(title: l.colQuantity, width: 44, align: .right) { $0.quantity.map(l.quantity) ?? "" })
        }
        if lines.contains(where: { $0.unitPriceNet != nil }) {
            columns.append(Column(title: l.colUnitNet, width: 62, align: .right) { $0.unitPriceNet.map(l.amount) ?? "" })
        } else if lines.contains(where: { $0.unitPriceGross != nil }) {
            columns.append(Column(title: l.colUnitGross, width: 62, align: .right) { $0.unitPriceGross.map(l.amount) ?? "" })
        }
        if lines.contains(where: { ($0.discount ?? 0) != 0 }) {
            columns.append(Column(title: l.colDiscount, width: 50, align: .right) { $0.discount.map(l.amount) ?? "" })
        }
        columns.append(Column(title: l.colRate, width: 38, align: .center) { l.lineRate($0.vatRate) })
        if lines.contains(where: { $0.net != nil }) {
            columns.append(Column(title: l.colNet, width: 70, align: .right) { $0.net.map(l.amount) ?? "" })
        }
        if lines.contains(where: { $0.gross != nil }) {
            columns.append(Column(title: l.colGross, width: 70, align: .right) { $0.gross.map(l.amount) ?? "" })
        }
        let fixed = columns.reduce(0) { $0 + $1.width }
        columns[1].width = Self.width - fixed
        return columns
    }

    func itemBlocks() -> [Block] {
        guard !doc.lines.isEmpty else { return [] }
        let columns = columns
        let pad: CGFloat = 4
        let headerColor: UIColor = layout == .modern ? .white : (layout == .classic ? Self.ink : accent)
        let titles = columns.map { Self.text($0.title, Self.attrs(7.5, .bold, headerColor, align: $0.align)) }
        let headerHeight = (zip(titles, columns).map { Self.height($0, $1.width - 2 * pad) }.max() ?? 10) + 10
        let header = Header(height: headerHeight) { y in
            let rect = CGRect(x: Self.margin, y: y, width: Self.width, height: headerHeight)
            switch layout {
            case .classic: Self.fill(rect, UIColor(white: 0.93, alpha: 1))
            case .modern: Self.fill(rect, accent, radius: 4)
            case .minimal: Self.hline(rect.maxY - 1, color: accent, thickness: 1)
            }
            var x = Self.margin
            for (title, column) in zip(titles, columns) {
                let h = Self.height(title, column.width - 2 * pad)
                Self.draw(title, CGRect(x: x + pad, y: y + (headerHeight - h) / 2, width: column.width - 2 * pad, height: h))
                x += column.width
            }
        }

        var blocks = [Block(height: header.height, spacing: 16, draw: header.draw)]
        for (index, line) in doc.lines.enumerated() {
            let color = line.isBeforeCorrection ? Self.secondary : Self.ink
            let cells = columns.map { column -> NSAttributedString in
                let value = Self.text(column.value(line), Self.attrs(8.5, .regular, color, align: column.align, italic: line.isBeforeCorrection))
                guard column.title == labels.colName, line.isBeforeCorrection else { return value }
                return Self.lines([value, Self.text(labels.beforeCorrection, Self.attrs(7, .regular, Self.secondary, italic: true))])
            }
            let height = (zip(cells, columns).map { Self.height($0, $1.width - 2 * pad) }.max() ?? 10) + 9
            blocks.append(Block(height: height, header: header) { y in
                let rect = CGRect(x: Self.margin, y: y, width: Self.width, height: height)
                if layout == .modern && index % 2 == 1 { Self.fill(rect, mix(0.05)) }
                if layout != .modern { Self.hline(rect.maxY - 0.5, color: UIColor(white: 0.88, alpha: 1), thickness: 0.5) }
                var x = Self.margin
                for (cell, column) in zip(cells, columns) {
                    Self.draw(cell, CGRect(x: x + pad, y: y + 4.5, width: column.width - 2 * pad, height: height - 9))
                    x += column.width
                }
            })
        }
        return blocks
    }

    // MARK: - Podsumowanie i sumy

    func summaryBlock() -> Block {
        let widths: [CGFloat] = [96, 78, 70, 82]
        let tableWidth = widths.reduce(0, +)
        let rowHeight: CGFloat = 16
        let rows = doc.vatSummary.map { [labels.rate($0.rate), labels.amount($0.net), labels.amount($0.vat), labels.amount($0.gross)] }
        let total = [labels.total, labels.amount(doc.totalNet), labels.amount(doc.totalVAT), labels.amount(doc.totalGross)]
        let head = [labels.rate, labels.net, labels.vat, labels.gross]
        let headAttrs = { (index: Int) in Self.attrs(8.5, .semibold, layout == .classic ? Self.ink : accent, align: index == 0 ? .left : .right) }
        let headHeight = max(rowHeight, (zip(head, widths).enumerated()
            .map { Self.height(Self.text($1.0, headAttrs($0)), $1.1 - 8) }.max() ?? 0) + 6)
        let height = 14 + headHeight + rowHeight * CGFloat(rows.count + 1) + (doc.vatInPLN == nil ? 0 : rowHeight)
        return Block(height: height, spacing: 14) { y in
            let x0 = Self.page.width - Self.margin - tableWidth
            Self.draw(Self.text(labels.vatSummary.uppercased(), Self.attrs(7.5, .bold, layout == .classic ? Self.secondary : accent)),
                      CGRect(x: x0, y: y, width: tableWidth, height: 12))
            func row(_ values: [String], _ top: CGFloat, weight: UIFont.Weight, color: UIColor = Self.ink) {
                var x = x0
                for (index, (value, width)) in zip(values, widths).enumerated() {
                    let a = Self.attrs(8.5, weight, color, align: index == 0 ? .left : .right)
                    Self.draw(Self.text(value, a), CGRect(x: x + 4, y: top + 3, width: width - 8, height: rowHeight - 3))
                    x += width
                }
            }
            var top = y + 14
            let headRect = CGRect(x: x0, y: top, width: tableWidth, height: headHeight)
            if layout == .classic {
                Self.fill(headRect, UIColor(white: 0.93, alpha: 1))
            } else {
                Self.hline(headRect.maxY - 0.8, from: x0, width: tableWidth, color: accent, thickness: 0.8)
            }
            var x = x0
            for (index, (value, width)) in zip(head, widths).enumerated() {
                Self.draw(Self.text(value, headAttrs(index)), CGRect(x: x + 4, y: top + 3, width: width - 8, height: headHeight - 3))
                x += width
            }
            top += headHeight
            for values in rows {
                row(values, top, weight: .regular)
                Self.hline(top + rowHeight - 0.5, from: x0, width: tableWidth, color: UIColor(white: 0.9, alpha: 1), thickness: 0.5)
                top += rowHeight
            }
            row(total, top, weight: .bold)
            top += rowHeight
            if let vat = doc.vatInPLN {
                row([labels.vatInPLN, "", "\(labels.amount(vat)) PLN", ""], top, weight: .regular, color: Self.secondary)
            }
        }
    }

    var dueLabel: String {
        if doc.kind.isCorrection { return labels.correctionAmount }
        return doc.payment.isPaid ? labels.paid : labels.amountDue
    }

    func totalsBlock() -> Block {
        let boxWidth: CGFloat = 326
        let words = template.showAmountInWords
            ? Self.lines([Self.text(labels.inWords.uppercased(), Self.attrs(7, .bold, Self.secondary)),
                          Self.text(labels.amountInWords(doc.totalGross, currency: doc.currency), Self.attrs(9))])
            : NSAttributedString()
        let wordsWidth = Self.width - boxWidth - 16
        let fg: UIColor = layout == .modern ? .white : Self.ink
        let amount = Self.text(money(doc.totalGross), Self.attrs(16, .bold, layout == .modern ? .white : accent, align: .right))
        let amountWidth = ceil(amount.size().width)
        let labelWidth = boxWidth - 24 - amountWidth - 10
        let label = Self.text(dueLabel, Self.attrs(10, .semibold, fg))
        let boxHeight = max(44, Self.height(label, labelWidth) + 18)
        let height = max(boxHeight, Self.height(words, wordsWidth))
        return Block(height: height, spacing: 10) { y in
            Self.draw(words, CGRect(x: Self.margin, y: y + 4, width: wordsWidth, height: 0))
            let box = CGRect(x: Self.page.width - Self.margin - boxWidth, y: y, width: boxWidth, height: boxHeight)
            switch layout {
            case .classic: Self.fill(box, mix(0.1), radius: 4)
            case .modern: Self.fill(box, accent, radius: 8)
            case .minimal: Self.stroke(box, accent, width: 1.2)
            }
            let labelHeight = Self.height(label, labelWidth)
            Self.draw(label, CGRect(x: box.minX + 12, y: box.midY - labelHeight / 2, width: labelWidth, height: labelHeight))
            Self.draw(amount, CGRect(x: box.maxX - 12 - amountWidth, y: box.midY - 10, width: amountWidth, height: 20))
        }
    }

    // MARK: - Płatność i KSeF

    var paymentRows: [NSAttributedString] {
        let p = doc.payment
        var rows: [NSAttributedString] = []
        if !p.formCode.isEmpty { rows.append(Self.pair(labels.paymentForm, labels.paymentForm(code: p.formCode), size: 9)) }
        if !p.otherForm.isEmpty { rows.append(Self.pair(labels.paymentForm, p.otherForm, size: 9)) }
        if !p.dueDates.isEmpty { rows.append(Self.pair(labels.dueDate, p.dueDates.map(labels.date).joined(separator: ", "), size: 9, bold: true)) }
        if !p.dueDescription.isEmpty { rows.append(Self.pair(labels.dueDate, p.dueDescription, size: 9)) }
        if p.isPaid { rows.append(Self.pair(labels.paidOn, p.paidDate.map(labels.date) ?? "✓", size: 9)) }
        for account in p.bankAccounts {
            var value = account.number.groupedNRB
            if !account.bankName.isEmpty { value += " · \(account.bankName)" }
            if !account.swift.isEmpty { value += " · SWIFT \(account.swift)" }
            rows.append(Self.pair(labels.bankAccount, value, size: 9, bold: true))
        }
        if doc.isSplitPayment { rows.append(Self.text(labels.annotation(.splitPayment), Self.attrs(9, .semibold, accent))) }
        if !doc.ksefNumber.isEmpty && !showsQR { rows.append(Self.pair(labels.ksefNumber, doc.ksefNumber, size: 8.5)) }
        return rows
    }

    var showsQR: Bool { template.showQRCode && doc.verificationURL != nil }

    func paymentBlock() -> Block {
        let qrSize: CGFloat = 92
        let qrColumn: CGFloat = showsQR ? 170 : 0
        let rows = paymentRows
        let content = rows.isEmpty ? NSAttributedString()
            : Self.lines([Self.text(labels.payment.uppercased(), Self.attrs(7.5, .bold, layout == .classic ? Self.secondary : accent))] + rows)
        let textWidth = Self.width - qrColumn - (showsQR ? 16 : 0)
        let ksefCaption = Self.lines([Self.text(doc.ksefNumber, Self.attrs(7, .medium, Self.ink, align: .center, mono: true)),
                                      Self.text(labels.verifyCaption, Self.attrs(6.5, .regular, Self.secondary, align: .center))])
        let qrHeight = showsQR ? qrSize + 4 + Self.height(ksefCaption, qrColumn) : 0
        let height = max(Self.height(content, textWidth), qrHeight)
        return Block(height: height, spacing: 18) { y in
            Self.draw(content, CGRect(x: Self.margin, y: y, width: textWidth, height: 0))
            guard showsQR, let url = doc.verificationURL else { return }
            let x0 = Self.page.width - Self.margin - qrColumn
            Self.drawQR(url.absoluteString, in: CGRect(x: x0 + (qrColumn - qrSize) / 2, y: y, width: qrSize, height: qrSize))
            Self.draw(ksefCaption, CGRect(x: x0, y: y + qrSize + 4, width: qrColumn, height: 0))
        }
    }

    /// Kod QR jako wektorowe kwadraty (ostry przy każdym powiększeniu i wydruku).
    static func drawQR(_ message: String, in rect: CGRect) {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(message.utf8)
        filter.correctionLevel = "M"
        guard let image = filter.outputImage else { return }
        let size = Int(image.extent.width)
        var pixels = [UInt8](repeating: 255, count: size * size)
        CIContext(options: [.workingColorSpace: NSNull()])
            .render(image, toBitmap: &pixels, rowBytes: size, bounds: image.extent, format: .L8, colorSpace: nil)
        let module = rect.width / CGFloat(size)
        UIColor.black.setFill()
        for row in 0..<size {
            for col in 0..<size where pixels[row * size + col] < 128 {
                // Lekki nadmiar usuwa szczeliny między modułami w niektórych przeglądarkach PDF.
                UIRectFill(CGRect(x: rect.minX + CGFloat(col) * module, y: rect.minY + CGFloat(row) * module,
                                  width: module + 0.05, height: module + 0.05))
            }
        }
    }

    // MARK: - Adnotacje, uwagi, podpisy

    func notesBlock() -> Block? {
        var rows: [NSAttributedString] = []
        let annotations = doc.annotations.filter { $0 != .splitPayment }
        if !annotations.isEmpty {
            rows.append(Self.text(labels.annotations.uppercased(), Self.attrs(7.5, .bold, layout == .classic ? Self.secondary : accent)))
            rows += annotations.map { Self.text("• \(labels.annotation($0))", Self.attrs(8.5)) }
        }
        if !doc.additionalInfo.isEmpty {
            rows.append(Self.text(labels.notes.uppercased(), Self.attrs(7.5, .bold, layout == .classic ? Self.secondary : accent)))
            rows += doc.additionalInfo.map { $0.key.isEmpty ? Self.text($0.value, Self.attrs(8.5)) : Self.pair($0.key, $0.value) }
        }
        let note = template.closingNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { rows.append(Self.text(note, Self.attrs(9.5, .medium, accent, italic: true))) }
        guard !rows.isEmpty else { return nil }
        let content = Self.lines(rows)
        let height = Self.height(content, Self.width)
        return Block(height: height, spacing: 16) { y in Self.draw(content, CGRect(x: Self.margin, y: y, width: Self.width, height: 0)) }
    }

    func signaturesBlock() -> Block {
        Block(height: 54, spacing: 28) { y in
            let width: CGFloat = 190
            for (index, label) in [labels.issuedBy, labels.receivedBy].enumerated() {
                let x = index == 0 ? Self.margin : Self.page.width - Self.margin - width
                Self.hline(y + 34, from: x, width: width, color: Self.secondary, thickness: 0.5)
                Self.draw(Self.text(label, Self.attrs(7.5, .regular, Self.secondary, align: .center)),
                          CGRect(x: x, y: y + 38, width: width, height: 12))
            }
        }
    }

    // MARK: - Stopka i znak wodny

    var footerText: NSAttributedString {
        var rows: [String] = []
        if prepared.isDraft { rows.append(labels.draftNotice) }
        let custom = template.footerText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            rows.append(custom)
        } else if !doc.footer.isEmpty {
            rows.append(doc.footer)
        }
        if isCostInvoice { rows.append(labels.costNotice) }
        return Self.text(rows.joined(separator: "\n"), Self.attrs(7, .regular, Self.secondary))
    }

    static let pageNumberWidth: CGFloat = 90

    var footerHeight: CGFloat { max(12, Self.height(footerText, Self.width - Self.pageNumberWidth)) + 8 }

    func drawFooter(page: Int, of total: Int, height: CGFloat) {
        let y = Self.page.height - Self.margin - height
        Self.hline(y, color: layout == .minimal ? accent : Self.rule, thickness: 0.5)
        Self.draw(footerText, CGRect(x: Self.margin, y: y + 6, width: Self.width - Self.pageNumberWidth, height: 0))
        let numbering = Self.lines([Self.text(labels.page(page, of: total), Self.attrs(7.5, .medium, Self.secondary, align: .right)),
                                    Self.text("KS-eFektywnie", Self.attrs(6.5, .regular, Self.rule, align: .right))])
        Self.draw(numbering, CGRect(x: Self.page.width - Self.margin - Self.pageNumberWidth, y: y + 6, width: Self.pageNumberWidth, height: 0))
    }

    func drawWatermark(_ context: CGContext) {
        context.saveGState()
        context.translateBy(x: Self.page.midX, y: Self.page.midY)
        context.rotate(by: -.pi / 6)
        let mark = Self.text(labels.draftWatermark, Self.attrs(110, .heavy, UIColor(white: 0.93, alpha: 1), align: .center))
        let size = mark.size()
        mark.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))
        context.restoreGState()
    }
}

// MARK: - Udostępnianie

/// Plik PDF wizualizacji do `ShareLink`; nazwa pliku z numeru faktury.
nonisolated struct InvoiceVisualizationFile: Transferable {
    let pdf: InvoiceVisualizationPDF

    var fileName: String {
        let safe = pdf.doc.number.map { "/\\:*?\"<>|".contains($0) ? "-" : $0 }
        return "\(String(safe).nonEmptyOr("Faktura")).pdf"
    }

    func write() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "invoice-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: fileName)
        try pdf.render().write(to: url, options: .atomic)
        return url
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { file in SentTransferredFile(try file.write()) }
    }
}
