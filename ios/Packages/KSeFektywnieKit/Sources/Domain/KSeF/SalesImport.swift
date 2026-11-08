import Foundation

/// Faktura sprzedażowa z XML pobranego z KSeF (firma jest sprzedawcą) — port `apps/ksef/sales_parser.py`.
///
/// Służy do importu faktur wystawionych poza aplikacją. Pozycje mają kwoty z XML
/// (`fixedAmounts`), więc sumy zgadzają się z fakturą w KSeF co do grosza.
/// Zmiany logiki trzeba wprowadzać w obu miejscach.
public enum SalesImport {
    /// Kod stawki P_12 → stawka w modelu i pole sumy VAT P_14_x. Stawki historyczne i szczególne
    /// są przybliżane (22→23, 7→8, taxi 4/3→5, odwrotne obciążenie oo→np); kwoty zostają dokładne.
    static let rateCodes: [String: (VATRate, String?)] = [
        "23": (.standard, "P_14_1"), "22": (.standard, "P_14_1"),
        "8": (.reduced8, "P_14_2"), "7": (.reduced8, "P_14_2"),
        "5": (.reduced5, "P_14_3"),
        "4": (.reduced5, "P_14_4"), "3": (.reduced5, "P_14_4"),
        "0": (.zero, nil), "0 KR": (.zero, nil), "0 WDT": (.zero, nil), "0 EX": (.zero, nil),
        "zw": (.exempt, nil),
        "oo": (.notSubject, nil), "np": (.notSubject, nil), "np I": (.notSubject, nil), "np II": (.notSubject, nil),
    ]

    static let vatPercent: [String: Decimal] = ["23": 23, "22": 22, "8": 8, "7": 7, "5": 5, "4": 4, "3": 3]

    /// Sumy netto z nagłówka → stawka i pole VAT (pozycje zbiorcze dla korekt i zaliczek).
    static let netTotals: [(String, VATRate, String?)] = [
        ("P_13_1", .standard, "P_14_1"), ("P_13_2", .reduced8, "P_14_2"), ("P_13_3", .reduced5, "P_14_3"),
        ("P_13_4", .reduced5, "P_14_4"), ("P_13_5", .standard, "P_14_5"),
        ("P_13_6_1", .zero, nil), ("P_13_6_2", .zero, nil), ("P_13_6_3", .zero, nil),
        ("P_13_7", .exempt, nil), ("P_13_8", .notSubject, nil), ("P_13_9", .notSubject, nil),
        ("P_13_10", .notSubject, nil), ("P_13_11", .notSubject, nil),
    ]

    static let rateLabels: [VATRate: String] = [
        .standard: "23%", .reduced8: "8%", .reduced5: "5%", .zero: "0%", .exempt: "ZW", .notSubject: "NP",
    ]

    static let exemptionFields: [(String, VATExemptionType)] = [("P_19A", .act), ("P_19B", .directive), ("P_19C", .other)]

    /// Pozycja w trakcie parsowania (z polem sumy VAT do uzgodnienia groszy).
    struct Line {
        var item: OutgoingInvoiceItem
        var net: Decimal
        var vat: Decimal
        var vatField: String?

        var finished: OutgoingInvoiceItem {
            var result = item
            result.fixedAmounts = FixedItemAmounts(net: net, vat: vat)
            return result
        }
    }

    /// Faktura ze statusem `.imported` albo nil, gdy XML jest nieczytelny lub nie ma numeru i daty.
    public static func invoice(xml: Data, ksefNumber: String, companyID: UUID, environment: KSeFEnvironment,
                               now: Date = Date(), device: String = "") -> OutgoingInvoice? {
        guard let tree = XMLTree.parse(xml) else { return nil }
        let ns = FAParser.namespace(of: tree)
        let root = tree.root
        guard let fa = root.find(".//Fa", ns: ns) else { return nil }
        func t(_ path: String) -> String { fa.text(path, ns: ns) }

        let number = t("P_2")
        guard !number.isEmpty, let issueDate = LocalDate(iso: PyText.prefix(t("P_1"), 10)) else { return nil }
        let dueDate = LocalDate(iso: PyText.prefix(t(".//Platnosc/TerminPlatnosci/Termin"), 10)) ?? issueDate
        let invoiceType = t("RodzajFaktury")

        var invoice = OutgoingInvoice(
            companyID: companyID, invoiceNumber: PyText.prefix(number, 64), issueDate: issueDate,
            deliveryDate: LocalDate(iso: PyText.prefix(t("P_6"), 10)), paymentDueDate: dueDate,
            paymentForm: t(".//Platnosc/FormaPlatnosci") == "1" ? .cash : .transfer,
            currency: PyText.prefix(t("KodWaluty").nonEmpty ?? "PLN", 3).uppercased(),
            bankAccountNumber: FAParser.bankAccount(root, ns),
            status: .imported, environment: environment, createdAt: now, updatedAt: now, updatedByDevice: device)
        invoice.ksefNumber = ksefNumber
        invoice.generatedXML = String(decoding: xml, as: UTF8.self)

        if let buyer = root.find(".//Podmiot2", ns: ns) {
            invoice.buyerNIP = buyer.text("DaneIdentyfikacyjne/NIP", ns: ns)
            invoice.buyerName = buyer.text("DaneIdentyfikacyjne/Nazwa", ns: ns).nonEmpty ?? invoice.buyerNIP.nonEmpty ?? "Nabywca bez nazwy"
            invoice.buyerAddress = [buyer.text("Adres/AdresL1", ns: ns), buyer.text("Adres/AdresL2", ns: ns)]
                .filter { !$0.isEmpty }.joined(separator: "\n")
        }

        for (field, type) in exemptionFields {
            let basis = t("Adnotacje/Zwolnienie/\(field)")
            if !basis.isEmpty {
                invoice.exemptionType = type
                invoice.exemptionBasis = PyText.prefix(basis, 256)
                break
            }
        }

        if invoiceType.hasPrefix("KOR") {
            let corrected = t(".//DaneFaKorygowanej/NrFaKorygowanej")
            invoice.notes = corrected.isEmpty ? "Faktura korygująca" : "Korekta faktury \(corrected)"
        }

        var lines = lineItems(fa, ns)
        reconcileVAT(&lines, fa, ns)
        let expectedGross = optionalDecimal(fa, "P_15", ns)
        let gross = lines.reduce(Decimal(0)) { $0 + $1.net + $1.vat }
        if lines.isEmpty || (expectedGross.map { gross != round($0) } ?? false) {
            // Korekty, faktury zaliczkowe albo pozycje niezgodne z sumami — pozycje zbiorcze z nagłówka.
            let summary = summaryLines(fa, ns, isCorrection: invoiceType.hasPrefix("KOR"))
            if !summary.isEmpty { lines = summary }
        }
        if lines.isEmpty, let expectedGross {
            let amount = round(expectedGross)
            lines = [Line(item: OutgoingInvoiceItem(name: "Faktura \(number)", unitPriceNet: amount, vatRate: .notSubject),
                          net: amount, vat: 0)]
        }
        invoice.items = lines.map(\.finished)
        return invoice
    }

