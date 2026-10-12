import Foundation

enum CSVAmount {
    /// `"1 234,56"` / `"-2 383,35"` → Decimal.
    static func parse(_ s: String) -> Decimal? {
        let clean = PyText.strip(PyText.strip(s), chars: "\"")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return DecimalText.parse(clean)
    }
}

/// Eksport CSV z VeloBank — port `velobank_csv.py`.
/// Wiersz 1: nagłówek wyciągu z NRB w polu 3; dalej transakcje, daty DD-MM-YYYY.
public enum VeloBankCSVParser {
    static let minColumns = 6

    static func parseDate(_ s: String) -> LocalDate? {
        let t = PyText.strip(s)
        return LocalDate.parse(t, order: .dmy, separator: "-")
            ?? LocalDate.parse(t, order: .ymd, separator: "-")
            ?? LocalDate.parse(t, order: .dmy, separator: ".")
    }

    public static func detect(_ content: String) -> Bool {
        let rows = CSVReader.nonEmptyRows(PyText.lstrip(content, chars: "\u{FEFF}"))
        guard rows.count >= 2, rows[0].count >= 8 else { return false }
        let digits = PyText.lstrip(PyText.strip(rows[0][2]), chars: "'").replacingOccurrences(of: " ", with: "")
        guard PyText.isDigits(digits), digits.count == 26 else { return false }
        guard rows[1].count >= minColumns else { return false }
        return parseDate(rows[1][0]) != nil
    }

    public static func parse(_ content: String) throws -> ParsedStatement {
        let rows = CSVReader.nonEmptyRows(PyText.lstrip(content, chars: "\u{FEFF}"))
        guard let header = rows.first else { throw StatementError.emptyFile }
        var statement = ParsedStatement(bankKey: "velobank")
        if header.count > 2 {
            statement.accountNumber = PyText.lstrip(PyText.strip(header[2]), chars: "'").replacingOccurrences(of: " ", with: "")
        }
        if let first = header.first, !PyText.strip(first).isEmpty {
            statement.statementDate = parseDate(first)
        }
        for row in rows.dropFirst() where row.count >= minColumns {
            guard let txDate = parseDate(row[0]) else { continue }
            let valueText = PyText.strip(row[1])
            let valueDate: LocalDate
            if valueText.isEmpty { valueDate = txDate } else {
                guard let d = parseDate(valueText) else { continue }
                valueDate = d
            }
            guard let amount = CSVAmount.parse(row[5]) else { continue }
            statement.transactions.append(ParsedTransaction(
                transactionDate: txDate, valueDate: valueDate, amount: abs(amount), currency: "PLN",
                isCredit: amount >= 0, description: PyText.strip(row[2]), counterparty: PyText.strip(row[3]),
                reference: PyText.prefix(PyText.strip(row[4]), 35)))
        }
        return statement
    }
}

/// Eksport CSV z Erste Bank — port `erste_csv.py`. Separator `;` (lub `,`), daty DD.MM.YYYY.
public enum ErsteCSVParser {
    static let minColumns = 6
    static let headerVariants: [[String]] = [
        ["nr rachunku", "data transakcji", "data ksiegowania", "opis transakcji", "kwota", "waluta"],
        ["numer rachunku", "data operacji", "data waluty", "opis", "kwota", "waluta"],
    ]

    static func parseDate(_ s: String) -> LocalDate? {
        let t = PyText.strip(PyText.strip(s), chars: "\"")
        return LocalDate.parse(t, order: .dmy, separator: ".")
            ?? LocalDate.parse(t, order: .ymd, separator: "-")
            ?? LocalDate.parse(t, order: .dmy, separator: "-")
    }

    static func normalizedHeader(_ row: [String]) -> [String] {
        row.map { PyText.strip(PyText.strip($0), chars: "\"").lowercased() }
    }

    static func isHeader(_ row: [String]) -> Bool {
        let normalized = normalizedHeader(row)
        if headerVariants.contains(where: { $0.allSatisfy(normalized.contains) }) { return true }
        guard let first = normalized.first else { return false }
        return first.contains("rachunek") || first.contains("konto")
    }

    public static func detect(_ content: String) -> Bool {
        let text = PyText.lstrip(content, chars: "\u{FEFF}")
        for sep: Character in [";", ","] {
            let rows = CSVReader.nonEmptyRows(text, delimiter: sep)
            guard rows.count >= 2, isHeader(rows[0]), rows[1].count >= minColumns else { continue }
            if rows[1].dropFirst().prefix(2).contains(where: { parseDate($0) != nil }) { return true }
        }
        return false
    }

    public static func parse(_ content: String) throws -> ParsedStatement {
        let text = PyText.lstrip(content, chars: "\u{FEFF}")
        var separator: Character = ";"
        for sep: Character in [";", ","] {
            let rows = CSVReader.nonEmptyRows(text, delimiter: sep)
            if rows.count >= 2, isHeader(rows[0]) { separator = sep; break }
        }
        let rows = CSVReader.nonEmptyRows(text, delimiter: separator)
        guard let headerRow = rows.first else { throw StatementError.emptyFile }
        let header = normalizedHeader(headerRow)
        func column(_ names: [String]) -> Int? { names.lazy.compactMap { header.firstIndex(of: $0) }.first }

        let account = column(["nr rachunku", "numer rachunku", "rachunek"])
        let date1 = column(["data transakcji", "data operacji", "data"])
        let date2 = column(["data ksiegowania", "data waluty", "data księgowania"])
        let desc = column(["opis transakcji", "opis", "tytul", "tytuł"])
        let currencyColumn = column(["waluta"])
        guard let amountColumn = column(["kwota"]) else { throw StatementError.missingAmountColumn }

        var statement = ParsedStatement(bankKey: "erste")
        func cell(_ row: [String], _ idx: Int?) -> String {
            guard let idx, idx < row.count else { return "" }
            return PyText.strip(row[idx])
        }
        if let account, rows.count > 1 {
            statement.accountNumber = PyText.strip(cell(rows[1], account), chars: "\"").replacingOccurrences(of: " ", with: "")
        }
        for row in rows.dropFirst() where row.count > amountColumn {
            let d1 = cell(row, date1), d2 = cell(row, date2)
            guard !d1.isEmpty, let txDate = parseDate(d1) else { continue }
            var valueDate = txDate
            if !d2.isEmpty {
                guard let d = parseDate(d2) else { continue }
                valueDate = d
            }
            guard let amount = CSVAmount.parse(row[amountColumn]) else { continue }
            let currency = PyText.strip(cell(row, currencyColumn), chars: "\"")
            statement.transactions.append(ParsedTransaction(
                transactionDate: txDate, valueDate: valueDate, amount: abs(amount),
                currency: currencyColumn == nil ? "PLN" : (currency.nonEmpty ?? "PLN"),
                isCredit: amount >= 0, description: PyText.strip(cell(row, desc), chars: "\"")))
            if statement.statementDate == nil { statement.statementDate = txDate }
        }
        return statement
    }
}
