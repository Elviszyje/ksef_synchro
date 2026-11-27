import Foundation
import Observation
import Domain
import Persistence
import KSeFClient
import AppServices

/// Stan aplikacji: baza, firmy, aktywna firma, identyfikator urządzenia.
/// Zakładki pracują zawsze na jednej, aktywnej firmie (`company`). Przełącznik firm zmienia
/// tylko `activeCompanyID`; widok „Wszystkie firmy” na Pulpicie czyta dane ponad tym podziałem.
@Observable
final class AppModel {
    let database: AppDatabase
    let deviceID: String
    /// Wszystkie firmy w kolejności dodania (najwyżej `maxCompanies`).
    private(set) var companies: [Company] = []
    /// Aktywna firma — na niej pracują zakładki Faktury, Przelewy, Wyciągi i Ustawienia.
    private(set) var company: Company?
    private(set) var bankAccounts: [CompanyBankAccount] = []
    /// Limit firm: aplikacja jest dla przedsiębiorcy (np. dwie działalności w rodzinie), nie dla biura rachunkowego.
    static let maxCompanies = 3
    private static let activeCompanyKey = "activeCompanyID"
    private(set) var startupError: String?
    /// Nie udało się otworzyć bazy na dysku — model działa na pustej atrapie i nie wolno
    /// traktować go jak świeżej instalacji (ekran powitalny, lustro iCloud, synchronizacja).
    private(set) var databaseUnavailable = false

    let cloud: CloudSync
    let reminders = RemindersService()
    /// Rekord do otwarcia z linku w aplikacji Przypomnienia.
    var openTarget: ReminderTarget?
    /// Wyszukiwanie do ustawienia na liście faktur kosztowych (dostawca dotknięty na Pulpicie);
    /// lista je przejmuje i zeruje.
    var invoiceSearchRequest: String?

