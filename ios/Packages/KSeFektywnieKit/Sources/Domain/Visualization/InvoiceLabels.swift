import Foundation

/// Etykiety i formaty liczb na wydruku faktury. Język wybiera szablon, nie ustawienia telefonu,
/// więc teksty są tu, a nie w katalogu tłumaczeń aplikacji.
public struct InvoiceLabels: Sendable {
    public let language: InvoiceLanguage

    public init(_ language: InvoiceLanguage) { self.language = language }

    func pick(_ pl: String, _ en: String) -> String {
        switch language {
        case .pl: pl
        case .en: en
        case .plEn: pl == en ? pl : "\(pl) / \(en)"
        }
    }

    public func title(_ kind: InvoiceKind) -> String {
        switch kind {
        case .vat: pick("Faktura VAT", "VAT invoice")
        case .correction: pick("Faktura korygująca", "Corrective invoice")
        case .advance: pick("Faktura zaliczkowa", "Advance invoice")
        case .settlement: pick("Faktura rozliczeniowa", "Settlement invoice")
        case .simplified: pick("Faktura uproszczona", "Simplified invoice")
        case .advanceCorrection: pick("Korekta faktury zaliczkowej", "Corrective advance invoice")
        case .settlementCorrection: pick("Korekta faktury rozliczeniowej", "Corrective settlement invoice")
        }
    }

    public var numberPrefix: String { pick("nr", "No.") }
    public var issueDate: String { pick("Data wystawienia", "Issue date") }
    public var issuePlace: String { pick("Miejsce wystawienia", "Place of issue") }
    public var saleDate: String { pick("Data dostawy / wykonania usługi", "Delivery date") }
    public var salePeriod: String { pick("Okres dostawy", "Supply period") }
    public var seller: String { pick("Sprzedawca", "Seller") }
    public var buyer: String { pick("Nabywca", "Buyer") }
    public var nip: String { pick("NIP", "Tax ID") }
    public var taxID: String { pick("Identyfikator podatkowy", "Tax ID") }
    public var email: String { "E-mail" }
    public var phone: String { pick("Tel.", "Phone") }

    /// Wąska kolumna: przy etykietach dwujęzycznych zostaje polskie „Lp.”.
    public var colNumber: String { language == .en ? "No." : "Lp." }
    public var colName: String { pick("Nazwa towaru lub usługi", "Description") }
    public var colUnit: String { pick("J.m.", "Unit") }
    public var colQuantity: String { pick("Ilość", "Qty") }
    public var colUnitNet: String { pick("Cena netto", "Unit price") }
    public var colUnitGross: String { pick("Cena brutto", "Unit gross") }
    public var colDiscount: String { pick("Rabat", "Discount") }
    public var colRate: String { pick("VAT", "VAT") }
    public var colNet: String { pick("Wartość netto", "Net amount") }
    public var colGross: String { pick("Wartość brutto", "Gross amount") }
    public var beforeCorrection: String { pick("stan przed korektą", "before correction") }

    public var vatSummary: String { pick("Podsumowanie stawek VAT", "VAT summary") }
    public var rate: String { pick("Stawka", "Rate") }
    public var net: String { pick("Netto", "Net") }
    public var vat: String { pick("Kwota VAT", "VAT") }
    public var gross: String { pick("Brutto", "Gross") }
    public var total: String { pick("Razem", "Total") }
    public var amountDue: String { pick("Do zapłaty", "Amount due") }
    public var paid: String { pick("Zapłacono", "Paid") }
    public var correctionAmount: String { pick("Kwota korekty", "Correction amount") }
    public var inWords: String { pick("Słownie", "In words") }
    public var vatInPLN: String { pick("VAT w PLN", "VAT in PLN") }

    public var payment: String { pick("Płatność", "Payment") }
    public var paymentForm: String { pick("Forma płatności", "Payment method") }
    public var dueDate: String { pick("Termin płatności", "Due date") }
    public var paidOn: String { pick("Zapłacono dnia", "Paid on") }
    public var bankAccount: String { pick("Rachunek bankowy", "Bank account") }

    public var correctedInvoice: String { pick("Faktura korygowana", "Corrected invoice") }
    public var correctionReason: String { pick("Przyczyna korekty", "Reason for correction") }
    public var notes: String { pick("Informacje dodatkowe", "Additional information") }
    public var annotations: String { pick("Adnotacje", "Notes") }
    public var ksefNumber: String { pick("Numer KSeF", "KSeF number") }
    public var verifyCaption: String { pick("Zeskanuj, aby sprawdzić fakturę w KSeF", "Scan to verify the invoice in KSeF") }
    public var draftWatermark: String { pick("PROJEKT", "DRAFT") }
    public var draftNotice: String {
        pick("Projekt faktury — nie została jeszcze wysłana do KSeF.", "Draft — this invoice has not been sent to KSeF yet.")
    }
    public var costNotice: String {
        pick("Wizualizacja faktury pobranej z KSeF. Dokumentem jest plik XML w KSeF.",
             "Visualization of an invoice downloaded from KSeF. The legally binding document is the XML file in KSeF.")
    }
    public var issuedBy: String { pick("Wystawił(a)", "Issued by") }
    public var receivedBy: String { pick("Odebrał(a)", "Received by") }

