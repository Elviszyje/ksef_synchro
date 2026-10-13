import Foundation
import GRDB
import Domain

/// Baza aplikacji: jedyne źródło prawdy dla UI. Lustro w iCloud Drive jest
/// zapisywane na podstawie zmian w tej bazie (faza iCloud).
public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    public var reader: any DatabaseReader { writer }

    /// Baza w pliku. Katalog powinien mieć ochronę `NSFileProtectionComplete`
    /// (ustawia ją aplikacja przy tworzeniu katalogu).
    public static func open(at url: URL) throws -> AppDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        #if DEBUG
        config.publicStatementArguments = true
        #endif
        return try AppDatabase(DatabasePool(path: url.path, configuration: config))
    }

    public static func inMemory() throws -> AppDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        return try AppDatabase(DatabaseQueue(configuration: config))
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif
        migrator.registerMigration("v1", migrate: Schema.v1)
        migrator.registerMigration("v2-sales-catalog", migrate: Schema.v2)
        migrator.registerMigration("v3-reminders", migrate: Schema.v3)
        return migrator
    }
}