    var syncInProgress = false
    /// Wynik ostatniej synchronizacji — w Ustawieniach zostaje przy przycisku „Synchronizuj teraz”.
    var syncMessage: String?
    /// Ten sam komunikat nad listami faktur — znika po kilku sekundach.
    private(set) var syncBanner: String?
    private var syncBannerTask: Task<Void, Never>?

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
            // `-demo-second YES`: druga firma demo (przełącznik firm, widok „Wszystkie firmy”).
            if UserDefaults.standard.bool(forKey: "demo-second") {
                _ = try? DemoData.seedSecondCompany(db: model.database, device: deviceID)
                model.reload()
            }
            if ProcessInfo.processInfo.arguments.contains("-print-demo-links"),
               let first = try? model.invoices?.fetch().first {
                print("DEMO-LINK \(ReminderTarget.invoice(first.id).deepLink.absoluteString) \(first.invoiceNumber)")
            }
            return model
        }
        #endif
        Keychain.migrateAccessibility()
        do {
            return AppModel(database: try AppDatabase.open(at: try databaseURL()), deviceID: deviceID)
        } catch {
            // Baza nieczytelna (np. start w tle przed pierwszym odblokowaniem telefonu). Model z pustą
            // bazą w pamięci jest tylko atrapą: interfejs pokazuje błąd zamiast ekranu powitalnego,
            // a po powrocie na pierwszy plan aplikacja otwiera bazę ponownie.
            let model = AppModel(database: try! AppDatabase.inMemory(), deviceID: deviceID)
            model.startupError = error.userMessage
            model.databaseUnavailable = true
            return model
        }
    }

    /// Ochrona plików bazy: zaszyfrowane do pierwszego odblokowania telefonu po uruchomieniu.
    /// Pełna ochrona („complete”) odcinała bazę przy zablokowanym ekranie, czyli wtedy,
    /// gdy iOS uruchamia synchronizację w tle.
    static let databaseProtection = FileProtectionType.completeUntilFirstUserAuthentication

    static func databaseURL() throws -> URL {
        let fm = FileManager.default
        let dir = URL.applicationSupportDirectory.appending(path: "Database", directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                               attributes: [.protectionKey: databaseProtection])
        // Katalog i pliki utworzone przez starsze wersje mają jeszcze ochronę "complete".
        // Zmiana klasy udaje się tylko przy odblokowanym telefonie — ponawiana przy każdym starcie.
        let existing = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for url in [dir] + existing {
            try? fm.setAttributes([.protectionKey: databaseProtection], ofItemAtPath: url.path)
        }
        return dir.appending(path: "ksefektywnie.sqlite")
    }

    func reload() {
        do {
            companies = try database.reader.read { try Company.order(Column.createdAt).fetchAll($0) }
            let stored = UserDefaults.standard.string(forKey: Self.activeCompanyKey).flatMap(UUID.init(uuidString:))
            company = companies.first { $0.id == stored } ?? companies.first
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

    /// Powiązania przypomnień wszystkich firm — odhaczanie po opłaceniu nie zależy od aktywnej firmy.
    var allReminderLinks: [ReminderLinkRepository] {
        companies.map { ReminderLinkRepository(db: database, companyID: $0.id) }
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

    var canAddCompany: Bool { companies.count < Self.maxCompanies }

    /// Dodaje firmę i od razu ją aktywuje. Token KSeF (jeśli podany) trafia do pęku kluczy tej firmy.
    func createCompany(nip: String, name: String, address: String, environment: KSeFEnvironment, token: String? = nil) throws {
        guard canAddCompany else { throw CompanyError.limitReached(Self.maxCompanies) }
        guard !companies.contains(where: { $0.nip == nip }) else { throw CompanyError.duplicateNIP }
        let company = Company(nip: nip, name: name, address: address, ksefEnvironment: environment, updatedByDevice: deviceID)
        try database.writer.write { try company.insert($0) }
        if let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            Keychain.setKSeFToken(token, for: company.id)
            tokenRevision += 1
        }
        activate(company.id)
    }

    /// Przełącza aktywną firmę (zapamiętywane między uruchomieniami).
    func activate(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: Self.activeCompanyKey)
        if company?.id != id || !companies.contains(where: { $0.id == id }) { reload() }
    }

    /// Aktywuje firmę, do której należy rekord z linku (przypomnienie może dotyczyć innej firmy niż aktywna).
    func activateCompany(owning target: ReminderTarget) {
        let owner: UUID? = try? database.reader.read { db in
            switch target {
            case .invoice(let id): try Invoice.filter(key: id).fetchOne(db)?.companyID
            case .paymentFile(let id): try PaymentFile.filter(key: id).fetchOne(db)?.companyID
            }
        }
        if let owner, owner != company?.id { activate(owner) }
    }

    func hasToken(_ company: Company) -> Bool {
        _ = tokenRevision
        return Keychain.ksefToken(for: company.id) != nil
    }

    /// Usuwa jedną firmę z telefonu razem z jej danymi i tokenem.
    func deleteCompany(_ target: Company) throws {
        Keychain.setKSeFToken(nil, for: target.id)
        _ = try database.writer.write { try target.delete($0) }
        tokenRevision += 1
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

    /// Pęk kluczy nie jest obserwowalny. Licznik sprawia, że widoki czytające token odświeżają się
    /// po jego zapisie i po powrocie aplikacji na pierwszy plan — inaczej zostawał na ekranie stan
    /// z chwili ostatniego rysowania (np. „Nie skonfigurowano” narysowane przy zablokowanym telefonie).
    private var tokenRevision = 0

    var ksefToken: String? {
        get {
            _ = tokenRevision
            return company.flatMap { Keychain.ksefToken(for: $0.id) }
        }
        set {
            guard let company else { return }
            Keychain.setKSeFToken(newValue, for: company.id)
            tokenRevision += 1
        }
    }

    /// Wymusza ponowne odczytanie tokenu przez widoki (wywoływane po powrocie na pierwszy plan).
    func refreshTokenState() { tokenRevision += 1 }

    func makeClient() throws -> KSeFClient {
        guard let company else { throw KSeFError.missingToken }
        return try makeClient(for: company)
    }

    func makeClient(for company: Company) throws -> KSeFClient {
        guard let token = Keychain.ksefToken(for: company.id), !token.isEmpty else { throw KSeFError.missingToken }
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

    /// Synchronizacja na żądanie: aktywna firma albo (Pulpit „Wszystkie firmy”) każda firma z tokenem.
    func sync(allCompanies: Bool = false) async {
        guard let company else { return }
        let connected = companies.filter { Keychain.ksefToken(for: $0.id) != nil }
        await sync(allCompanies && !connected.isEmpty ? connected : [company])
    }

    /// Synchronizuje podane firmy po kolei i pokazuje jeden komunikat (z nazwami firm, gdy jest ich kilka).
    private func sync(_ targets: [Company]) async {
        guard !targets.isEmpty, !syncInProgress else { return }
        syncInProgress = true
        defer { syncInProgress = false }
        var messages: [String] = []
        var failed = false
        for target in targets {
            let prefix = targets.count > 1 ? "\(target.name): " : ""
            do {
                let service = KSeFSyncService(company: target, source: try makeClient(for: target), db: database, device: deviceID)
                messages.append(prefix + SyncSummary.text(try await service.run()))
            } catch {
                failed = true
                messages.append(prefix + error.userMessage)
            }
        }
        // Błąd zostaje dłużej, żeby dało się go przeczytać.
        showSyncResult(messages.joined(separator: "\n"), for: .seconds(failed ? 8 : 4))
        reload()
    }

    private var lastAutoSyncAttempt: Date?

    /// Najkrótszy odstęp między synchronizacjami uruchamianymi samoczynnie po wejściu do aplikacji.
    /// Krótszy niż interwał synchronizacji w tle (6 godzin), bo ten jest tylko prośbą do systemu.
    static let autoSyncMinInterval: TimeInterval = 3600

    /// Synchronizacja po wejściu do aplikacji: każda firma z tokenem, której ostatnia synchronizacja jest
    /// starsza niż godzina. Synchronizacji w tle iOS nie gwarantuje, więc to jedyny pewny moment na pobranie
    /// nowych faktur bez gestu. Nieudana próba nie jest ponawiana przez kwadrans, żeby błąd nie wracał
    /// przy każdym powrocie.
    func syncIfStale(now: Date = Date()) async {
        guard !databaseUnavailable, !syncInProgress else { return }
        let stale = companies.filter { company in
            !DemoData.isDemoNIP(company.nip) && Keychain.ksefToken(for: company.id) != nil
                && company.lastSyncAt.map { now.timeIntervalSince($0) >= Self.autoSyncMinInterval } ?? true
        }
        guard !stale.isEmpty else { return }
        if let attempt = lastAutoSyncAttempt, now.timeIntervalSince(attempt) < 15 * 60 { return }
        lastAutoSyncAttempt = now
        await sync(stale)
    }

    private func showSyncResult(_ message: String, for duration: Duration) {
        syncMessage = message
        syncBanner = message
        syncBannerTask?.cancel()
        syncBannerTask = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            syncBanner = nil
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
        let demo = try DemoData.seed(db: database, device: deviceID)
        activate(demo.id)
    }

    var isDemo: Bool { company.map { DemoData.isDemoNIP($0.nip) } ?? false }

    // MARK: - Dane

    /// Usuwa z telefonu wszystkie firmy z ich danymi i tokenami.
    func deleteAllData() throws {
        for company in companies {
            Keychain.setKSeFToken(nil, for: company.id)
            _ = try database.writer.write { try company.delete($0) }
        }
        tokenRevision += 1
        reload()
    }
}

import GRDB

enum CompanyError: LocalizedError {
    case limitReached(Int)
    case duplicateNIP

    var errorDescription: String? {
        switch self {
        case .limitReached(let max): String(localized: "Można dodać najwyżej \(max) firmy.")
        case .duplicateNIP: String(localized: "Firma z tym NIP-em jest już dodana.")
        }
    }
}

extension Column {
    static let createdAt = Column("createdAt")
    static let companyId = Column("companyId")
}

enum SyncSummary {
    static func text(_ r: KSeFSyncService.Result) -> String {
        var parts = [String(localized: "Pobrano \(r.fetched) faktur, nowych: \(r.new).")]
        if r.salesNew > 0 {
            parts.append(String(localized: "Nowe faktury sprzedażowe z KSeF: \(r.salesNew)."))
        }
        if !r.salesRenumbered.isEmpty {
            parts.append(String(localized: "Numery szkiców zajęte już w KSeF zostały zmienione: \(r.salesRenumbered.joined(separator: ", "))."))
        }
        if let error = r.salesError {
            parts.append(String(localized: "Nie udało się pobrać faktur sprzedażowych: \(error)"))
        }
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
