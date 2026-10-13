import Foundation
import Observation
import Domain
import Persistence
import KSeFClient
import AppServices

/// Stan aplikacji: baza, aktywna firma, identyfikator urządzenia.
/// `activeCompany` to jedno źródło prawdy — przełącznik firm w v2 zmienia tylko tę wartość.
@Observable
final class AppModel {
    let database: AppDatabase
    let deviceID: String
    private(set) var company: Company?
    private(set) var bankAccounts: [CompanyBankAccount] = []
    private(set) var startupError: String?

    let cloud: CloudSync
    let reminders = RemindersService()
    /// Rekord do otwarcia z linku w aplikacji Przypomnienia.
    var openTarget: ReminderTarget?

    var syncInProgress = false
    var syncMessage: String?

    init(database: AppDatabase, deviceID: String) {
        self.database = database
        self.deviceID = deviceID
        self.cloud = CloudSync(database: database, deviceID: deviceID)
        reload()
    }

    static func live() -> AppModel {
        let defaults = UserDefaults.standard
        let deviceID = defaults.string(forKey: "deviceID") ?? {
            let id = UUID().uuidString
            defaults.set(id, forKey: "deviceID")
            return id
        }()
        #if DEBUG
        // Zrzuty ekranu i testy UI: świeża baza w pamięci z danymi demo, bez lustra iCloud.
        if ProcessInfo.processInfo.arguments.contains("-demo") || ProcessInfo.processInfo.arguments.contains("-demo-cloud") {
            let model = AppModel(database: try! AppDatabase.inMemory(), deviceID: deviceID)
            model.cloud.isEnabled = ProcessInfo.processInfo.arguments.contains("-demo-cloud")
            try? model.startDemo()
            if ProcessInfo.processInfo.arguments.contains("-print-demo-links"),
               let first = try? model.invoices?.fetch().first {
                print("DEMO-LINK \(ReminderTarget.invoice(first.id).deepLink.absoluteString) \(first.invoiceNumber)")
            }
            return model
        }
        #endif
        do {
            return AppModel(database: try AppDatabase.open(at: try databaseURL()), deviceID: deviceID)
        } catch {
            let model = AppModel(database: try! AppDatabase.inMemory(), deviceID: deviceID)
            model.startupError = error.userMessage
            return model
        }
    }

