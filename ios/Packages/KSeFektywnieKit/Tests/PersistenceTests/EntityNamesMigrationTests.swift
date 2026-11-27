import Foundation
import Testing
import GRDB
import Domain
@testable import Persistence

@Suite("Migracja v7: encje w zapisanych nazwach")
struct EntityNamesMigrationTests {
    @Test("Zapisane nazwy z encjami są dekodowane, a updatedAt rośnie")
    func migratesStoredNames() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v6-sales-import")
        let company = Company(nip: "1111111111", name: "F")
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        let bad = Invoice(companyID: company.id, ksefReferenceNumber: "R1", invoiceNumber: "1", sellerName: "Grupa K&amp;K", issueDate: LocalDate(old),
                          updatedAt: old)
        let good = Invoice(companyID: company.id, ksefReferenceNumber: "R2", invoiceNumber: "2", sellerName: "Kowalski & Syn", issueDate: LocalDate(old),
                           updatedAt: old)
        try queue.write { db in
            try company.insert(db)
            try bad.insert(db)
            try good.insert(db)
        }
        try AppDatabase.migrator.migrate(queue)
        let rows = try queue.read { try Row.fetchAll($0, sql: "SELECT sellerName, updatedAt FROM invoice ORDER BY invoiceNumber") }
        #expect(rows.map { $0["sellerName"] as String } == ["Grupa K&K", "Kowalski & Syn"])
        #expect((rows[0]["updatedAt"] as Date) > old)
        #expect((rows[1]["updatedAt"] as Date) == old)
    }
}

@Suite("Migracja v8: ponowne pobranie metadanych dla dat wystawienia")
struct IssueDateResyncMigrationTests {
    @Test("Kursor synchronizacji cofa się przed najstarszą fakturę bez XML")
    func rewindsCursor() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v7-decode-entity-names")
        let now = Date()
        let synced = now.addingTimeInterval(-2 * 24 * 3600)
        var company = Company(nip: "1111111111", name: "F")
        company.lastSyncAt = now
        var other = Company(nip: "2222222222", name: "G")
        other.lastSyncAt = now
        let metadataOnly = Invoice(companyID: company.id, ksefReferenceNumber: "R1", invoiceNumber: "1",
                                   issueDate: LocalDate(now), syncedAt: synced)
        let withXML = Invoice(companyID: other.id, ksefReferenceNumber: "R2", invoiceNumber: "2",
                              issueDate: LocalDate(now), rawXML: "<Faktura/>", syncedAt: synced)
        try queue.write { db in
            try company.insert(db); try other.insert(db)
            try metadataOnly.insert(db); try withXML.insert(db)
        }
        try AppDatabase.migrator.migrate(queue)
        let cursors = try queue.read { db in
            try Dictionary(uniqueKeysWithValues: Row.fetchAll(db, sql: "SELECT nip, lastSyncAt FROM company").map {
                ($0["nip"] as String, $0["lastSyncAt"] as Date)
            })
        }
        #expect(abs(cursors["1111111111"]!.timeIntervalSince(synced.addingTimeInterval(-31 * 24 * 3600))) < 1)
        #expect(abs(cursors["2222222222"]!.timeIntervalSince(now)) < 1)
    }
}
