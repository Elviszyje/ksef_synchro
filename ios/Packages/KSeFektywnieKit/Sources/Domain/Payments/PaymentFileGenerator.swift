import Foundation

/// Dane firmy-płatnika potrzebne w pliku przelewów.
public struct PaymentPayer: Hashable, Sendable {
    public var debitAccount: String
    public var name: String
    public var address: String

    public init(debitAccount: String, name: String, address: String) {
        self.debitAccount = debitAccount
        self.name = name
        self.address = address
    }
}

/// Format pliku przelewów. Wartości surowe zgodne z `PaymentFile.FORMAT_*` w Django.
public enum PaymentFileFormat: String, CaseIterable, Codable, Sendable {
    case erste
    case mbank
    case elixir

    public var fileExtension: String { self == .elixir ? "pli" : "txt" }

    public var label: String {
        switch self {
        case .erste: "Erste Bank"
        case .mbank: "mBank"
        case .elixir: "Elixir-0"
        }
    }

    /// Format dla banku rachunku obciążanego; banki bez własnego formatu → Elixir-0.
    public static func forBank(_ bankKey: String) -> PaymentFileFormat {
        switch bankKey {
        case "erste": .erste
        case "mbank": .mbank
        default: .elixir
        }
    }

    public func generator(payer: PaymentPayer) -> PaymentFileGenerator {
        switch self {
        case .erste: ErsteBankGenerator(payer: payer)
        case .mbank: MBankGenerator(payer: payer)
        case .elixir: ElixirGenerator(payer: payer)
        }
    }

    /// `przelewy_YYYYMMDD_<Bank>.<ext>` jak w Django.
    public static func fileName(bankKey: String, date: LocalDate) -> String {
        "przelewy_\(date.compact)_\(BankDetection.fileSuffix(for: bankKey)).\(forBank(bankKey).fileExtension)"
    }
}

/// Generator pliku przelewów — port `BasePaymentGenerator`.
public protocol PaymentFileGenerator: Sendable {
    func headerLines() -> [String]
    func lines(for invoice: Invoice, executionDate: LocalDate) -> [String]
}

extension PaymentFileGenerator {
    public func headerLines() -> [String] { [] }

    /// Linie łączone CRLF, bez końcowego CRLF, kodowanie CP1250 z `?` dla znaków spoza strony kodowej.
    public func generate(_ invoices: [Invoice], executionDate: LocalDate) -> Data {
        var all = headerLines()
        for invoice in invoices { all += lines(for: invoice, executionDate: executionDate) }
        return CP1250.encode(all.joined(separator: "\r\n"))
    }
}

/// Wspólne pomocniki tekstowe generatorów.
public enum PaymentText {
    static let plTransliteration: [Unicode.Scalar: Unicode.Scalar] = {
        let from = Array("ąćęłńóśźżĄĆĘŁŃÓŚŹŻ".unicodeScalars)
        let to = Array("acelnoszzACELNOSZZ".unicodeScalars)
        return Dictionary(uniqueKeysWithValues: zip(from, to))
    }()

    static let allowedPunctuation = Set("-.,:;+=[]{}!@#$%^&*()/?".unicodeScalars)

    /// Transliteracja PL, zamiana niedozwolonych znaków na spację, obcięcie i strip
    /// (port `_clean_text`).
    public static func clean(_ text: String, maxLength: Int) -> String {
        var view = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let s = plTransliteration[scalar] ?? scalar
            if PyText.isWord(s) || PyText.isSpace(s) || allowedPunctuation.contains(s) {
                view.append(s)
            } else {
                view.append(" ")
            }
        }
        return PyText.strip(PyText.prefix(String(view), maxLength))
    }

    /// Kwota w formacie `zzzzzzzzzz,gg` (port `format_amount`, zaokrąglenie bankierskie).
    public static func formatAmount(_ amount: Decimal) -> String {
        let cents = amount.minorUnits
        let sign = cents < 0 ? "-" : ""
        let absolute = cents.magnitude
        return "\(sign)\(absolute / 100),\(String(format: "%02d", absolute % 100))"
    }

    /// Tytuł przelewu w mechanizmie podzielonej płatności.
    static func splitPaymentTitle(_ invoice: Invoice) -> (vat: String, rest: String) {
        let vat = (invoice.vatAmountSplit.flatMap { $0 != 0 ? $0 : nil }) ?? invoice.amountVAT
        let number = clean(invoice.invoiceNumber, maxLength: 35)
        let freeText = clean("Faktura \(invoice.invoiceNumber)", maxLength: 33)
        return ("/VAT/\(formatAmount(vat))", "/IDC/\(invoice.sellerNIP)/INV/\(number)/TXT/\(freeText)")
    }
}
