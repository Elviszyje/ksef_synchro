import Foundation
import GRDB
import Domain

extension BankStatement: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "bankStatement"

    public init(row: Row) throws {
        self.init(id: row["id"], companyID: row["companyId"], fileName: row["fileName"], accountNumber: row["accountNumber"],
                  statementDate: row["statementDate"], status: BankStatementStatus(rawValue: row["status"]) ?? .pending,
                  fileFormat: row["fileFormat"], rawContent: row["rawContent"], uploadedAt: row["uploadedAt"],
                  confirmedAt: row["confirmedAt"])
    }

    public func encode(to c: inout PersistenceContainer) throws {
        c["id"] = id
        c["companyId"] = companyID
        c["fileName"] = fileName
        c["accountNumber"] = accountNumber
        c["statementDate"] = statementDate
        c["status"] = status.rawValue
        c["fileFormat"] = fileFormat
        c["rawContent"] = rawContent
        c["uploadedAt"] = uploadedAt
        c["confirmedAt"] = confirmedAt
    }
}

extension BankTransaction: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "bankTransaction"

    public init(row: Row) throws {
        self.init(id: row["id"], statementID: row["bankStatementId"], transactionDate: row["transactionDate"],
                  valueDate: row["valueDate"], amount: Money.decimal(row["amount"] as Int64), currency: row["currency"],
                  isDebit: row["isDebit"], description: row["description"], counterparty: row["counterparty"],
                  reference: row["reference"], isMatched: row["isMatched"])
    }

    public func encode(to c: inout PersistenceContainer) throws {
        c["id"] = id
        c["bankStatementId"] = statementID
        c["transactionDate"] = transactionDate
        c["valueDate"] = valueDate
        c["amount"] = Money.db(amount)
        c["currency"] = currency
        c["isDebit"] = isDebit
        c["description"] = description
        c["counterparty"] = counterparty
        c["reference"] = reference
        c["isMatched"] = isMatched
    }
}

extension TransactionMatch: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "transactionMatch"

    public init(row: Row) throws {
        self.init(id: row["id"], transactionID: row["bankTransactionId"], invoiceID: row["invoiceId"],
                  type: MatchType(rawValue: row["matchType"]) ?? .manual,
                  confidence: MatchConfidence(rawValue: row["confidence"]) ?? .low,
                  isConfirmed: row["isConfirmed"], confirmedAt: row["confirmedAt"])
    }

    public func encode(to c: inout PersistenceContainer) throws {
        c["id"] = id
        c["bankTransactionId"] = transactionID
        c["invoiceId"] = invoiceID
        c["matchType"] = type.rawValue
        c["confidence"] = confidence.rawValue
        c["isConfirmed"] = isConfirmed
        c["confirmedAt"] = confirmedAt
    }
}

public enum StatementRepositoryError: Error, Equatable, LocalizedError {
    case alreadyConfirmed
    case nothingConfirmed

    public var errorDescription: String? {
        switch self {
        case .alreadyConfirmed: "Wyciąg jest już zatwierdzony."
        case .nothingConfirmed: "Potwierdź co najmniej jedno dopasowanie przed zatwierdzeniem wyciągu."
        }
    }
}

/// Podsumowanie wyciągu do listy.
public struct StatementSummary: Identifiable, Hashable, Sendable {
    public var statement: BankStatement
    public var debitCount: Int
    public var matchCount: Int
    public var confirmedCount: Int
    public var id: UUID { statement.id }
}

/// Transakcja z propozycjami dopasowań i danymi faktur do ekranu przeglądu.
public struct ReviewedTransaction: Identifiable, Hashable, Sendable {
    public var transaction: BankTransaction
    public var matches: [(match: TransactionMatch, invoice: Invoice)]
    public var id: UUID { transaction.id }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.transaction == rhs.transaction && lhs.matches.map(\.match) == rhs.matches.map(\.match)
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(transaction) }
}

/// Wyciągi bankowe — port `apps/bank_statements/views.py` (upload, review, toggle, confirm, delete).
public struct StatementRepository: Sendable {
    let db: AppDatabase
    public let companyID: UUID
    public let device: String

