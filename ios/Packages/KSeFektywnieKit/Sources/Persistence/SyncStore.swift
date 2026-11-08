import Foundation
import GRDB
import Domain

public enum SyncStatus: String, Sendable, Codable {
    case running, success, error, cancelled
}

public struct SyncLogEntry: Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "ksefSyncLog"
    public var id: UUID
    public var companyID: UUID
    public var startedAt: Date
    public var finishedAt: Date?
    public var status: SyncStatus
    public var invoicesFetched: Int
    public var invoicesNew: Int
    public var errorMessage: String
    public var currentStage: String

    public init(id: UUID = UUID(), companyID: UUID, startedAt: Date, finishedAt: Date? = nil, status: SyncStatus = .running,
                invoicesFetched: Int = 0, invoicesNew: Int = 0, errorMessage: String = "", currentStage: String = "") {
        self.id = id
        self.companyID = companyID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.invoicesFetched = invoicesFetched
        self.invoicesNew = invoicesNew
        self.errorMessage = errorMessage
        self.currentStage = currentStage
    }

    public init(row: Row) throws {
        self.init(id: row["id"], companyID: row["companyId"], startedAt: row["startedAt"], finishedAt: row["finishedAt"],
                  status: SyncStatus(rawValue: row["status"]) ?? .error, invoicesFetched: row["invoicesFetched"],
                  invoicesNew: row["invoicesNew"], errorMessage: row["errorMessage"], currentStage: row["currentStage"])
    }

    public func encode(to c: inout PersistenceContainer) throws {
        c["id"] = id
        c["companyId"] = companyID
        c["startedAt"] = startedAt
        c["finishedAt"] = finishedAt
        c["status"] = status.rawValue
        c["invoicesFetched"] = invoicesFetched
        c["invoicesNew"] = invoicesNew
        c["errorMessage"] = errorMessage
        c["currentStage"] = currentStage
    }
}

/// Wpis kolejki pobierania XML.
public struct QueuedXML: Hashable, Sendable {
    public enum Kind: String, Sendable {
        case purchase, sale
    }

    public var ksefNumber: String
    public var kind: Kind

    public init(ksefNumber: String, kind: Kind) {
        self.ksefNumber = ksefNumber
        self.kind = kind
    }
}

/// Kolejka pobierania XML i logi synchronizacji.
public struct SyncStore: Sendable {
    let db: AppDatabase
    public let companyID: UUID

    public init(db: AppDatabase, companyID: UUID) {
        self.db = db
        self.companyID = companyID
    }

    public func save(_ entry: SyncLogEntry) throws {
        try db.writer.write { try entry.save($0) }
    }

    public func logs(limit: Int = 50) throws -> [SyncLogEntry] {
        try db.reader.read {
            try SyncLogEntry.filter(Column("companyId") == companyID).order(Column("startedAt").desc).limit(limit).fetchAll($0)
        }
    }

    /// Dodaje do kolejki faktury bez treści XML (pomija już zakolejkowane).
    public func enqueueMissingXML(now: Date) throws {
        try db.writer.write { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO ksefXmlQueue (companyId, ksefNumber, enqueuedAt, attempts)
                SELECT companyId, ksefReferenceNumber, ?, 0 FROM invoice WHERE companyId = ? AND rawXml = ''
                """, arguments: [now, companyID])
        }
    }

    /// Faktury sprzedażowe do pobrania (treść XML jest potrzebna, żeby odtworzyć pozycje).
    public func enqueueSales(_ ksefNumbers: [String], now: Date) throws {
        guard !ksefNumbers.isEmpty else { return }
        try db.writer.write { db in
            for ksefNumber in ksefNumbers {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO ksefXmlQueue (companyId, ksefNumber, enqueuedAt, attempts, kind)
                    VALUES (?, ?, ?, 0, ?)
                    """, arguments: [companyID, ksefNumber, now, QueuedXML.Kind.sale.rawValue])
            }
        }
    }

    /// Najpierw faktury zakupowe (płatności), potem sprzedażowe — duży import historii
    /// sprzedaży nie opóźnia pobierania nowych faktur kosztowych.
    public func pendingXML(now: Date, limit: Int) throws -> [QueuedXML] {
        try db.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT ksefNumber, kind FROM ksefXmlQueue
                WHERE companyId = ? AND (notBefore IS NULL OR notBefore <= ?)
                ORDER BY kind = 'sale', enqueuedAt, ksefNumber LIMIT ?
                """, arguments: [companyID, now, limit]).map {
                QueuedXML(ksefNumber: $0["ksefNumber"], kind: QueuedXML.Kind(rawValue: $0["kind"]) ?? .purchase)
            }
        }
    }

    public func pendingXMLCount(kind: QueuedXML.Kind? = nil) throws -> Int {
        try db.reader.read {
            if let kind {
                return try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM ksefXmlQueue WHERE companyId = ? AND kind = ?",
                                        arguments: [companyID, kind.rawValue]) ?? 0
            }
            return try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM ksefXmlQueue WHERE companyId = ?", arguments: [companyID]) ?? 0
        }
    }

    /// Kursor synchronizacji faktur sprzedażowych (osobny od zakupów).
    public func lastSalesSync() throws -> Date? {
        try db.reader.read {
            try Date.fetchOne($0, sql: "SELECT lastSyncAt FROM ksefSalesSync WHERE companyId = ?", arguments: [companyID])
        }
    }

    public func markSalesSynced(at date: Date) throws {
        try db.writer.write {
            try $0.execute(sql: """
                INSERT INTO ksefSalesSync (companyId, lastSyncAt) VALUES (?, ?)
                ON CONFLICT(companyId) DO UPDATE SET lastSyncAt = excluded.lastSyncAt
                """, arguments: [companyID, date])
        }
    }

    public func dequeue(_ ksefNumber: String) throws {
        try db.writer.write {
            try $0.execute(sql: "DELETE FROM ksefXmlQueue WHERE companyId = ? AND ksefNumber = ?", arguments: [companyID, ksefNumber])
        }
    }

    /// Po 429 cała kolejka czeka do `until`.
    public func postponeQueue(until: Date) throws {
        try db.writer.write {
            try $0.execute(sql: "UPDATE ksefXmlQueue SET notBefore = ?, attempts = attempts + 1 WHERE companyId = ?",
                           arguments: [until, companyID])
        }
    }

    public func nextQueueAttempt() throws -> Date? {
        try db.reader.read {
            try Date.fetchOne($0, sql: "SELECT MIN(notBefore) FROM ksefXmlQueue WHERE companyId = ?", arguments: [companyID])
        }
    }

    public func markSynced(at date: Date) throws {
        try db.writer.write {
            try $0.execute(sql: "UPDATE company SET lastSyncAt = ? WHERE id = ?", arguments: [date, companyID])
        }
    }
}
