import Foundation

/// Sprzedawca na fakturze FA(3).
public struct FA3Seller: Hashable, Sendable {
    public var nip: String
    public var name: String
    public var address: String

    public init(nip: String, name: String, address: String) {
        self.nip = nip
        self.name = name
        self.address = address
    }
}

public enum FA3GeneratorError: Error, Equatable, LocalizedError {
    case noItems
    case missingBankAccount
    case missingExemptionBasis

    public var errorDescription: String? {
        switch self {
        case .noItems: "Faktura nie ma żadnych pozycji."
        case .missingBankAccount: "Brak numeru rachunku bankowego dla płatności przelewem."
        case .missingExemptionBasis: "Faktura ze stawką ZW wymaga podania podstawy prawnej zwolnienia z VAT."
        }
    }
}

/// Generator XML FA(3) — port `apps/ksef/generator.py` (schemat 2025/06/25/13775).
/// Zgodność sprawdzana w testach z wynikiem Django, który z kolei jest walidowany XSD.
public enum FA3Generator {
    public static let namespace = "http://crd.gov.pl/wzor/2025/06/25/13775/"

    /// Stawka → (pole netto, pole VAT, wartość P_12).
    static let rateFields: [VATRate: (net: String, vat: String?, p12: String)] = [
        .standard: ("P_13_1", "P_14_1", "23"),
        .reduced8: ("P_13_2", "P_14_2", "8"),
        .reduced5: ("P_13_3", "P_14_3", "5"),
        .zero: ("P_13_6_1", nil, "0 KR"),
        .exempt: ("P_13_7", nil, "zw"),
        .notSubject: ("P_13_8", nil, "np I"),
    ]
    static let totalsOrder = ["P_13_1", "P_14_1", "P_13_2", "P_14_2", "P_13_3", "P_14_3", "P_13_6_1", "P_13_7", "P_13_8"]
    static let exemptionFields: [VATExemptionType: String] = [.act: "P_19A", .directive: "P_19B", .other: "P_19C"]

    public static func generate(_ invoice: OutgoingInvoice, seller: FA3Seller, now: Date = Date(),
                                systemInfo: String = "KS-eFektywnie") throws -> String {
        guard !invoice.items.isEmpty else { throw FA3GeneratorError.noItems }
        if invoice.paymentForm == .transfer && invoice.bankAccountNumber.isEmpty { throw FA3GeneratorError.missingBankAccount }
        let basis = invoice.exemptionBasis.trimmingCharacters(in: .whitespacesAndNewlines)
        if invoice.hasExemptItems && basis.isEmpty { throw FA3GeneratorError.missingExemptionBasis }

        let root = XMLBuilder("Faktura")
        let naglowek = root.add("Naglowek")
        naglowek.add("KodFormularza", "FA", attributes: [("kodSystemowy", "FA (3)"), ("wersjaSchemy", "1-0E")])
        naglowek.add("WariantFormularza", "3")
        naglowek.add("DataWytworzeniaFa", utcTimestamp(now))
        naglowek.add("SystemInfo", systemInfo)

        let p1 = root.add("Podmiot1")
        let p1dane = p1.add("DaneIdentyfikacyjne")
        p1dane.add("NIP", seller.nip)
        p1dane.add("Nazwa", seller.name)
        address(p1, seller.address)

        let p2 = root.add("Podmiot2")
        let p2dane = p2.add("DaneIdentyfikacyjne")
        p2dane.add("NIP", invoice.buyerNIP)
        p2dane.add("Nazwa", invoice.buyerName)
        if !invoice.buyerAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { address(p2, invoice.buyerAddress) }
        p2.add("JST", "2")
        p2.add("GV", "2")

        let fa = root.add("Fa")
        fa.add("KodWaluty", invoice.currency)
        fa.add("P_1", invoice.issueDate.iso)
        fa.add("P_2", invoice.invoiceNumber)
        if let delivery = invoice.deliveryDate { fa.add("P_6", delivery.iso) }

        var totals: [String: Decimal] = [:]
        for item in invoice.items {
            let fields = rateFields[item.vatRate]!
            totals[fields.net, default: 0] += item.amountNet
            if let vat = fields.vat { totals[vat, default: 0] += item.amountVAT }
        }
        for field in totalsOrder { if let value = totals[field] { fa.add(field, fixed(value, 2)) } }
        fa.add("P_15", fixed(invoice.amountGross, 2))

        let adnotacje = fa.add("Adnotacje")
        for field in ["P_16", "P_17", "P_18", "P_18A"] { adnotacje.add(field, "2") }
        let zwolnienie = adnotacje.add("Zwolnienie")
        if invoice.hasExemptItems {
            zwolnienie.add("P_19", "1")
            zwolnienie.add(exemptionFields[invoice.exemptionType]!, String(basis.prefix(256)))
        } else {
            zwolnienie.add("P_19N", "1")
        }
        adnotacje.add("NoweSrodkiTransportu").add("P_22N", "1")
        adnotacje.add("P_23", "2")
        adnotacje.add("PMarzy").add("P_PMarzyN", "1")
        fa.add("RodzajFaktury", "VAT")

        for (index, item) in invoice.items.enumerated() {
            let row = fa.add("FaWiersz")
            row.add("NrWierszaFa", String(index + 1))
            row.add("P_7", item.name)
            row.add("P_8A", item.unit)
            row.add("P_8B", quantity(item.quantity))
            row.add("P_9A", fixed(item.unitPriceNet, 2))
            row.add("P_11", fixed(item.amountNet, 2))
            row.add("P_12", rateFields[item.vatRate]!.p12)
        }

        let platnosc = fa.add("Platnosc")
        platnosc.add("TerminPlatnosci").add("Termin", invoice.paymentDueDate.iso)
        platnosc.add("FormaPlatnosci", invoice.paymentForm == .cash ? "1" : "6")
        if invoice.paymentForm == .transfer {
            platnosc.add("RachunekBankowy").add("NrRB", invoice.bankAccountNumber.replacingOccurrences(of: " ", with: ""))
        }
        return root.document(namespace: namespace)
    }

