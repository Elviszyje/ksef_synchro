import Foundation

/// Rodzaj faktury (`RodzajFaktury` w FA(2)/FA(3)).
public enum InvoiceKind: String, CaseIterable, Sendable {
    case vat = "VAT"
    case correction = "KOR"
    case advance = "ZAL"
    case settlement = "ROZ"
    case simplified = "UPR"
    case advanceCorrection = "KOR_ZAL"
    case settlementCorrection = "KOR_ROZ"

    public var isCorrection: Bool { self == .correction || self == .advanceCorrection || self == .settlementCorrection }
}

/// Strona faktury (sprzedawca, nabywca) w postaci do wydruku.
public struct InvoiceParty: Hashable, Sendable {
    public var name: String
    public var nip: String
    /// Numer VAT UE z prefiksem kraju (`DE123456789`) albo inny identyfikator podatkowy.
    public var otherTaxID: String
    public var addressLines: [String]
    public var email: String
    public var phone: String

    public init(name: String = "", nip: String = "", otherTaxID: String = "", addressLines: [String] = [],
                email: String = "", phone: String = "") {
        self.name = name
        self.nip = nip
        self.otherTaxID = otherTaxID
        self.addressLines = addressLines
        self.email = email
        self.phone = phone
    }
}

/// Pozycja faktury (`FaWiersz`). Kwoty opcjonalne — faktury uproszczone i korekty pomijają część pól.
public struct InvoiceDocumentLine: Hashable, Sendable {
    public var number: String
    public var name: String
    public var unit: String
    public var quantity: Decimal?
    public var unitPriceNet: Decimal?
    public var unitPriceGross: Decimal?
    public var discount: Decimal?
    public var net: Decimal?
    public var gross: Decimal?
    /// Stawka jak w XML (`P_12`): `23`, `8`, `zw`, `np I`, `0 KR`, `oo`…
    public var vatRate: String
    /// Wiersz „stan przed korektą” (`StanPrzed`).
    public var isBeforeCorrection: Bool

    public init(number: String, name: String, unit: String = "", quantity: Decimal? = nil, unitPriceNet: Decimal? = nil,
                unitPriceGross: Decimal? = nil, discount: Decimal? = nil, net: Decimal? = nil, gross: Decimal? = nil,
                vatRate: String = "", isBeforeCorrection: Bool = false) {
        self.number = number
        self.name = name
        self.unit = unit
        self.quantity = quantity
        self.unitPriceNet = unitPriceNet
        self.unitPriceGross = unitPriceGross
        self.discount = discount
        self.net = net
        self.gross = gross
        self.vatRate = vatRate
        self.isBeforeCorrection = isBeforeCorrection
    }
}

/// Stawka w podsumowaniu (pola `P_13_x`/`P_14_x`).
public enum VATSummaryRate: Hashable, Sendable {
    case rate(String)        // P_13_1…3: 23/22, 8/7, 5 (z pozycji, gdy da się ustalić)
    case taxi                // P_13_4: ryczałt dla taksówek
    case oss                 // P_13_5: procedura OSS
    case zeroDomestic        // P_13_6_1
    case zeroIntraEU         // P_13_6_2: WDT
    case zeroExport          // P_13_6_3
    case exempt              // P_13_7
    case notSubjectAbroad    // P_13_8
    case notSubjectArt100    // P_13_9
    case reverseCharge       // P_13_10
    case margin              // P_13_11
}

public struct VATSummaryRow: Hashable, Sendable {
    public var rate: VATSummaryRate
    public var net: Decimal
    public var vat: Decimal
    public var gross: Decimal { net + vat }

    public init(rate: VATSummaryRate, net: Decimal, vat: Decimal) {
        self.rate = rate
        self.net = net
        self.vat = vat
    }
}

/// Adnotacje (`Adnotacje`) mające wpływ na treść wydruku.
public enum InvoiceAnnotation: Hashable, Sendable {
    case cashMethod
    case selfBilling
    case reverseCharge
    case splitPayment
    case exemption(basis: String)
    case newTransport
    case triangular
    case margin
}

public struct InvoiceBankAccount: Hashable, Sendable {
    public var number: String
    public var bankName: String
    public var swift: String

    public init(number: String, bankName: String = "", swift: String = "") {
        self.number = number
        self.bankName = bankName
        self.swift = swift
    }
}

public struct InvoicePayment: Hashable, Sendable {
    public var isPaid = false
    public var paidDate: LocalDate?
    public var dueDates: [LocalDate] = []
    public var dueDescription = ""
    /// Kod formy płatności FA: 1 gotówka … 7 płatność mobilna; pusty, gdy brak.
    public var formCode = ""
    public var otherForm = ""
    public var bankAccounts: [InvoiceBankAccount] = []

