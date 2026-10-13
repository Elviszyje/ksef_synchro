import Foundation
import GRDB
import Domain

/// Powiązania rekordów z przypomnieniami w aplikacji Przypomnienia.
public struct ReminderLinkRepository: Sendable {
    let db: AppDatabase
    public let companyID: UUID

    public init(db: AppDatabase, companyID: UUID) {
        self.db = db
        self.companyID = companyID
    }

    public func identifier(for target: ReminderTarget) throws -> String? {
        try db.reader.read {
            try String.fetchOne($0, sql: "SELECT reminderIdentifier FROM reminderLink WHERE recordType = ? AND recordId = ?",
                                arguments: [target.recordType, target.recordID])
        }
    }

    public func link(_ target: ReminderTarget, identifier: String, now: Date = Date()) throws {
        try db.writer.write {
            try $0.execute(sql: """
                INSERT INTO reminderLink (companyId, recordType, recordId, reminderIdentifier, createdAt) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(recordType, recordId) DO UPDATE SET reminderIdentifier = excluded.reminderIdentifier
                """, arguments: [companyID, target.recordType, target.recordID, identifier, now])
        }
    }

    public func unlink(_ target: ReminderTarget) throws {
        try db.writer.write {
            try $0.execute(sql: "DELETE FROM reminderLink WHERE recordType = ? AND recordId = ?",
                           arguments: [target.recordType, target.recordID])
        }
    }

    /// Przypomnienia, które można odhaczyć: faktura opłacona albo paczka, w której
    /// wszystkie faktury są opłacone. Usunięte rekordy też (przypomnienie traci sens).
    public func finished() throws -> [(target: ReminderTarget, identifier: String)] {
        try db.reader.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT l.recordType, l.recordId, l.reminderIdentifier FROM reminderLink l
                WHERE l.companyId = ? AND (
                  (l.recordType = 'invoice' AND NOT EXISTS (
                      SELECT 1 FROM invoice i WHERE i.id = l.recordId AND i.status != 'oplacona'))
                  OR
                  (l.recordType = 'paymentFile' AND NOT EXISTS (
                      SELECT 1 FROM paymentFileItem p JOIN invoice i ON i.id = p.invoiceId
                      WHERE p.paymentFileId = l.recordId AND i.status != 'oplacona'))
                )
                """, arguments: [companyID])
            return rows.compactMap { row in
                guard let target = ReminderTarget(recordType: row["recordType"], recordID: row["recordId"]) else { return nil }
                return (target, row["reminderIdentifier"])
            }
        }
    }
}