    static func address(_ parent: XMLBuilder, _ text: String) {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let adres = parent.add("Adres")
        adres.add("KodKraju", "PL")
        adres.add("AdresL1", lines.first ?? "-")
        if lines.count >= 2 { adres.add("AdresL2", lines[1]) }
    }

    static func utcTimestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    /// Stała liczba miejsc po przecinku, ROUND_HALF_UP (jak `_fmt_decimal`).
    static func fixed(_ value: Decimal, _ places: Int) -> String {
        let rounded = value.rounded(scale: places, mode: .plain)
        var scaled = rounded
        for _ in 0..<places { scaled *= 10 }
        let units = NSDecimalNumber(decimal: scaled).int64Value
        let sign = units < 0 ? "-" : ""
        let magnitude = units.magnitude
        var divisor: UInt64 = 1
        for _ in 0..<places { divisor *= 10 }
        let fraction = String(magnitude % divisor)
        return "\(sign)\(magnitude / divisor).\(String(repeating: "0", count: places - fraction.count))\(fraction)"
    }

    /// Ilość bez zbędnych zer: 2.000 → 2, 1.500 → 1.5 (jak `_fmt_quantity`).
    static func quantity(_ value: Decimal) -> String {
        var text = fixed(value, 3)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}

/// Prosty budowniczy XML: elementy w domyślnej przestrzeni nazw, wcięcia 2 spacje.
final class XMLBuilder {
    let name: String
    var text: String?
    var attributes: [(String, String)] = []
    var children: [XMLBuilder] = []

    init(_ name: String, _ text: String? = nil, attributes: [(String, String)] = []) {
        self.name = name
        self.text = text
        self.attributes = attributes
    }

    @discardableResult
    func add(_ name: String, _ text: String? = nil, attributes: [(String, String)] = []) -> XMLBuilder {
        let child = XMLBuilder(name, text, attributes: attributes)
        children.append(child)
        return child
    }

    func document(namespace: String) -> String {
        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        attributes.insert(("xmlns", namespace), at: 0)
        write(into: &out, depth: 0)
        return out
    }

    private func write(into out: inout String, depth: Int) {
        let indent = String(repeating: "  ", count: depth)
        let attrs = attributes.map { " \($0.0)=\"\(Self.escape($0.1, attribute: true))\"" }.joined()
        if children.isEmpty {
            if let text {
                out += "\(indent)<\(name)\(attrs)>\(Self.escape(text))</\(name)>\n"
            } else {
                out += "\(indent)<\(name)\(attrs)/>\n"
            }
            return
        }
        out += "\(indent)<\(name)\(attrs)>\n"
        for child in children { child.write(into: &out, depth: depth + 1) }
        out += "\(indent)</\(name)>\n"
    }

    static func escape(_ text: String, attribute: Bool = false) -> String {
        var s = text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        if attribute { s = s.replacingOccurrences(of: "\"", with: "&quot;") }
        return s
    }
}