    public init() {}
}

public struct CorrectedInvoiceRef: Hashable, Sendable {
    public var number: String
    public var issueDate: LocalDate?
    public var ksefNumber: String
}

public struct InvoiceKeyValue: Hashable, Sendable {
    public var key: String
    public var value: String
}

/// Treść faktury do wizualizacji — wspólna dla faktur kosztowych (XML z KSeF)
/// i sprzedażowych (XML wygenerowany w aplikacji).
public struct InvoiceDocument: Hashable, Sendable {
    public var kind: InvoiceKind = .vat
    public var number = ""
    public var issueDate: LocalDate?
    public var issuePlace = ""
    public var saleDate: LocalDate?
    public var salePeriod: ClosedRange<LocalDate>?
    public var currency = "PLN"

    public var seller = InvoiceParty()
    public var buyer = InvoiceParty()
    public var sellerRegistry: [InvoiceKeyValue] = []

    public var lines: [InvoiceDocumentLine] = []
    public var vatSummary: [VATSummaryRow] = []
    public var totalNet: Decimal = 0
    public var totalVAT: Decimal = 0
    public var totalGross: Decimal = 0
    /// Suma VAT w złotych dla faktur w walucie obcej (`P_14_xW`).
    public var vatInPLN: Decimal?

    public var annotations: [InvoiceAnnotation] = []
    public var payment = InvoicePayment()
    public var correctedInvoices: [CorrectedInvoiceRef] = []
    public var correctionReason = ""
    public var additionalInfo: [InvoiceKeyValue] = []
    public var footer = ""

    /// Uzupełniane poza parserem: numer KSeF i link weryfikacyjny (kod QR).
    public var ksefNumber = ""
    public var verificationURL: URL?

    public init() {}

    public var isSplitPayment: Bool { annotations.contains(.splitPayment) }
}

// MARK: - Parser

extension InvoiceDocument {
    /// Pełna treść faktury FA(2)/FA(3) do wydruku. `nil`, gdy XML jest nieczytelny.
    public static func parse(xml: String) -> InvoiceDocument? {
        guard !xml.isEmpty, let tree = XMLTree.parse(Data(xml.utf8)) else { return nil }
        let ns = FAParser.namespace(of: tree)
        let root = tree.root
        guard let fa = root.find(".//Fa", ns: ns) else { return nil }
        func t(_ path: String) -> String { fa.text(path, ns: ns).trimmed }

        var doc = InvoiceDocument()
        doc.kind = InvoiceKind(rawValue: t("RodzajFaktury")) ?? .vat
        doc.number = t("P_2")
        doc.issueDate = LocalDate(iso: t("P_1"))
        doc.issuePlace = t("P_1M")
        doc.saleDate = LocalDate(iso: t("P_6"))
        if let from = LocalDate(iso: t("OkresFa/P_6_Od")), let to = LocalDate(iso: t("OkresFa/P_6_Do")), from <= to {
            doc.salePeriod = from...to
        }
        doc.currency = t("KodWaluty").nonEmpty ?? "PLN"

        if let p1 = root.find(".//Podmiot1", ns: ns) { doc.seller = party(p1, ns) }
        if let p2 = root.find(".//Podmiot2", ns: ns) { doc.buyer = party(p2, ns) }
        doc.sellerRegistry = registry(root, ns)

        doc.lines = fa.findAll("FaWiersz", ns: ns).enumerated().map { index, row in
            func r(_ p: String) -> String { row.text(p, ns: ns).trimmed }
            return InvoiceDocumentLine(
                number: r("NrWierszaFa").nonEmpty ?? String(index + 1), name: r("P_7"), unit: r("P_8A"),
                quantity: number(r("P_8B")), unitPriceNet: number(r("P_9A")), unitPriceGross: number(r("P_9B")),
                discount: number(r("P_10")), net: number(r("P_11")), gross: number(r("P_11A")),
                vatRate: r("P_12"), isBeforeCorrection: r("StanPrzed") == "1")
        }

        doc.vatSummary = summary(fa, ns, lines: doc.lines)
        doc.totalNet = doc.vatSummary.reduce(0) { $0 + $1.net }
        doc.totalVAT = doc.vatSummary.reduce(0) { $0 + $1.vat }
        doc.totalGross = number(t("P_15")) ?? (doc.totalNet + doc.totalVAT)
        let vatPLN = (1...4).compactMap { number(t("P_14_\($0)W")) }
        if !vatPLN.isEmpty && doc.currency != "PLN" { doc.vatInPLN = vatPLN.reduce(0, +) }

        doc.annotations = annotations(fa, ns)
        doc.payment = payment(fa, ns)
        if fa.text("Platnosc/MechanizmPodzielonejPlatnosci", ns: ns) == "T" && !doc.isSplitPayment {
            doc.annotations.append(.splitPayment)
        }

        doc.correctedInvoices = fa.findAll("DaneFaKorygowanej", ns: ns).map { node in
            CorrectedInvoiceRef(number: node.text("NrFaKorygowanej", ns: ns).trimmed,
                                issueDate: LocalDate(iso: node.text("DataWystFaKorygowanej", ns: ns).trimmed),
                                ksefNumber: node.text("NrKSeFFaKorygowanej", ns: ns).trimmed)
        }
        doc.correctionReason = t("PrzyczynaKorekty")
        doc.additionalInfo = fa.findAll("DodatkowyOpis", ns: ns).compactMap { node in
            let key = node.text("Klucz", ns: ns).trimmed, value = node.text("Wartosc", ns: ns).trimmed
            return key.isEmpty && value.isEmpty ? nil : InvoiceKeyValue(key: key, value: value)
        }
        doc.footer = root.findAll(".//Stopka/Informacje/StopkaFaktury", ns: ns).map { $0.text.trimmed }
            .filter { !$0.isEmpty }.joined(separator: "\n")
        return doc
    }

