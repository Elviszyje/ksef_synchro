import Foundation
import GRDB
import Domain

extension PaymentFile: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "paymentFile"

    public init(row: Row) throws {
        self.init(id: row["id"], companyID: row["companyId"],
                  format: PaymentFileFormat(rawValue: row["format"]) ?? .elixir, bankKey: row["bankKey"],
                  debitAccount: row["debitAccount"], fileName: row["fileName"], content: row["content"],
                  totalAmount: Money.decimal(row["totalAmount"] as Int64), invoiceCount: row["invoiceCount"],
                  createdAt: row["createdAt"])
    }

    public func encode(to c: inout PersistenceContainer) throws {
        c["id"] = id
        c["companyId"] = companyID
        c["format"] = format.rawValue
        c["bankKey"] = bankKey
        c["debitAccount"] = debitAccount
        c["fileName"] = fileName
        c["content"] = content
        c["totalAmount"] = Money.db(totalAmount)
        c["invoiceCount"] = invoiceCount
        c["createdAt"] = createdAt
    }
}

/// Generowanie i historia plików przelewów — port `apps/payments/views.py`.
public struct PaymentFileRepository: Sendable {
    let db: AppDatabase
    public let companyID: UUID
    public let device: String

    public init(db: AppDatabase, companyID: UUID, device: String) {
        self.db = db
        self.companyID = companyID
        self.device = device
    }

    /// Faktury gotowe do przelewu: zaakceptowane, z numerem rachunku.
    public func payableInvoices() throws -> [Invoice] {
        try db.reader.read {
            try Invoice.filter(Column("companyId") == companyID)
                .filter(Column("status") == InvoiceStatus.accepted.rawValue)
                .filter(Column("bankAccountNumber") != "")
                .order(Column("paymentDueDate").ascNullsLast, Column("issueDate").desc)
                .fetchAll($0)
        }
    }

    /// Tworzy plik dla rachunku obciążanego; format wynika z banku tego rachunku.
    /// Faktury przechodzą w `przekazano_do_oplacenia` w tej samej transakcji.
    public func generate(invoiceIDs: [UUID], debitAccount: CompanyBankAccount, payer: PaymentPayer,
                         date: LocalDate = .today(), now: Date = Date()) throws -> PaymentFile {
        guard !invoiceIDs.isEmpty else { throw PaymentFileError.noInvoices }
        return try db.writer.write { db in
            var invoices: [Invoice] = []
            for id in invoiceIDs {
                guard let invoice = try Invoice.filter(Column("companyId") == companyID).filter(key: id).fetchOne(db) else { continue }
                guard invoice.canBeSelectedForPayment else {
                    throw PaymentFileError.invoiceNotPayable(invoiceNumber: invoice.invoiceNumber)
                }
                invoices.append(invoice)
            }
            guard !invoices.isEmpty else { throw PaymentFileError.noInvoices }

            let bankKey = debitAccount.bankKey
            let format = PaymentFileFormat.forBank(bankKey)
            let fileName = PaymentFileFormat.fileName(bankKey: bankKey, date: date)
            let content = format.generator(payer: payer).generate(invoices, executionDate: date)
            let file = PaymentFile(companyID: companyID, format: format, bankKey: bankKey,
                                   debitAccount: debitAccount.accountNumber, fileName: fileName, content: content,
                                   totalAmount: invoices.reduce(0) { $0 + $1.amountGross },
                                   invoiceCount: invoices.count, createdAt: now)
            try file.insert(db)

            for (index, var invoice) in invoices.enumerated() {
                try db.execute(sql: """
                    INSERT INTO paymentFileItem (paymentFileId, invoiceId, amount, lineNumber) VALUES (?, ?, ?, ?)
                    """, arguments: [file.id, invoice.id, Money.db(invoice.amountGross), index + 1])
                if let change = invoice.forceStatus(.sentForPayment, note: "Automatycznie po wygenerowaniu pliku \(fileName)",
                                                    at: now, device: device) {
                    try invoice.update(db)
                    try InvoiceStatusLogEntry(invoiceID: invoice.id, change: change, device: device).insert(db)
                }
            }
            return file
        }
    }

    public func files() throws -> [PaymentFile] {
        try db.reader.read {
            try PaymentFile.filter(Column("companyId") == companyID).order(Column("createdAt").desc).fetchAll($0)
        }
    }

    public func invoices(in fileID: UUID) throws -> [Invoice] {
        try db.reader.read { db in
            try Invoice.fetchAll(db, sql: """
                SELECT invoice.* FROM invoice
                JOIN paymentFileItem ON paymentFileItem.invoiceId = invoice.id
                WHERE paymentFileItem.paymentFileId = ? ORDER BY paymentFileItem.lineNumber
                """, arguments: [fileID])
        }
    }

    /// Reset paczki: faktury wracają do `zaakceptowana`, plik jest usuwany.
    /// Niedozwolony, gdy którakolwiek faktura jest już opłacona.
    public func reset(_ fileID: UUID, now: Date = Date()) throws {
        let invoices = try invoices(in: fileID)
        try db.writer.write { db in
            guard let file = try PaymentFile.filter(Column("companyId") == companyID).filter(key: fileID).fetchOne(db) else { return }
            if invoices.contains(where: { $0.status == .paid }) { throw PaymentFileError.paidInvoiceInBatch }
            for var invoice in invoices where invoice.status == .sentForPayment {
                if let change = invoice.forceStatus(.accepted, note: "Cofnięto do zaakceptowana — reset paczki \(file.fileName)",
                                                    at: now, device: device) {
                    try invoice.update(db)
                    try InvoiceStatusLogEntry(invoiceID: invoice.id, change: change, device: device).insert(db)
                }
            }
            try file.delete(db)
        }
    }
}
