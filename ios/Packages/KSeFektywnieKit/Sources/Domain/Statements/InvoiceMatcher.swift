import Foundation

public enum MatchType: String, Codable, Sendable, CaseIterable {
    case amount
    case nip
    case invoiceNumber = "invoice_nr"
    case manual
}

public enum MatchConfidence: String, Codable, Sendable, CaseIterable {
    case high
    case medium
    case low
}

/// Transakcja w postaci potrzebnej matcherowi. Opis to opis + kontrahent,
/// tak jak w `BankStatementReviewView._run_matcher`.
public struct MatchableTransaction: Hashable, Sendable {
    public var amount: Decimal
    public var isCredit: Bool
    public var description: String
    public var reference: String

    public init(amount: Decimal, isCredit: Bool, description: String, reference: String) {
        self.amount = amount
        self.isCredit = isCredit
        self.description = description
        self.reference = reference
    }

    public init(_ tx: ParsedTransaction) {
        self.init(amount: tx.amount, isCredit: tx.isCredit,
                  description: PyText.strip("\(tx.description) \(tx.counterparty)"), reference: tx.reference)
    }
}

public protocol MatchCandidate {
    associatedtype ID: Hashable
    var id: ID { get }
    var invoiceNumber: String { get }
    var sellerNIP: String { get }
    var amountGross: Decimal { get }
    var bankAccountNumber: String { get }
}

extension Invoice: MatchCandidate {}

public struct InvoiceMatch<ID: Hashable>: Hashable {
    public var transactionIndex: Int
    public var invoiceID: ID
    public var type: MatchType
    public var confidence: MatchConfidence
}

/// Dopasowanie transakcji bankowych do faktur — port `InvoiceMatcher`.
///
/// Kolejność sygnałów: kwota + rachunek, kwota + numer FV + NIP, kwota + NIP,
/// kwota + numer FV (średnia pewność), unikalna kwota (niska pewność).
/// Wpływy (credit) są pomijane — faktury kosztowe opłacamy przelewem wychodzącym.
public enum InvoiceMatcher {
    static let nipPattern = PyRegex(#"(?:NIP\s*:?\s*)?(\d{10})"#)
    static let invoiceNumberPattern = PyRegex(
        #"(?:INVOICE|FAKTURA|FVS|FVZ|FV|INV|F-)\s*(?:NR\.?|NO\.?)?\s*[:\s/]?\s*([^\s,;|]{3,35})"#,
        options: .caseInsensitive)
    static let separators = PyRegex(#"[\s\-/]+"#)

    public static func match<C: MatchCandidate>(_ transactions: [MatchableTransaction], candidates: [C]) -> [InvoiceMatch<C.ID>] {
        var byAmount: [String: [C]] = [:]
        for invoice in candidates { byAmount[key(invoice.amountGross), default: []].append(invoice) }

        var results: [InvoiceMatch<C.ID>] = []
        for (index, tx) in transactions.enumerated() where !tx.isCredit {
            guard let sameAmount = byAmount[key(tx.amount)], !sameAmount.isEmpty,
                  let (invoice, type, confidence) = bestMatch(tx, sameAmount) else { continue }
            results.append(InvoiceMatch(transactionIndex: index, invoiceID: invoice.id, type: type, confidence: confidence))
        }
        return results
    }

    static func key(_ amount: Decimal) -> String { DecimalText.string(amount.rounded(scale: 2)) }

    static func bestMatch<C: MatchCandidate>(_ tx: MatchableTransaction, _ candidates: [C]) -> (C, MatchType, MatchConfidence)? {
        let number = invoiceNumberPattern.search(tx.description).flatMap { $0[1] }.map(normalizeInvoiceNumber)
        let nips = Set(nipPattern.all(tx.description).compactMap { $0[1] })
        let account = normalizeAccount(tx.reference)

        if !account.isEmpty, let inv = candidates.first(where: { normalizeAccount($0.bankAccountNumber) == account }) {
            return (inv, .invoiceNumber, .high)
        }
        if let number, !nips.isEmpty,
           let inv = candidates.first(where: { normalizeInvoiceNumber($0.invoiceNumber) == number && nips.contains($0.sellerNIP) }) {
            return (inv, .invoiceNumber, .high)
        }
        // Python iteruje po zbiorze NIP-ów w nieustalonej kolejności; przy wielu NIP-ach
        // w opisie i wielu kandydatach wynik może się różnić — tu wybieramy pierwszą fakturę.
        if !nips.isEmpty, let inv = candidates.first(where: { nips.contains($0.sellerNIP) }) {
            return (inv, .nip, .high)
        }
        if let number, let inv = candidates.first(where: { normalizeInvoiceNumber($0.invoiceNumber) == number }) {
            return (inv, .invoiceNumber, .medium)
        }
        if candidates.count == 1 {
            return (candidates[0], .amount, .low)
        }
        return nil
    }

    static func normalizeAccount(_ account: String) -> String {
        String(String.UnicodeScalarView(account.unicodeScalars.filter { !PyText.isSpace($0) }))
    }

    /// Segmenty liczbowe bez wiodących zer: "FV/0030/26" == "FV/30/26".
    public static func normalizeInvoiceNumber(_ number: String) -> String {
        let text = PyText.strip(number) as NSString
        var segments: [String] = []
        var last = 0
        for m in separators.regex.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
            segments.append(text.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        segments.append(text.substring(from: last))
        return segments.map { segment in
            let upper = segment.uppercased()
            if PyText.isDigits(upper), let value = Int(upper) { return String(value) }
            return upper
        }.joined()
    }
}