    static func number(_ text: String) -> Decimal? {
        let raw = text.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")
        return raw.isEmpty ? nil : DecimalText.parse(raw)
    }

    static func party(_ node: XMLNode, _ ns: String) -> InvoiceParty {
        func t(_ p: String) -> String { node.text(p, ns: ns).trimmed }
        var party = InvoiceParty()
        party.nip = t("DaneIdentyfikacyjne/NIP")
        if party.nip.isEmpty {
            let eu = t("DaneIdentyfikacyjne/KodUE") + t("DaneIdentyfikacyjne/NrVatUE")
            let other = [t("DaneIdentyfikacyjne/KodKraju"), t("DaneIdentyfikacyjne/NrID")].filter { !$0.isEmpty }.joined(separator: " ")
            party.otherTaxID = eu.nonEmpty ?? other
        }
        party.name = t("DaneIdentyfikacyjne/Nazwa").nonEmpty
            ?? t("DaneIdentyfikacyjne/PelnaNazwa").nonEmpty
            ?? [t("DaneIdentyfikacyjne/Imie"), t("DaneIdentyfikacyjne/Nazwisko")].filter { !$0.isEmpty }.joined(separator: " ")
        party.addressLines = [t("Adres/AdresL1"), t("Adres/AdresL2")].filter { !$0.isEmpty && $0 != "-" }
        let country = t("Adres/KodKraju")
        if !country.isEmpty && country != "PL" && !party.addressLines.isEmpty { party.addressLines.append(country) }
        party.email = t("DaneKontaktowe/Email")
        party.phone = t("DaneKontaktowe/Telefon")
        return party
    }

    static func registry(_ root: XMLNode, _ ns: String) -> [InvoiceKeyValue] {
        guard let rejestry = root.find(".//Stopka/Rejestry", ns: ns) else { return [] }
        return [("KRS", "KRS"), ("REGON", "REGON"), ("BDO", "BDO")].compactMap { key, path in
            let value = rejestry.text(path, ns: ns).trimmed
            return value.isEmpty ? nil : InvoiceKeyValue(key: key, value: value)
        }
    }

    static let summaryFields: [(net: String, vat: String?, rate: VATSummaryRate)] = [
        ("P_13_1", "P_14_1", .rate("23")), ("P_13_2", "P_14_2", .rate("8")), ("P_13_3", "P_14_3", .rate("5")),
        ("P_13_4", "P_14_4", .taxi), ("P_13_5", "P_14_5", .oss),
        ("P_13_6_1", nil, .zeroDomestic), ("P_13_6_2", nil, .zeroIntraEU), ("P_13_6_3", nil, .zeroExport),
        ("P_13_7", nil, .exempt), ("P_13_8", nil, .notSubjectAbroad), ("P_13_9", nil, .notSubjectArt100),
        ("P_13_10", nil, .reverseCharge), ("P_13_11", nil, .margin),
    ]

