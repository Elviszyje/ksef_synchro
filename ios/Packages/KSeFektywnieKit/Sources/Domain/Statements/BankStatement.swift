import Foundation

public enum BankStatementStatus: String, Codable, Sendable {
    case pending, reviewed, confirmed
}

/// Zaimportowany wyciąg (odpowiednik `BankStatement` w Django).
public struct BankStatement: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var companyID: UUID
    public var fileName: String
    public var accountNumber: String
    public var statementDate: LocalDate?
    public var status: BankStatementStatus
    public var fileFormat: String
    public var rawContent: String
    public var uploadedAt: Date
    public var confirmedAt: Date?

    public init(id: UUID = UUID(), companyID: UUID, fileName: String, accountNumber: String, statementDate: LocalDate?,
                status: BankStatementStatus = .pending, fileFormat: String, rawContent: String,
                uploadedAt: Date = Date(), confirmedAt: Date? = nil) {
        self.id = id
        self.companyID = companyID
        self.fileName = fileName
        self.accountNumber = accountNumber
        self.statementDate = statementDate
        self.status = status
        self.fileFormat = fileFormat
        self.rawContent = rawContent
        self.uploadedAt = uploadedAt
        self.confirmedAt = confirmedAt
    }
}

public struct BankTransaction: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var statementID: UUID
    public var transactionDate: LocalDate
    public var valueDate: LocalDate
    public var amount: Decimal
    public var currency: String
    public var isDebit: Bool
    public var description: String
    public var counterparty: String
    public var reference: String
    public var isMatched: Bool

    public init(id: UUID = UUID(), statementID: UUID, transactionDate: LocalDate, valueDate: LocalDate, amount: Decimal,
                currency: String, isDebit: Bool, description: String, counterparty: String, reference: String, isMatched: Bool = false) {
        self.id = id
        self.statementID = statementID
        self.transactionDate = transactionDate
        self.valueDate = valueDate
        self.amount = amount
        self.currency = currency
        self.isDebit = isDebit
        self.description = description
        self.counterparty = counterparty
        self.reference = reference
        self.isMatched = isMatched
    }

    /// Wejście matchera: opis + kontrahent (jak `_run_matcher` w Django).
    public var matchable: MatchableTransaction {
        MatchableTransaction(amount: amount, isCredit: !isDebit,
                             description: "\(description) \(counterparty)".trimmingCharacters(in: .whitespaces),
                             reference: reference)
    }
}

public struct TransactionMatch: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var transactionID: UUID
    public var invoiceID: UUID
    public var type: MatchType
    public var confidence: MatchConfidence
    public var isConfirmed: Bool
    public var confirmedAt: Date?

    public init(id: UUID = UUID(), transactionID: UUID, invoiceID: UUID, type: MatchType, confidence: MatchConfidence,
                isConfirmed: Bool = false, confirmedAt: Date? = nil) {
        self.id = id
        self.transactionID = transactionID
        self.invoiceID = invoiceID
        self.type = type
        self.confidence = confidence
        self.isConfirmed = isConfirmed
        self.confirmedAt = confirmedAt
    }
}