    public init(db: AppDatabase, companyID: UUID, device: String) {
        self.db = db
        self.companyID = companyID
        self.device = device
    }

    /// Import pliku: dekodowanie, rozpoznanie formatu, zapis transakcji i automatyczne dopasowanie
    /// do faktur w statusie „przekazano do opłacenia”.
    @discardableResult
    public func importStatement(fileName: String, data: Data, preferredBankKeys: [String] = [], now: Date = Date()) throws -> BankStatement {
        let content = try StatementImporter.decode(data)
        let parsed = try StatementImporter.parse(content, preferredBankKeys: preferredBankKeys)
        return try db.writer.write { db in
            let statement = BankStatement(companyID: companyID, fileName: fileName, accountNumber: parsed.accountNumber,
                                          statementDate: parsed.statementDate, fileFormat: parsed.bankKey,
                                          rawContent: content, uploadedAt: now)
            try statement.insert(db)
            var transactions: [BankTransaction] = []
            for tx in parsed.transactions {
                let row = BankTransaction(statementID: statement.id, transactionDate: tx.transactionDate, valueDate: tx.valueDate,
                                          amount: tx.amount, currency: tx.currency, isDebit: !tx.isCredit,
                                          description: tx.description, counterparty: tx.counterparty,
                                          reference: String(tx.reference.prefix(35)))
                try row.insert(db)
                transactions.append(row)
            }
            let candidates = try Invoice.filter(Column("companyId") == companyID)
                .filter(Column("status") == InvoiceStatus.sentForPayment.rawValue).fetchAll(db)
            for match in InvoiceMatcher.match(transactions.map(\.matchable), candidates: candidates) {
                try TransactionMatch(transactionID: transactions[match.transactionIndex].id, invoiceID: match.invoiceID,
                                     type: match.type, confidence: match.confidence).insert(db)
            }
            return statement
        }
    }

    public func summaries() throws -> [StatementSummary] {
        let companyID = companyID
        return try db.reader.read { try Self.fetchSummaries($0, companyID: companyID) }
    }

    public func observeSummaries() -> ValueObservation<ValueReducers.Fetch<[StatementSummary]>> {
        let companyID = companyID
        return ValueObservation.tracking { try Self.fetchSummaries($0, companyID: companyID) }
    }

    static func fetchSummaries(_ db: Database, companyID: UUID) throws -> [StatementSummary] {
        try BankStatement.filter(Column("companyId") == companyID).order(Column("uploadedAt").desc).fetchAll(db).map { s in
            let counts = try Row.fetchOne(db, sql: """
                SELECT
                  (SELECT COUNT(*) FROM bankTransaction WHERE bankStatementId = ? AND isDebit = 1) AS debits,
                  (SELECT COUNT(*) FROM transactionMatch m JOIN bankTransaction t ON t.id = m.bankTransactionId WHERE t.bankStatementId = ?) AS matches,
                  (SELECT COUNT(*) FROM transactionMatch m JOIN bankTransaction t ON t.id = m.bankTransactionId WHERE t.bankStatementId = ? AND m.isConfirmed = 1) AS confirmed
                """, arguments: [s.id, s.id, s.id])!
            return StatementSummary(statement: s, debitCount: counts["debits"], matchCount: counts["matches"],
                                    confirmedCount: counts["confirmed"])
        }
    }

    public func statement(_ id: UUID) throws -> BankStatement? {
        try db.reader.read { try BankStatement.filter(Column("companyId") == companyID).filter(key: id).fetchOne($0) }
    }

    /// Transakcje wyciągu z dopasowaniami (obciążenia najpierw, w kolejności dat).
    public func review(_ statementID: UUID) throws -> [ReviewedTransaction] {
        try db.reader.read { try Self.fetchReview($0, statementID: statementID) }
    }

    public func observeReview(_ statementID: UUID) -> ValueObservation<ValueReducers.Fetch<[ReviewedTransaction]>> {
        ValueObservation.tracking { try Self.fetchReview($0, statementID: statementID) }
    }