    static func lineItems(_ fa: XMLNode, _ ns: String) -> [Line] {
        fa.findAll("FaWiersz", ns: ns).compactMap { row in
            if row.text("StanPrzed", ns: ns) == "1" { return nil } // stan przed korektą
            let code = row.text("P_12", ns: ns)
            let (rate, vatField) = rateCodes[code] ?? (.notSubject, nil)
            let percent = vatPercent[code]
            let quantity = optionalDecimal(row, "P_8B", ns) ?? 1
            var price = optionalDecimal(row, "P_9A", ns)
            var net = optionalDecimal(row, "P_11", ns)
            var lineVAT = optionalDecimal(row, "P_11Vat", ns)

            if net == nil, let gross = optionalDecimal(row, "P_11A", ns) {
                // Faktura liczona od cen brutto (P_9B/P_11A): VAT „w stu”.
                if lineVAT == nil { lineVAT = percent.map { round(gross * $0 / (100 + $0)) } ?? 0 }
                net = gross - (lineVAT ?? 0)
            }
            let netValue = round(net ?? quantity * (price ?? 0))
            if price == nil { price = quantity != 0 ? round(netValue / quantity) : netValue }
            let vat = round(lineVAT ?? percent.map { netValue * $0 / 100 } ?? 0)

            let item = OutgoingInvoiceItem(
                name: PyText.prefix(row.text("P_7", ns: ns).nonEmpty ?? "Pozycja", 255),
                unit: PyText.prefix(row.text("P_8A", ns: ns).nonEmpty ?? "szt.", 30),
                quantity: quantity.rounded(scale: 3, mode: .plain), unitPriceNet: round(price ?? 0), vatRate: rate)
            return Line(item: item, net: netValue, vat: vat, vatField: vatField)
        }
    }

    /// VAT na fakturze liczy się od sumy netto w stawce, więc suma VAT z pozycji może
    /// różnić się o grosze. Różnicę dostaje największa pozycja w stawce.
    static func reconcileVAT(_ lines: inout [Line], _ fa: XMLNode, _ ns: String) {
        for field in ["P_14_1", "P_14_2", "P_14_3", "P_14_4"] {
            guard let expected = optionalDecimal(fa, field, ns) else { continue }
            let bucket = lines.indices.filter { lines[$0].vatField == field }
            guard !bucket.isEmpty else { continue }
            let diff = round(expected) - bucket.reduce(Decimal(0)) { $0 + lines[$1].vat }
            if diff != 0, let largest = bucket.max(by: { abs(lines[$0].net) < abs(lines[$1].net) }) {
                lines[largest].vat += diff
            }
        }
    }

    static func summaryLines(_ fa: XMLNode, _ ns: String, isCorrection: Bool) -> [Line] {
        let prefix = isCorrection ? "Korekta wartości" : "Wartość"
        return netTotals.compactMap { netField, rate, vatField in
            guard let net = optionalDecimal(fa, netField, ns), net != 0 else { return nil }
            let vat = vatField.flatMap { optionalDecimal(fa, $0, ns) } ?? 0
            let item = OutgoingInvoiceItem(name: "\(prefix) – stawka \(rateLabels[rate] ?? "")", quantity: 1,
                                           unitPriceNet: round(net), vatRate: rate)
            return Line(item: item, net: round(net), vat: round(vat), vatField: vatField)
        }
    }

    static func optionalDecimal(_ node: XMLNode, _ path: String, _ ns: String) -> Decimal? {
        let raw = node.text(path, ns: ns).replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")
        return raw.isEmpty ? nil : DecimalText.parse(raw)
    }

    static func round(_ value: Decimal) -> Decimal { value.rounded(scale: 2, mode: .plain) }
}
