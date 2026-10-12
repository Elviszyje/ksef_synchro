import Foundation

/// Parser XML faktur FA(2) i FA(3) — port `apps/ksef/parser.py`.
/// Przestrzeń nazw jest wykrywana z elementu głównego, więc nowe wersje
/// schematu o tej samej strukturze działają bez zmian w kodzie.
public enum FAParser {
    public static let knownNamespaces = [
        "http://crd.gov.pl/wzor/2023/06/29/12648/", // FA(2)
        "http://crd.gov.pl/wzor/2024/06/19/12648/", // FA(3) — wersja robocza
        "http://crd.gov.pl/wzor/2025/06/25/13775/", // FA(3) — wersja produkcyjna
    ]

    static let paymentForms = [
        "1": "gotówka", "2": "karta", "3": "bon/voucher", "4": "czek",
        "5": "kredyt", "6": "przelew", "7": "płatność mobilna",
    ]

    static func namespace(of tree: XMLTree) -> String {
        if !tree.root.namespace.isEmpty { return tree.root.namespace }
        for ns in knownNamespaces where tree.declaredNamespaces.contains(ns) { return ns }
        return knownNamespaces[0]
    }

    public static func parse(_ xml: Data, ksefReferenceNumber: String = "") -> ParsedInvoice {
        var result = ParsedInvoice(ksefReferenceNumber: ksefReferenceNumber)
        result.rawXML = String(decoding: xml, as: UTF8.self)
        guard let tree = XMLTree.parse(xml) else { return result }
        let ns = namespace(of: tree)
        let root = tree.root
        func t(_ path: String) -> String { root.text(path, ns: ns) }

        result.invoiceNumber = t(".//Fa/P_2").nonEmpty ?? t(".//Naglowek/NumerFaktury")
        result.issueDate = t(".//Fa/P_1").nonEmpty ?? t(".//Naglowek/DataWystawienia")
        result.paymentDueDate = t(".//Platnosc/TerminPlatnosci/Termin").nonEmpty ?? t(".//Platnosc/DataZaplaty").nonEmpty

        if let seller = root.find(".//Podmiot1", ns: ns) {
            func s(_ path: String) -> String { seller.text(path, ns: ns) }
            result.sellerNIP = s("DaneIdentyfikacyjne/NIP").nonEmpty ?? s(".//NIP")
            result.sellerName = s("DaneIdentyfikacyjne/PelnaNazwa").nonEmpty
                ?? s("DaneIdentyfikacyjne/Nazwa").nonEmpty
                ?? s(".//PelnaNazwa").nonEmpty
                ?? s(".//Nazwa").nonEmpty
                ?? [s(".//Imie"), s(".//Nazwisko")].filter { !$0.isEmpty }.joined(separator: " ")
            let address = [s("Adres/AdresL1"), s("Adres/AdresL2")].filter { !$0.isEmpty }.joined(separator: ", ")
            result.sellerAddress = PyText.prefix(address, 60)
        }

        if let buyer = root.find(".//Podmiot2", ns: ns) {
            result.buyerNIP = buyer.text("DaneIdentyfikacyjne/NIP", ns: ns)
        }

        (result.amountNet, result.amountVAT, result.amountGross) = amounts(root, ns)

        result.currency = t(".//Fa/KodWaluty").nonEmpty ?? t(".//Naglowek/KodWaluty").nonEmpty ?? "PLN"
        result.invoiceType = t(".//RodzajFaktury")

        var seen = Set<String>()
        var names: [String] = []
        for row in root.findAll(".//FaWiersz", ns: ns) {
            let name = row.text("P_7", ns: ns)
            if !name.isEmpty, seen.insert(name).inserted { names.append(name) }
        }
        result.description = names.joined(separator: "; ")

        result.isSplitPayment = t(".//Platnosc/MechanizmPodzielonejPlatnosci") == "T"
        result.isPaid = t(".//Platnosc/Zaplacono") == "1"
        result.paymentDate = t(".//Platnosc/DataZaplaty").nonEmpty
        let formCode = t(".//Platnosc/FormaPlatnosci")
        result.paymentForm = paymentForms[formCode] ?? formCode
        result.bankAccountNumber = bankAccount(root, ns)
        result.paymentTitle = "Faktura \(result.invoiceNumber)"
        return result
    }

    /// Pozycje faktury z zapisanego XML (port `parse_line_items`).
    public static func lineItems(rawXML: String) -> [InvoiceLineItem] {
        guard !rawXML.isEmpty, let tree = XMLTree.parse(Data(rawXML.utf8)) else { return [] }
        let ns = namespace(of: tree)
        return tree.root.findAll(".//FaWiersz", ns: ns).map { row in
            func t(_ p: String) -> String { row.text(p, ns: ns) }
            return InvoiceLineItem(nr: t("NrWierszaFa"), name: t("P_7"), unit: t("P_8A"), qty: t("P_8B"),
                                   unitPrice: t("P_9A"), netValue: t("P_11"), vatRate: t("P_12"))
        }
    }

    static func decimal(_ node: XMLNode, _ path: String, _ ns: String) -> Decimal {
        let raw = node.text(path, ns: ns).replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")
        return DecimalText.parse(raw) ?? 0
    }

    /// Pola sum netto FA(2)/FA(3): 1=23/22%, 2=8/7%, 3=5%, 4=ryczałt taxi, 5=OSS,
    /// 6_1/6_2/6_3=0% (kraj/WDT/eksport), 7=zw, 8/9=np, 10=odwrotne obciążenie, 11=marża.
    static let netFields = ["P_13_1", "P_13_2", "P_13_3", "P_13_4", "P_13_5", "P_13_6_1", "P_13_6_2", "P_13_6_3",
                            "P_13_7", "P_13_8", "P_13_9", "P_13_10", "P_13_11"]

    /// P_15 = brutto; P_13_x = netto per stawka; P_14_1…P_14_5 = VAT.
    static func amounts(_ root: XMLNode, _ ns: String) -> (Decimal, Decimal, Decimal) {
        var gross = decimal(root, ".//Fa/P_15", ns)
        var net: Decimal = 0
        var vat: Decimal = 0
        for field in netFields { net += decimal(root, ".//Fa/\(field)", ns) }
        for i in 1...5 { vat += decimal(root, ".//Fa/P_14_\(i)", ns) }
        if net == 0 {
            for row in root.findAll(".//FaWiersz", ns: ns) { net += decimal(row, "P_11", ns) }
            if net != 0 && gross != 0 { vat = gross - net }
        }
        if gross == 0 && net != 0 { gross = net + vat }
        return (net, vat, gross)
    }

    static func bankAccount(_ root: XMLNode, _ ns: String) -> String {
        let paths = [
            ".//Platnosc/NrKonta/NrRB",
            ".//Platnosc/RachunekBankowy/NrRB",
            ".//Platnosc/RachunekBankowy/NumerRachunku",
            ".//Podmiot1/NrKonta/NrRB",
            ".//Podmiot1/RachunekBankowy/NrRB",
            ".//Podmiot1/RachunekBankowy/NumerRachunku",
        ]
        for path in paths {
            let raw = root.text(path, ns: ns)
            guard !raw.isEmpty else { continue }
            var account = raw.replacingOccurrences(of: " ", with: "").uppercased()
            if account.hasPrefix("PL") { account.removeFirst(2) }
            if account.count == 26 && PyText.isDigits(account) { return account }
        }
        return ""
    }
}

extension String {
    /// Pythonowe `a or b` dla napisów: pusty napis jest "fałszywy".
    var nonEmpty: String? { isEmpty ? nil : self }
}