    public func page(_ page: Int, of total: Int) -> String {
        switch language {
        case .pl: "Strona \(page) z \(total)"
        case .en: "Page \(page) of \(total)"
        case .plEn: "\(page) / \(total)"
        }
    }

    public func paymentForm(code: String) -> String {
        switch code {
        case "1": pick("gotówka", "cash")
        case "2": pick("karta", "card")
        case "3": pick("bon", "voucher")
        case "4": pick("czek", "cheque")
        case "5": pick("kredyt", "credit")
        case "6": pick("przelew", "bank transfer")
        case "7": pick("płatność mobilna", "mobile payment")
        default: code
        }
    }

    public func rate(_ rate: VATSummaryRate) -> String {
        switch rate {
        case .rate(let r): Self.lineRate(r)
        case .taxi: pick("ryczałt taxi", "flat-rate taxi")
        case .oss: "OSS"
        case .zeroDomestic: pick("0% kraj", "0% domestic")
        case .zeroIntraEU: pick("0% WDT", "0% intra-EU")
        case .zeroExport: pick("0% eksport", "0% export")
        case .exempt: pick("zw", "exempt")
        case .notSubjectAbroad: pick("np", "out of scope")
        case .notSubjectArt100: pick("np art. 100", "out of scope art. 100")
        case .reverseCharge: pick("odwrotne obciążenie", "reverse charge")
        case .margin: pick("marża", "margin")
        }
    }

    /// Stawka pozycji (`P_12`) w czytelnej postaci.
    public func lineRate(_ raw: String) -> String { Self.lineRate(raw) }

    static func lineRate(_ raw: String) -> String {
        switch raw.lowercased() {
        case "": ""
        // Kody z FA są krótkie i jednoznaczne w każdym języku; pełna nazwa jest w podsumowaniu stawek.
        case "zw": "zw"
        case "np i", "np": "np"
        case "np ii": "np II"
        case "oo": "o.o."
        case "0 kr", "0 wdt", "0 ex": raw.replacingOccurrences(of: " ", with: "% ")
        default: raw.allSatisfy { $0.isNumber || $0 == "." || $0 == "," } ? "\(raw)%" : raw
        }
    }

    public func annotation(_ a: InvoiceAnnotation) -> String {
        switch a {
        case .cashMethod: pick("Metoda kasowa", "Cash accounting")
        case .selfBilling: pick("Samofakturowanie", "Self-billing")
        case .reverseCharge: pick("Odwrotne obciążenie", "Reverse charge")
        case .splitPayment: pick("Mechanizm podzielonej płatności", "Split payment")
        case .exemption(let basis):
            basis.isEmpty ? pick("Zwolnienie z VAT", "VAT exemption") : "\(pick("Zwolnienie z VAT", "VAT exemption")): \(basis)"
        case .newTransport: pick("Wewnątrzwspólnotowa dostawa nowych środków transportu", "Intra-EU supply of new means of transport")
        case .triangular: pick("Procedura trójstronna uproszczona", "Simplified triangular procedure")
        case .margin: pick("Procedura marży", "Margin scheme")
        }
    }

    public func amountInWords(_ amount: Decimal, currency: String) -> String {
        switch language {
        case .pl, .plEn: AmountInWords.polish(amount, currency: currency)
        case .en: AmountInWords.english(amount, currency: currency)
        }
    }

    // MARK: Liczby i daty

    /// Kwota z dwoma miejscami: `1 234,56` (pl) albo `1,234.56` (en).
    public func amount(_ value: Decimal) -> String {
        let fixed = FA3Generator.fixed(value, 2)
        return grouped(fixed)
    }

    /// Ilość bez zbędnych zer, do 4 miejsc: `1,5` / `1.5`.
    public func quantity(_ value: Decimal) -> String {
        var text = FA3Generator.fixed(value, 4)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return grouped(text)
    }

    func grouped(_ canonical: String) -> String {
        let (decimalSep, groupSep) = language == .en ? (".", ",") : (",", "\u{00A0}")
        var text = canonical
        let negative = text.hasPrefix("-")
        if negative { text.removeFirst() }
        let parts = text.split(separator: ".", maxSplits: 1).map(String.init)
        var integer = parts[0]
        var groups: [String] = []
        while integer.count > 3 { groups.insert(String(integer.suffix(3)), at: 0); integer.removeLast(3) }
        groups.insert(integer, at: 0)
        var result = groups.joined(separator: groupSep)
        if parts.count > 1 { result += decimalSep + parts[1] }
        return (negative ? "-" : "") + result
    }

    public func date(_ date: LocalDate) -> String {
        language == .en ? date.iso : String(format: "%02d.%02d.%04d", date.day, date.month, date.year)
    }
}
