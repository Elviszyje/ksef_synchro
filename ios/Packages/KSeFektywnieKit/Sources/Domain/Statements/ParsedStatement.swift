import Foundation

public struct ParsedTransaction: Hashable, Sendable {
    public var transactionDate: LocalDate
    public var valueDate: LocalDate
    /// Kwota zawsze dodatnia; kierunek określa `isCredit`.
    public var amount: Decimal
    public var currency: String
    public var isCredit: Bool
    public var description: String
    public var counterparty: String
    public var reference: String

    public init(transactionDate: LocalDate, valueDate: LocalDate, amount: Decimal, currency: String,
                isCredit: Bool, description: String, counterparty: String = "", reference: String = "") {
        self.transactionDate = transactionDate
        self.valueDate = valueDate
        self.amount = amount
        self.currency = currency
        self.isCredit = isCredit
        self.description = description
        self.counterparty = counterparty
        self.reference = reference
    }
}

public struct ParsedStatement: Hashable, Sendable {
    public var accountNumber = ""
    public var statementDate: LocalDate?
    public var transactions: [ParsedTransaction] = []
    /// `mt940`, `erste`, `velobank`, `millennium` — zapisywane jako format pliku.
    public var bankKey = "other"

    public init(bankKey: String = "other") { self.bankKey = bankKey }
}

public enum StatementError: Error, Equatable, LocalizedError {
    case unrecognizedFormat
    case unreadableEncoding
    case emptyFile
    case missingAmountColumn
    case pdfNotSupported

    public var errorDescription: String? {
        switch self {
        case .unrecognizedFormat:
            "Nie rozpoznano formatu pliku. Obsługiwane formaty: MT940 (SWIFT), CSV VeloBank, CSV Erste Bank, Millennium (CSV, XLS, HTML)."
        case .unreadableEncoding:
            "Nie można odczytać pliku. Sprawdź kodowanie (UTF-8 lub Windows-1250)."
        case .emptyFile:
            "Pusty plik."
        case .missingAmountColumn:
            "Nie znaleziono kolumny \"Kwota\" w pliku CSV."
        case .pdfNotSupported:
            "Pliki PDF nie są obsługiwane — to wydruk, a nie wyciąg do importu. W bankowości wybierz eksport CSV, XLS albo HTML (Millennium) lub MT940."
        }
    }
}
