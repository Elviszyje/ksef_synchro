import Foundation

/// Parser SWIFT MT940 — port `apps/bank_statements/parsers/mt940.py`.
/// Obsługiwane tagi: :25: :60F: :60M: :61: :86:.
public enum MT940Parser {
    // `\z` zamiast `\Z`: w ICU `\Z` dopuszcza końcowy znak nowej linii, w Pythonie nie.
    static let field = PyRegex(#":(\d{2}[A-Z]?):(.*?)(?=:\d{2}[A-Z]?:|\z)"#, options: .dotMatchesLineSeparators)
    static let line61 = PyRegex(
        #"^(\d{6})(\d{4})?(R?[DC])([A-Z]{0,3})([\d,]+)([A-Z]{4})(.{0,16})(?://(.{0,16}))?(?:\r?\n(.*))?$"#,
        options: .dotMatchesLineSeparators)
    static let line61Fallback = PyRegex(#"^(\d{6})(\d{4})?(R?[DC])([A-Z]{0,3})([\d,]+)(.+)"#)
    static let balanceDate = PyRegex(#"[CD](\d{6})"#)
    static let detectTag = PyRegex(#":\d{2}[A-Z]?:"#)

    public static func detect(_ content: String) -> Bool {
        detectTag.search(PyText.prefix(content, 500)) != nil
    }

    public static func parse(_ content: String) -> ParsedStatement {
        let normalized = PyText.strip(content, chars: "\u{FEFF}")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var statement = ParsedStatement(bankKey: "mt940")
        for groups in field.all(normalized) {
            let tag = (groups[1] ?? "").uppercased()
            let value = groups[2] ?? ""
            switch tag {
            case "25":
                statement.accountNumber = PyText.strip(value)
                    .replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "/", with: "")
            case "60F", "60M":
                statement.statementDate = parseBalanceDate(value)
            case "61":
                if let tx = parseTransaction(value, referenceDate: statement.statementDate) {
                    statement.transactions.append(tx)
                }
            case "86":
                guard var last = statement.transactions.popLast() else { continue }
                let extra = PyText.strip(value).replacingOccurrences(of: "\n", with: " ")
                last.description = last.description.isEmpty ? extra : PyText.strip("\(last.description) \(extra)")
                statement.transactions.append(last)
            default:
                continue
            }
        }
        return statement
    }

    static func parseDate6(_ s: String) -> LocalDate? {
        guard s.count == 6, let yy = Int(s.prefix(2)), let mm = Int(s.dropFirst(2).prefix(2)), let dd = Int(s.suffix(2)) else { return nil }
        return LocalDate(year: yy < 50 ? 2000 + yy : 1900 + yy, month: mm, day: dd)
    }

    static func parseBalanceDate(_ value: String) -> LocalDate? {
        guard let g = balanceDate.match(value), let d = g[1] else { return nil }
        return parseDate6(d)
    }

    static func parseTransaction(_ raw: String, referenceDate: LocalDate?) -> ParsedTransaction? {
        let text = PyText.strip(raw)
        let lines = text.components(separatedBy: "\n")
        let valueDateText: String, dc: String, amountText: String, reference: String, description: String

        if let m = line61.match(text) {
            valueDateText = m[1]!
            dc = m[3]!
            amountText = m[5]!
            reference = PyText.strip(m[7] ?? "")
            description = PyText.strip(m[9] ?? "")
        } else if let m = line61Fallback.match(lines[0]) {
            valueDateText = m[1]!
            dc = m[3]!
            amountText = m[5]!
            reference = PyText.prefix(m[6] ?? "", 35)
            description = lines.dropFirst().joined(separator: " ")
        } else {
            return nil
        }

        let valueDate = parseDate6(valueDateText) ?? referenceDate ?? .today()
        let amount = DecimalText.parse(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let upper = dc.uppercased()
        return ParsedTransaction(
            transactionDate: valueDate, valueDate: valueDate, amount: amount, currency: "PLN",
            isCredit: upper.contains("C") && !upper.contains("D"),
            description: description, reference: reference)
    }
}
