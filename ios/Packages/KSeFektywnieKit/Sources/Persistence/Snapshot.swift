import Foundation
import GRDB
import Domain

/// Pozycja pliku przelewów (faktura w paczce).
public struct PaymentFileLine: Hashable, Sendable {
    public var invoiceID: UUID
    public var amount: Decimal
    public var lineNumber: Int

    public init(invoiceID: UUID, amount: Decimal, lineNumber: Int) {
        self.invoiceID = invoiceID
        self.amount = amount
        self.lineNumber = lineNumber
    }
}

/// Komplet danych jednej firmy — eksport do katalogu iCloud i odtworzenie na nowym urządzeniu.
public struct CompanySnapshot: Sendable {
    public var company: Company
    public var bankAccounts: [CompanyBankAccount]
    public var invoices: [Invoice]
    public var statusLogs: [InvoiceStatusLogEntry]
    public var sales: [OutgoingInvoice]
    public var buyers: [Buyer]
    public var catalog: [CatalogItem]
    public var paymentFiles: [(file: PaymentFile, lines: [PaymentFileLine])]
    public var statements: [(statement: BankStatement, transactions: [BankTransaction], matches: [TransactionMatch])]

    public init(company: Company, bankAccounts: [CompanyBankAccount] = [], invoices: [Invoice] = [],
                statusLogs: [InvoiceStatusLogEntry] = [], sales: [OutgoingInvoice] = [], buyers: [Buyer] = [],
                catalog: [CatalogItem] = [], paymentFiles: [(file: PaymentFile, lines: [PaymentFileLine])] = [],
                statements: [(statement: BankStatement, transactions: [BankTransaction], matches: [TransactionMatch])] = []) {
        self.company = company
        self.bankAccounts = bankAccounts
        self.invoices = invoices
        self.statusLogs = statusLogs
        self.sales = sales
        self.buyers = buyers
        self.catalog = catalog
        self.paymentFiles = paymentFiles
        self.statements = statements
    }
}

extension AppDatabase {
    public func companies() throws -> [Company] {
        try reader.read { try Company.order(Column("createdAt")).fetchAll($0) }
    }

    public func snapshot(companyID: UUID) throws -> CompanySnapshot? {
        try reader.read { db in
            guard let company = try Company.fetchOne(db, key: companyID) else { return nil }
            let byCompany = Column("companyId") == companyID
            let invoices = try Invoice.filter(byCompany).order(Column("issueDate"), Column("ksefReferenceNumber")).fetchAll(db)
            let logs = try InvoiceStatusLogEntry.fetchAll(db, sql: """
                SELECT l.* FROM invoiceStatusLog l JOIN invoice i ON i.id = l.invoiceId WHERE i.companyId = ? ORDER BY l.changedAt, l.id
                """, arguments: [companyID])
            let sales = try OutgoingInvoiceRecord.filter(byCompany).order(Column("invoiceNumber")).fetchAll(db)
                .map { try salesWithItems($0.invoice, db) }
            let files = try PaymentFile.filter(byCompany).order(Column("createdAt")).fetchAll(db).map { file in
                let lines = try Row.fetchAll(db, sql: "SELECT invoiceId, amount, lineNumber FROM paymentFileItem WHERE paymentFileId = ? ORDER BY lineNumber",
                                             arguments: [file.id]).map {
                    PaymentFileLine(invoiceID: $0["invoiceId"], amount: Money.decimal($0["amount"] as Int64), lineNumber: $0["lineNumber"])
                }
                return (file: file, lines: lines)
            }
            let statements = try BankStatement.filter(byCompany).order(Column("uploadedAt")).fetchAll(db).map { s in
                let txs = try BankTransaction.filter(Column("bankStatementId") == s.id)
                    .order(Column("transactionDate"), Column("id")).fetchAll(db)
                let matches = try TransactionMatch.fetchAll(db, sql: """
                    SELECT m.* FROM transactionMatch m JOIN bankTransaction t ON t.id = m.bankTransactionId WHERE t.bankStatementId = ? ORDER BY m.id
                    """, arguments: [s.id])
                return (statement: s, transactions: txs, matches: matches)
            }
            return CompanySnapshot(
                company: company,
                bankAccounts: try CompanyBankAccount.filter(byCompany).order(Column("accountNumber")).fetchAll(db),
                invoices: invoices, statusLogs: logs, sales: sales,
                buyers: try Buyer.filter(byCompany).order(Column("nip")).fetchAll(db),
                catalog: try CatalogItem.filter(byCompany).order(Column("name"), Column("unit")).fetchAll(db),
                paymentFiles: files, statements: statements)
        }
    }