    static func fetchReview(_ db: Database, statementID: UUID) throws -> [ReviewedTransaction] {
        let transactions = try BankTransaction.filter(Column("bankStatementId") == statementID)
            .order(Column("isDebit").desc, Column("transactionDate"), Column("amount").desc).fetchAll(db)
        return try transactions.map { tx in
            let matches = try TransactionMatch.filter(Column("bankTransactionId") == tx.id).fetchAll(db)
            let pairs = try matches.compactMap { m in try Invoice.fetchOne(db, key: m.invoiceID).map { (m, $0) } }
            return ReviewedTransaction(transaction: tx, matches: pairs)
        }
    }

    public func setConfirmed(_ matchID: UUID, _ confirmed: Bool, now: Date = Date()) throws {
        try db.writer.write { db in
            guard var match = try TransactionMatch.fetchOne(db, key: matchID) else { return }
            match.isConfirmed = confirmed
            match.confirmedAt = confirmed ? now : nil
            try match.update(db)
        }
    }

    /// Faktury, które można ręcznie przypisać do transakcji: przekazane do opłacenia lub zaakceptowane;
    /// najpierw te z identyczną kwotą.
    public func manualCandidates(for transaction: BankTransaction) throws -> [Invoice] {
        try db.reader.read { db in
            let invoices = try Invoice.filter(Column("companyId") == companyID)
                .filter([InvoiceStatus.sentForPayment.rawValue, InvoiceStatus.accepted.rawValue].contains(Column("status")))
                .order(Column("paymentDueDate").ascNullsLast).fetchAll(db)
            return invoices.sorted { a, b in
                let ae = a.amountGross == transaction.amount, be = b.amountGross == transaction.amount
                return ae && !be
            }
        }
    }

    /// Ręczne przypisanie faktury — od razu potwierdzone.
    public func assignManually(transactionID: UUID, invoiceID: UUID, now: Date = Date()) throws {
        try db.writer.write { db in
            if var existing = try TransactionMatch.filter(Column("bankTransactionId") == transactionID)
                .filter(Column("invoiceId") == invoiceID).fetchOne(db) {
                existing.isConfirmed = true
                existing.confirmedAt = now
                try existing.update(db)
                return
            }
            try TransactionMatch(transactionID: transactionID, invoiceID: invoiceID, type: .manual, confidence: .high,
                                 isConfirmed: true, confirmedAt: now).insert(db)
        }
    }

    public func removeMatch(_ matchID: UUID) throws {
        _ = try db.writer.write { try TransactionMatch.deleteOne($0, key: matchID) }
    }

    /// Zatwierdzenie: potwierdzone dopasowania → faktury „opłacona” (z historią), wyciąg „zatwierdzony”.
    /// Zwraca liczbę faktur oznaczonych jako opłacone.
    @discardableResult
    public func confirm(_ statementID: UUID, now: Date = Date()) throws -> Int {
        try db.writer.write { db in
            guard var statement = try BankStatement.filter(Column("companyId") == companyID).filter(key: statementID).fetchOne(db) else { return 0 }
            guard statement.status != .confirmed else { throw StatementRepositoryError.alreadyConfirmed }
            let matches = try TransactionMatch.fetchAll(db, sql: """
                SELECT m.* FROM transactionMatch m JOIN bankTransaction t ON t.id = m.bankTransactionId
                WHERE t.bankStatementId = ? AND m.isConfirmed = 1
                """, arguments: [statementID])
            guard !matches.isEmpty else { throw StatementRepositoryError.nothingConfirmed }
            var paid = 0
            for match in matches {
                if var invoice = try Invoice.fetchOne(db, key: match.invoiceID), invoice.companyID == companyID,
                   let change = invoice.forceStatus(.paid, note: "Zatwierdzony wyciąg \(statement.fileName)", at: now, device: device) {
                    try invoice.update(db)
                    try InvoiceStatusLogEntry(invoiceID: invoice.id, change: change, device: device).insert(db)
                    paid += 1
                }
                try db.execute(sql: "UPDATE bankTransaction SET isMatched = 1 WHERE id = ?", arguments: [match.transactionID])
            }
            statement.status = .confirmed
            statement.confirmedAt = now
            try statement.update(db)
            return paid
        }
    }

    public func delete(_ statementID: UUID) throws {
        _ = try db.writer.write { try BankStatement.filter(Column("companyId") == companyID).filter(key: statementID).deleteAll($0) }
    }
}