    /// Podsumowanie stawek z pól `P_13_x`/`P_14_x`; gdy ich brak — z pozycji (np. korekty bez sum).
    static func summary(_ fa: XMLNode, _ ns: String, lines: [InvoiceDocumentLine]) -> [VATSummaryRow] {
        let rates = Set(lines.map(\.vatRate))
        let rows = summaryFields.compactMap { field -> VATSummaryRow? in
            let net = number(fa.text(field.net, ns: ns).trimmed)
            let vat = field.vat.flatMap { number(fa.text($0, ns: ns).trimmed) }
            guard net != nil || vat != nil else { return nil }
            var rate = field.rate
            // Stare stawki 22% i 7% (faktury za okresy sprzed 2011) są w tych samych polach.
            if case .rate("23") = rate, rates.contains("22") && !rates.contains("23") { rate = .rate("22") }
            if case .rate("8") = rate, rates.contains("7") && !rates.contains("8") { rate = .rate("7") }
            return VATSummaryRow(rate: rate, net: net ?? 0, vat: vat ?? 0)
        }
        if !rows.isEmpty { return rows }

        var order: [VATSummaryRate] = []
        var nets: [VATSummaryRate: Decimal] = [:]
        for line in lines where !line.isBeforeCorrection {
            guard let net = line.net ?? line.gross else { continue }
            let rate = summaryRate(forLineRate: line.vatRate)
            if nets[rate] == nil { order.append(rate) }
            nets[rate, default: 0] += net
        }
        return order.map { rate in
            let net = nets[rate]!
            var vat: Decimal = 0
            if case .rate(let r) = rate, let percent = DecimalText.parse(r) { vat = (net * percent / 100).rounded(scale: 2, mode: .plain) }
            return VATSummaryRow(rate: rate, net: net, vat: vat)
        }
    }

    static func summaryRate(forLineRate raw: String) -> VATSummaryRate {
        switch raw.lowercased() {
        case "0 kr", "0": .zeroDomestic
        case "0 wdt": .zeroIntraEU
        case "0 ex": .zeroExport
        case "zw": .exempt
        case "np i", "np": .notSubjectAbroad
        case "np ii": .notSubjectArt100
        case "oo": .reverseCharge
        default: .rate(raw)
        }
    }

    static func annotations(_ fa: XMLNode, _ ns: String) -> [InvoiceAnnotation] {
        guard let a = fa.find("Adnotacje", ns: ns) else { return [] }
        func on(_ p: String) -> Bool { a.text(p, ns: ns).trimmed == "1" }
        var result: [InvoiceAnnotation] = []
        if on("P_16") { result.append(.cashMethod) }
        if on("P_17") { result.append(.selfBilling) }
        if on("P_18") { result.append(.reverseCharge) }
        if on("P_18A") { result.append(.splitPayment) }
        if on("Zwolnienie/P_19") {
            let basis = ["P_19A", "P_19B", "P_19C"].map { a.text("Zwolnienie/\($0)", ns: ns).trimmed }.first { !$0.isEmpty } ?? ""
            result.append(.exemption(basis: basis))
        }
        if on("NoweSrodkiTransportu/P_22") { result.append(.newTransport) }
        if on("P_23") { result.append(.triangular) }
        if on("PMarzy/P_PMarzy") { result.append(.margin) }
        return result
    }

    static func payment(_ fa: XMLNode, _ ns: String) -> InvoicePayment {
        var p = InvoicePayment()
        guard let node = fa.find("Platnosc", ns: ns) else { return p }
        func t(_ path: String) -> String { node.text(path, ns: ns).trimmed }
        p.isPaid = t("Zaplacono") == "1"
        p.paidDate = LocalDate(iso: t("DataZaplaty"))
        p.dueDates = node.findAll("TerminPlatnosci", ns: ns).compactMap { LocalDate(iso: $0.text("Termin", ns: ns).trimmed) }
        p.dueDescription = node.findAll("TerminPlatnosci/TerminOpis", ns: ns).map { term in
            [term.text("Ilosc", ns: ns), term.text("Jednostka", ns: ns), term.text("ZdarzeniePoczatkowe", ns: ns)]
                .map(\.trimmed).filter { !$0.isEmpty }.joined(separator: " ")
        }.filter { !$0.isEmpty }.joined(separator: "; ")
        p.formCode = t("FormaPlatnosci")
        if t("PlatnoscInna") == "1" { p.otherForm = t("OpisPlatnosci") }
        p.bankAccounts = node.findAll("RachunekBankowy", ns: ns).compactMap { account in
            let number = account.text("NrRB", ns: ns).trimmed.replacingOccurrences(of: " ", with: "")
            guard !number.isEmpty else { return nil }
            return InvoiceBankAccount(number: number, bankName: account.text("NazwaBanku", ns: ns).trimmed,
                                      swift: account.text("SWIFT", ns: ns).trimmed)
        }
        return p
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