    /// Baza w Application Support z ochroną plików "complete": nieczytelna, gdy telefon jest zablokowany.
    static func databaseURL() throws -> URL {
        let dir = URL.applicationSupportDirectory.appending(path: "Database", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        return dir.appending(path: "ksefektywnie.sqlite")
    }

    func reload() {
        do {
            company = try database.reader.read { try Company.order(Column.createdAt).fetchOne($0) }
            bankAccounts = try company.map { c in
                try database.reader.read { try CompanyBankAccount.filter(Column.companyId == c.id).fetchAll($0) }
            } ?? []
        } catch {
            startupError = error.userMessage
        }
    }

    var invoices: InvoiceRepository? {
        company.map { InvoiceRepository(db: database, companyID: $0.id, device: deviceID) }
    }

    var sales: SalesRepository? {
        company.map { SalesRepository(db: database, companyID: $0.id, device: deviceID) }
    }

    var payments: PaymentFileRepository? {
        company.map { PaymentFileRepository(db: database, companyID: $0.id, device: deviceID) }
    }

    var paymentPayer: PaymentPayer? {
        company.map { PaymentPayer(debitAccount: defaultBankAccount?.accountNumber ?? "", name: $0.name, address: $0.address) }
    }

    var statements: StatementRepository? {
        company.map { StatementRepository(db: database, companyID: $0.id, device: deviceID) }
    }

    /// Banki rachunków firmy — ich parsery CSV są sprawdzane najpierw.
    var preferredBankKeys: [String] { bankAccounts.map(\.bankKey) }

    var reminderLinks: ReminderLinkRepository? {
        company.map { ReminderLinkRepository(db: database, companyID: $0.id) }
    }

    var catalog: CatalogRepository? {
        company.map { CatalogRepository(db: database, companyID: $0.id, device: deviceID) }
    }

    var defaultBankAccount: CompanyBankAccount? {
        bankAccounts.first(where: \.isDefault) ?? bankAccounts.first
    }

    /// Nowy szkic faktury sprzedażowej z kolejnym numerem i domyślnym terminem płatności.
    func newSalesDraft(today: LocalDate = .today()) -> OutgoingInvoice? {
        guard let company, let sales else { return nil }
        let number = (try? sales.nextNumber(pattern: company.invoiceNumberPattern, year: today.year,
                                            environment: company.ksefEnvironment)) ?? ""
        let due = LocalDate(Calendar.current.date(byAdding: .day, value: company.defaultPaymentDays, to: today.date())!)
        return OutgoingInvoice(companyID: company.id, invoiceNumber: number, issueDate: today, paymentDueDate: due,
                               bankAccountNumber: defaultBankAccount?.accountNumber ?? "",
                               environment: company.ksefEnvironment, updatedByDevice: deviceID)
    }

    var fa3Seller: FA3Seller? {
        company.map { FA3Seller(nip: $0.nip, name: $0.name, address: $0.address) }
    }

    var syncStore: SyncStore? {
        company.map { SyncStore(db: database, companyID: $0.id) }
    }

    // MARK: - Firma

    func createCompany(nip: String, name: String, address: String, environment: KSeFEnvironment) throws {
        let company = Company(nip: nip, name: name, address: address, ksefEnvironment: environment, updatedByDevice: deviceID)
        try database.writer.write { try company.insert($0) }
        reload()
    }

    func updateCompany(_ update: (inout Company) -> Void) throws {
        guard var company else { return }
        update(&company)
        company.updatedAt = Date()
        company.updatedByDevice = deviceID
        try database.writer.write { [company] in try company.update($0) }
        reload()
    }

    func addBankAccount(_ number: String, label: String) throws {
        guard let company else { return }
        let account = CompanyBankAccount(companyID: company.id, accountNumber: number, label: label, isDefault: bankAccounts.isEmpty)
        try database.writer.write { try account.insert($0) }
        reload()
    }

    func deleteBankAccount(_ account: CompanyBankAccount) throws {
        _ = try database.writer.write { try account.delete($0) }
        reload()
    }

    // MARK: - KSeF

    var ksefToken: String? {
        get { company.flatMap { Keychain.ksefToken(for: $0.id) } }
        set {
            guard let company else { return }
            Keychain.setKSeFToken(newValue, for: company.id)
        }
    }

    func makeClient() throws -> KSeFClient {
        guard let company, let token = ksefToken, !token.isEmpty else { throw KSeFError.missingToken }
        return KSeFClient(environment: company.ksefEnvironment, nip: company.nip, apiToken: token)
    }

    func sendService() throws -> KSeFSendService {
        guard let company else { throw KSeFError.missingToken }
        return KSeFSendService(company: company, sender: try makeClient(), db: database, device: deviceID)
    }

    /// Odświeża faktury sprzedażowe czekające na wynik z KSeF lub UPO.
    func refreshSalesSubmissions() async {
        guard ksefToken != nil, let service = try? sendService() else { return }
        await service.refreshPending()
    }

    func testConnection() async throws {
        _ = try await makeClient().authenticate()
    }

    func sync() async {
        guard let company, !syncInProgress else { return }
        syncInProgress = true
        defer { syncInProgress = false }
        do {
            let service = KSeFSyncService(company: company, source: try makeClient(), db: database, device: deviceID)
            let result = try await service.run()
            syncMessage = SyncSummary.text(result)
            reload()
        } catch {
            syncMessage = error.userMessage
        }
    }

    // MARK: - iCloud

    /// Przywraca dane z kopii w iCloud Drive (pierwsze uruchomienie na nowym telefonie).
    func restoreFromCloud(_ location: CloudSync.Location, progress: @escaping @Sendable (Int, Int) -> Void) async throws {
        _ = try await CloudSync.restore(from: location, into: database, progress: progress)
        reload()
        await cloud.start()
    }

    // MARK: - Demo

    /// Dane przykładowe bez KSeF (także dla recenzentów App Store).
    func startDemo() throws {
        try DemoData.seed(db: database, device: deviceID)
        reload()
    }

    var isDemo: Bool { company?.nip == DemoData.companyNIP }

    // MARK: - Dane

    /// Usuwa wszystkie dane firmy z telefonu (baza i token).
    func deleteAllData() throws {
        guard let company else { return }
        Keychain.setKSeFToken(nil, for: company.id)
        _ = try database.writer.write { try company.delete($0) }
        reload()
    }
}

import GRDB

extension Column {
    static let createdAt = Column("createdAt")
    static let companyId = Column("companyId")
}

enum SyncSummary {
    static func text(_ r: KSeFSyncService.Result) -> String {
        var parts = [String(localized: "Pobrano \(r.fetched) faktur, nowych: \(r.new).")]
        if r.xmlPending > 0 {
            if let resume = r.xmlResumesAt {
                parts.append(String(localized: "Treść \(r.xmlPending) faktur zostanie pobrana po \(resume.formatted(date: .omitted, time: .shortened)) (limit KSeF)."))
            } else {
                parts.append(String(localized: "Treść \(r.xmlPending) faktur zostanie pobrana przy kolejnej synchronizacji."))
            }
        }
        return parts.joined(separator: " ")
    }
}