    /// Odtwarza firmę z kopii (z oryginalnymi identyfikatorami). Wymaga, by firmy jeszcze nie było.
    public func restore(_ snapshot: CompanySnapshot) throws {
        try writer.write { db in
            try snapshot.company.insert(db)
            for account in snapshot.bankAccounts { try account.insert(db) }
            for buyer in snapshot.buyers { try buyer.insert(db) }
            for item in snapshot.catalog { try item.insert(db) }
            for invoice in snapshot.invoices { try invoice.insert(db) }
            for log in snapshot.statusLogs { try log.insert(db) }
            for sale in snapshot.sales {
                try OutgoingInvoiceRecord(sale).insert(db)
                try insertSalesItems(sale, db)
            }
            for (file, lines) in snapshot.paymentFiles {
                try file.insert(db)
                for line in lines {
                    try db.execute(sql: "INSERT INTO paymentFileItem (paymentFileId, invoiceId, amount, lineNumber) VALUES (?, ?, ?, ?)",
                                   arguments: [file.id, line.invoiceID, Money.db(line.amount), line.lineNumber])
                }
            }
            for (statement, transactions, matches) in snapshot.statements {
                try statement.insert(db)
                for tx in transactions { try tx.insert(db) }
                for match in matches { try match.insert(db) }
            }
        }
    }
}

func salesWithItems(_ invoice: OutgoingInvoice, _ db: Database) throws -> OutgoingInvoice {
    var result = invoice
    result.items = try Row.fetchAll(db, sql: "SELECT * FROM outgoingInvoiceItem WHERE outgoingInvoiceId = ? ORDER BY lp",
                                    arguments: [invoice.id]).map { row in
        OutgoingInvoiceItem(name: row["name"], unit: row["unit"],
                            quantity: DecimalText.parse(row["quantity"]) ?? 0,
                            unitPriceNet: Money.decimal(row["unitPriceNet"] as Int64),
                            vatRate: VATRate(rawValue: row["vatRate"]) ?? .standard)
    }
    return result
}

func insertSalesItems(_ invoice: OutgoingInvoice, _ db: Database) throws {
    try db.execute(sql: "DELETE FROM outgoingInvoiceItem WHERE outgoingInvoiceId = ?", arguments: [invoice.id])
    for (index, item) in invoice.items.enumerated() {
        try db.execute(sql: """
            INSERT INTO outgoingInvoiceItem (outgoingInvoiceId, lp, name, unit, quantity, unitPriceNet, vatRate, amountNet, amountVat, amountGross)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [invoice.id, index + 1, item.name, item.unit, DecimalText.string(item.quantity),
                             Money.db(item.unitPriceNet), item.vatRate.rawValue,
                             Money.db(item.amountNet), Money.db(item.amountVAT), Money.db(item.amountGross)])
    }
}

/// Stan lustra iCloud (tabela `cloudMirrorState`).
public struct MirrorStateEntry: Hashable, Sendable {
    public var path: String
    public var contentHash: String
    public var writtenAt: Date

    public init(path: String, contentHash: String, writtenAt: Date) {
        self.path = path
        self.contentHash = contentHash
        self.writtenAt = writtenAt
    }
}

extension AppDatabase {
    public func mirrorState() throws -> [String: MirrorStateEntry] {
        try reader.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT path, contentHash, writtenAt FROM cloudMirrorState")
            return Dictionary(uniqueKeysWithValues: rows.map {
                ($0["path"], MirrorStateEntry(path: $0["path"], contentHash: $0["contentHash"], writtenAt: $0["writtenAt"]))
            })
        }
    }

    public func recordMirrorWrite(path: String, recordType: String, recordID: String, hash: String, at date: Date) throws {
        try writer.write {
            try $0.execute(sql: """
                INSERT INTO cloudMirrorState (path, recordType, recordId, recordUpdatedAt, contentHash, writtenAt)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(path) DO UPDATE SET contentHash = excluded.contentHash, writtenAt = excluded.writtenAt,
                  recordUpdatedAt = excluded.recordUpdatedAt
                """, arguments: [path, recordType, recordID, date, hash, date])
        }
    }

    public func removeMirrorState(paths: [String]) throws {
        guard !paths.isEmpty else { return }
        try writer.write { db in
            for path in paths { try db.execute(sql: "DELETE FROM cloudMirrorState WHERE path = ?", arguments: [path]) }
        }
    }

    public func clearMirrorState() throws {
        try writer.write { try $0.execute(sql: "DELETE FROM cloudMirrorState") }
    }
}
