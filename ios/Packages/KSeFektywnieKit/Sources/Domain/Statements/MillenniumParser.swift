import Foundation

/// Historia transakcji z Banku Millennium — port `apps/bank_statements/parsers/millennium.py`.
///
/// Ta sama tabela w trzech formatach: CSV (`,`, pola w cudzysłowach, UTF-8 z BOM),
/// XLS (w rzeczywistości HTML z tabelą, kolumna „Waluta” bywa pusta) i HTML.
/// PDF jest wydrukiem i nie jest obsługiwany. Pola wielowierszowe są sklejane spacjami.
public enum MillenniumParser {
    static let bankKey = "millennium"

    static let account = "numer rachunku/karty"
    static let txDate = "data transakcji"
    static let valueDate = "data rozliczenia"
    static let kind = "rodzaj transakcji"
    static let counterAccount = "na konto/z konta"
    static let counterparty = "odbiorca/zleceniodawca"
    static let description = "opis"
    static let debit = "obciążenia"
    static let credit = "uznania"
    static let currency = "waluta"
    static let required = [account, txDate, valueDate, counterparty, description, debit, credit]

    /// Zwija białe znaki (nowe linie, twarde spacje) do pojedynczych spacji — jak `' '.join(s.split())`.
    static func clean(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func isHTML(_ text: String) -> Bool {
        let head = String(text.prefix(4096)).lowercased()
        return head.contains("<table") || head.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<html")
    }

    static func rows(_ content: String) -> [[String]] {
        let text = PyText.lstrip(content, chars: "\u{FEFF}")
        let rows = isHTML(text) ? HTMLTable.rows(text) : CSVReader.nonEmptyRows(text).map { $0.map(clean) }
        return rows.filter { $0.contains { !$0.isEmpty } }
    }

    static func headerIndex(_ row: [String]) -> [String: Int]? {
        let names = row.map { $0.lowercased() }
        guard required.allSatisfy(names.contains) else { return nil }
        var index: [String: Int] = [:]
        for (i, name) in names.enumerated() { index[name] = i }
        return index
    }

    static func parseDate(_ s: String) -> LocalDate? {
        let t = PyText.strip(s)
        return LocalDate.parse(t, order: .ymd, separator: "-")
            ?? LocalDate.parse(t, order: .dmy, separator: "-")
            ?? LocalDate.parse(t, order: .dmy, separator: ".")
    }

    static func parseAmount(_ s: String) -> Decimal? {
        let clean = s.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
        return clean.isEmpty ? nil : DecimalText.parse(clean)
    }

    public static func detect(_ content: String) -> Bool {
        guard let header = rows(content).first else { return false }
        return headerIndex(header) != nil
    }

    public static func parse(_ content: String) throws -> ParsedStatement {
        let rows = rows(content)
        guard let header = rows.first else { throw StatementError.emptyFile }
        guard let columns = headerIndex(header) else { throw StatementError.unrecognizedFormat }
        func cell(_ row: [String], _ name: String) -> String {
            guard let i = columns[name], i < row.count else { return "" }
            return row[i]
        }

        var statement = ParsedStatement(bankKey: bankKey)
        for row in rows.dropFirst() {
            guard let date = parseDate(cell(row, txDate)) else { continue }
            let creditAmount = parseAmount(cell(row, credit))
            guard let amount = creditAmount ?? parseAmount(cell(row, debit)) else { continue }
            if statement.accountNumber.isEmpty {
                let number = cell(row, account).replacingOccurrences(of: " ", with: "").uppercased()
                statement.accountNumber = number.hasPrefix("PL") ? String(number.dropFirst(2)) : number
            }
            statement.transactions.append(ParsedTransaction(
                transactionDate: date, valueDate: parseDate(cell(row, valueDate)) ?? date, amount: abs(amount),
                currency: cell(row, currency).uppercased().nonEmpty ?? "PLN", isCredit: creditAmount != nil,
                description: cell(row, description).nonEmpty ?? cell(row, kind),
                counterparty: cell(row, counterparty),
                reference: PyText.prefix(cell(row, counterAccount).replacingOccurrences(of: " ", with: ""), 35)))
            statement.statementDate = max(statement.statementDate ?? date, date)
        }
        return statement
    }
}

/// Wiersze tabeli HTML (`<tr>` → teksty komórek `<td>`/`<th>`) — odpowiednik `text_content()` z lxml:
/// znaczniki w komórce znikają, encje są dekodowane, białe znaki zwijane.
enum HTMLTable {
    static let rowPattern = try! NSRegularExpression(pattern: "<tr\\b[^>]*>(.*?)</tr\\s*>",
                                                     options: [.caseInsensitive, .dotMatchesLineSeparators])
    static let cellPattern = try! NSRegularExpression(pattern: "<t[dh]\\b[^>]*>(.*?)</t[dh]\\s*>",
                                                      options: [.caseInsensitive, .dotMatchesLineSeparators])
    static let tagPattern = try! NSRegularExpression(pattern: "<[^>]*>")

    static func rows(_ html: String) -> [[String]] {
        matches(rowPattern, in: html).map { row in
            matches(cellPattern, in: row).map { MillenniumParser.clean(decodeEntities(stripTags($0))) }
        }
    }

    static func matches(_ regex: NSRegularExpression, in text: String) -> [String] {
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    static func stripTags(_ text: String) -> String {
        tagPattern.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "")
    }

    static let namedEntities = ["nbsp": "\u{00A0}", "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'"]

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            result += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            if let semi = after.prefix(10).firstIndex(of: ";") {
                let name = String(after[..<semi])
                var decoded: String?
                if name.hasPrefix("#x") || name.hasPrefix("#X") {
                    decoded = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else if name.hasPrefix("#") {
                    decoded = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else {
                    decoded = namedEntities[name.lowercased()]
                }
                if let decoded {
                    result += decoded
                    rest = after[after.index(after: semi)...]
                    continue
                }
            }
            result += "&"
            rest = after
        }
        return result + rest
    }
}
