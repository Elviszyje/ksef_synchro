import Foundation
import Observation
import GRDB
import Domain
import Persistence
import AppServices

/// Lustro danych w iCloud Drive (albo w katalogu aplikacji, gdy iCloud jest wyłączony).
/// Zapis uruchamia się kilka sekund po każdej zmianie w bazie.
@Observable
final class CloudSync {
    enum Location: Equatable {
        case unknown
        case iCloud(URL)
        case local(URL)

        var url: URL? {
            switch self {
            case .unknown: nil
            case .iCloud(let u), .local(let u): u
            }
        }
    }

    nonisolated static let containerID = "iCloud.pl.ksefektywnie.app"

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "cloudMirrorEnabled")
            if isEnabled { schedule(delay: .zero) } else { stop() }
        }
    }
    private(set) var location: Location = .unknown
    private(set) var lastSync: Date?
    private(set) var lastReport: MirrorReport?
    private(set) var lastError: String?
    private(set) var isSyncing = false
    /// Inne urządzenie zapisało katalog później niż to — dwa telefony nadpisują wzajemnie pliki.
    private(set) var otherDeviceWarning: String?

    private let database: AppDatabase
    private let deviceID: String
    private var observation: AnyDatabaseCancellable?
    private var pending: Task<Void, Never>?

    init(database: AppDatabase, deviceID: String) {
        self.database = database
        self.deviceID = deviceID
        isEnabled = UserDefaults.standard.object(forKey: "cloudMirrorEnabled") as? Bool ?? true
    }

    /// Ustala katalog (iCloud lub lokalny) i zaczyna obserwować bazę.
    func start() async {
        location = await Self.resolveLocation()
        guard isEnabled else { return }
        let tables = ["company", "companyBankAccount", "invoice", "invoiceStatusLog", "outgoingInvoice", "outgoingInvoiceItem",
                      "buyer", "catalogItem", "paymentFile", "paymentFileItem", "bankStatement", "bankTransaction", "transactionMatch"]
        let region = DatabaseRegionObservation(tracking: tables.map { Table($0) })
        observation = region.start(in: database.writer, onError: { _ in }, onChange: { [weak self] _ in
            Task { @MainActor in self?.schedule(delay: .seconds(3)) }
        })
        schedule(delay: .zero)
    }

    func stop() {
        observation?.cancel()
        observation = nil
        pending?.cancel()
    }

    static func resolveLocation() async -> Location {
        await Task.detached {
            if let container = FileManager.default.url(forUbiquityContainerIdentifier: containerID) {
                return Location.iCloud(container.appending(path: "Documents", directoryHint: .isDirectory))
            }
            return Location.local(URL.documentsDirectory.appending(path: "KS-eFektywnie", directoryHint: .isDirectory))
        }.value
    }

    func schedule(delay: Duration) {
        guard isEnabled, location.url != nil else { return }
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await run { mirror in try mirror.sync() }
        }
    }

    func rewriteAll() async {
        await run { mirror in try mirror.rewriteAll() }
    }

    private func run(_ operation: @escaping @Sendable (CloudMirror) throws -> MirrorReport) async {
        guard let root = location.url, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        let mirror = CloudMirror(db: database, fileSystem: CoordinatedFileSystem(root: root), deviceID: deviceID)
        let ownDevice = deviceID
        let result = await Task.detached { () -> (Result<MirrorReport, Error>, (String, Date)?) in
            let fs = CoordinatedFileSystem(root: root)
            let before = CloudMirror.manifest(in: fs).map { ($0.deviceID, $0.writtenAt) }
            return (Result { try operation(mirror) }, before)
        }.value
        if let (device, writtenAt) = result.1, device != ownDevice, writtenAt > (lastSync ?? .distantPast) {
            otherDeviceWarning = String(localized: "Katalog był ostatnio zapisywany przez inne urządzenie (\(writtenAt.formatted(date: .abbreviated, time: .shortened))). Używaj aplikacji na jednym urządzeniu, aby pliki się nie nadpisywały.")
        }
        switch result.0 {
        case .success(let report):
            lastReport = report
            lastSync = Date()
            lastError = nil
        case .failure(let error):
            lastError = error.userMessage
        }
    }

    /// Kopia znaleziona w katalogu przy pierwszym uruchomieniu (do przywrócenia).
    static func availableBackup() async -> (location: Location, companies: [String], writtenAt: Date)? {
        let location = await resolveLocation()
        guard let root = location.url else { return nil }
        return await Task.detached {
            let fs = CoordinatedFileSystem(root: root)
            if case .iCloud = location { try? await fs.downloadAll(timeout: 15) }
            guard let manifest = CloudMirror.manifest(in: fs), !manifest.companies.isEmpty else { return nil }
            return (location, manifest.companies, manifest.writtenAt)
        }.value
    }

    /// Pobiera pliki z iCloud i odtwarza dane w bazie.
    static func restore(from location: Location, into database: AppDatabase,
                        progress: @escaping @Sendable (Int, Int) -> Void) async throws -> [Company] {
        guard let root = location.url else { return [] }
        return try await Task.detached {
            let fs = CoordinatedFileSystem(root: root)
            if case .iCloud = location { try await fs.downloadAll(timeout: 300, progress: progress) }
            return try CloudMirror.restore(from: fs, into: database)
        }.value
    }
}
