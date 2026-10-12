import Foundation
import CryptoKit
import Domain
import Persistence

/// System plików lustra (iCloud Drive albo katalog lokalny). Ścieżki względne, separator "/".
public protocol MirrorFileSystem: Sendable {
    func write(_ data: Data, to path: String) throws
    func remove(_ path: String) throws
    func read(_ path: String) throws -> Data
    func exists(_ path: String) -> Bool
    /// Wszystkie pliki pod katalogiem (rekurencyjnie), jako ścieżki względne od korzenia.
    func files(under directory: String) throws -> [String]
}

/// Pliki w katalogu na dysku z koordynacją `NSFileCoordinator` (wymagana dla iCloud Drive).
public struct CoordinatedFileSystem: MirrorFileSystem {
    public let root: URL

    public init(root: URL) { self.root = root }

    func url(_ path: String) -> URL { root.appending(path: path) }

    public func write(_ data: Data, to path: String) throws {
        let target = url(path)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try coordinate(target, writing: true) { try data.write(to: $0, options: .atomic) }
    }

    public func remove(_ path: String) throws {
        let target = url(path)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try coordinate(target, writing: true, deleting: true) { try FileManager.default.removeItem(at: $0) }
    }

    public func read(_ path: String) throws -> Data {
        var data = Data()
        try coordinate(url(path), writing: false) { data = try Data(contentsOf: $0) }
        return data
    }

    public func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: url(path).path) }

    public func files(under directory: String) throws -> [String] {
        let base = url(directory)
        guard let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        let rootPath = root.standardizedFileURL.path
        var result: [String] = []
        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            var relative = fileURL.standardizedFileURL.path
            if relative.hasPrefix(rootPath) { relative.removeFirst(rootPath.count) }
            result.append(relative.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        }
        return result.sorted()
    }

    /// Prosi iCloud o pobranie wszystkich plików i czeka (do `timeout`), aż będą lokalnie.
    public func downloadAll(timeout: TimeInterval = 120, progress: @Sendable (Int, Int) -> Void = { _, _ in }) async throws {
        let keys: Set<URLResourceKey> = [.ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey]
        var pending = startDownloads(keys: keys)
        let total = pending.count
        let deadline = Date().addingTimeInterval(timeout)
        while !pending.isEmpty && Date() < deadline {
            pending.removeAll { url in
                var u = url
                u.removeAllCachedResourceValues()
                return (try? u.resourceValues(forKeys: keys))?.ubiquitousItemDownloadingStatus == .current
            }
            progress(total - pending.count, total)
            if !pending.isEmpty { try await Task.sleep(for: .milliseconds(500)) }
        }
    }

    /// Zleca pobranie plików, których nie ma jeszcze lokalnie; zwraca listę oczekujących.
    private func startDownloads(keys: Set<URLResourceKey>) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys)) else { return [] }
        var pending: [URL] = []
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: keys)
            guard values?.isUbiquitousItem == true, values?.ubiquitousItemDownloadingStatus != .current else { continue }
            try? fm.startDownloadingUbiquitousItem(at: fileURL)
            pending.append(fileURL)
        }
        return pending
    }

    private func coordinate(_ url: URL, writing: Bool, deleting: Bool = false, _ body: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var bodyError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        if writing {
            coordinator.coordinate(writingItemAt: url, options: deleting ? .forDeleting : .forReplacing, error: &coordinationError) { u in
                do { try body(u) } catch { bodyError = error }
            }
        } else {
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { u in
                do { try body(u) } catch { bodyError = error }
            }
        }
        if let error = coordinationError ?? bodyError { throw error }
    }
}

public struct MirrorReport: Equatable, Sendable {
    public var written = 0
    public var removed = 0
    public var unchanged = 0
}

/// Lustro danych w katalogu (iCloud Drive). Baza SQLite pozostaje źródłem prawdy;
/// lustro zapisuje tylko pliki, których treść się zmieniła, i usuwa pliki skasowanych rekordów.
public struct CloudMirror: Sendable {
    let db: AppDatabase
    let fs: any MirrorFileSystem
    let deviceID: String

    public static let manifestPath = "manifest.json"

    public init(db: AppDatabase, fileSystem: any MirrorFileSystem, deviceID: String) {
        self.db = db
        self.fs = fileSystem
        self.deviceID = deviceID
    }

    struct PlannedFile {
        let path: String
        let data: Data
        let recordType: String
        let recordID: String
    }

    // MARK: Układ katalogu

    static func folder(for company: Company) -> String { safeName(company.nip) }

    /// Nazwa pliku: tylko ASCII, bez ukośników (numery faktur zawierają "/").
    static func safeName(_ text: String) -> String {
        let polish = text.replacingOccurrences(of: "ł", with: "l").replacingOccurrences(of: "Ł", with: "L")
        let transliterated = polish.applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false) ?? polish
        let mapped = transliterated.unicodeScalars.map { s -> Character in
            (s.isASCII && (CharacterSet.alphanumerics.contains(s) || "._-".unicodeScalars.contains(s))) ? Character(s) : "-"
        }
        var name = String(mapped)
        while name.contains("--") { name = name.replacingOccurrences(of: "--", with: "-") }
        return name.trimmingCharacters(in: CharacterSet(charactersIn: "-.")).nonEmptyOr("plik")
    }

    func plan() throws -> [PlannedFile] {
        let encoder = CloudFormat.encoder
        var files: [PlannedFile] = []
        func add(_ path: String, _ data: Data, _ type: String, _ id: String) {
            files.append(PlannedFile(path: path, data: data, recordType: type, recordID: id))
        }
        for company in try db.companies() {
            guard let s = try db.snapshot(companyID: company.id) else { continue }
            let root = Self.folder(for: company)
            add("\(root)/firma.json", try encoder.encode(CompanyDTO(s)), "company", company.id.uuidString)

            let historyByInvoice = Dictionary(grouping: s.statusLogs, by: \.invoiceID)
            for invoice in s.invoices {
                let dir = "\(root)/faktury-kosztowe/\(invoice.issueDate.year)/\(String(format: "%04d-%02d", invoice.issueDate.year, invoice.issueDate.month))"
                let base = Self.safeName(invoice.ksefReferenceNumber)
                let xmlName = invoice.rawXML.isEmpty ? nil : "\(base).xml"
                add("\(dir)/\(base).json", try encoder.encode(InvoiceDTO(invoice, history: historyByInvoice[invoice.id] ?? [], xmlFile: xmlName)),
                    "invoice", invoice.id.uuidString)
                if let xmlName { add("\(dir)/\(xmlName)", Data(invoice.rawXML.utf8), "invoice.xml", invoice.id.uuidString) }
            }

            for sale in s.sales {
                let env = sale.environment == .test ? "test/" : ""
                let dir = "\(root)/faktury-sprzedazowe/\(env)\(sale.issueDate.year)"
                let base = Self.safeName(sale.invoiceNumber)
                let xmlName = sale.generatedXML.isEmpty ? nil : "\(base).xml"
                let upoName = sale.upoXML.isEmpty ? nil : "\(base).upo.xml"
                add("\(dir)/\(base).json", try encoder.encode(SalesDTO(sale, xmlFile: xmlName, upoFile: upoName)), "sale", sale.id.uuidString)
                if let xmlName { add("\(dir)/\(xmlName)", Data(sale.generatedXML.utf8), "sale.xml", sale.id.uuidString) }
                if let upoName { add("\(dir)/\(upoName)", Data(sale.upoXML.utf8), "sale.upo", sale.id.uuidString) }
            }

            add("\(root)/nabywcy.json", try encoder.encode(s.buyers.map(BuyerDTO.init)), "buyers", company.id.uuidString)
            add("\(root)/katalog.json", try encoder.encode(s.catalog.map(CatalogDTO.init)), "catalog", company.id.uuidString)

            for (file, lines) in s.paymentFiles {
                let base = "\(Self.day(file.createdAt))_\(file.id.uuidString.prefix(8))_\(Self.safeName(file.fileName))"
                add("\(root)/przelewy/\(base)", file.content, "payment.content", file.id.uuidString)
                add("\(root)/przelewy/\(base).json", try encoder.encode(PaymentFileDTO(file, lines: lines, contentFile: base)),
                    "payment", file.id.uuidString)
            }

            for (statement, transactions, matches) in s.statements {
                let base = "\(Self.day(statement.uploadedAt))_\(statement.id.uuidString.prefix(8))_\(Self.safeName(statement.fileName))"
                add("\(root)/wyciagi/\(base)", Data(statement.rawContent.utf8), "statement.content", statement.id.uuidString)
                add("\(root)/wyciagi/\(base).json",
                    try encoder.encode(StatementDTO(statement, transactions: transactions, matches: matches, contentFile: base)),
                    "statement", statement.id.uuidString)
            }
        }
        return files
    }

    static func day(_ date: Date) -> String { LocalDate(date).iso }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Zapisuje zmiany od ostatniego przebiegu. Plik identyczny z tym na dysku (np. po
    /// przywróceniu danych) jest tylko odnotowywany, bez ponownego zapisu do iCloud.
    @discardableResult
    public func sync(now: Date = Date()) throws -> MirrorReport {
        let planned = try plan()
        let state = try db.mirrorState()
        var report = MirrorReport()
        for file in planned {
            let digest = Self.hash(file.data)
            if state[file.path]?.contentHash == digest, fs.exists(file.path) {
                report.unchanged += 1
                continue
            }
            if state[file.path] == nil, fs.exists(file.path), (try? fs.read(file.path)) == file.data {
                report.unchanged += 1
            } else {
                try fs.write(file.data, to: file.path)
                report.written += 1
            }
            try db.recordMirrorWrite(path: file.path, recordType: file.recordType, recordID: file.recordID, hash: digest, at: now)
        }
        let plannedPaths = Set(planned.map(\.path))
        let stale = state.keys.filter { !plannedPaths.contains($0) && $0 != Self.manifestPath }
        for path in stale { try fs.remove(path) }
        try db.removeMirrorState(paths: Array(stale))
        report.removed = stale.count

        if report.written > 0 || report.removed > 0 || !fs.exists(Self.manifestPath) {
            let manifest = ManifestDTO(
                schema_version: CloudFormat.schemaVersion, app: "KS-eFektywnie", device_id: deviceID, written_at: now,
                companies: try db.companies().map { .init(id: $0.id, nip: $0.nip, name: $0.name, folder: Self.folder(for: $0)) })
            try fs.write(try CloudFormat.encoder.encode(manifest), to: Self.manifestPath)
        }
        return report
    }

    /// Pełny zapis od nowa (np. gdy ktoś usunął pliki z iCloud).
    @discardableResult
    public func rewriteAll(now: Date = Date()) throws -> MirrorReport {
        try db.clearMirrorState()
        for file in try plan() { try fs.write(file.data, to: file.path) }
        try db.clearMirrorState()
        return try sync(now: now)
    }

    /// Manifest w katalogu, jeśli istnieje.
    public static func manifest(in fs: any MirrorFileSystem) -> (deviceID: String, writtenAt: Date, companies: [String])? {
        guard fs.exists(manifestPath), let data = try? fs.read(manifestPath),
              let m = try? CloudFormat.decoder.decode(ManifestDTO.self, from: data) else { return nil }
        return (m.device_id, m.written_at, m.companies.map(\.name))
    }

    /// Odtwarza z katalogu firmy, których nie ma w bazie. Zwraca odtworzone firmy.
    @discardableResult
    public static func restore(from fs: any MirrorFileSystem, into db: AppDatabase) throws -> [Company] {
        let decoder = CloudFormat.decoder
        let manifest = try decoder.decode(ManifestDTO.self, from: try fs.read(manifestPath))
        let existing = Set(try db.companies().map(\.id))
        var restored: [Company] = []
        for entry in manifest.companies where !existing.contains(entry.id) {
            let root = entry.folder
            let companyDTO = try decoder.decode(CompanyDTO.self, from: try fs.read("\(root)/firma.json"))
            let company = companyDTO.company()
            var snapshot = CompanySnapshot(company: company, bankAccounts: companyDTO.accounts())

            func jsonFiles(_ dir: String) throws -> [String] { try fs.files(under: "\(root)/\(dir)").filter { $0.hasSuffix(".json") } }
            func sibling(_ path: String, _ name: String?) -> String? {
                guard let name else { return nil }
                return (path as NSString).deletingLastPathComponent + "/" + name
            }
            func text(_ path: String?) -> String {
                guard let path, let data = try? fs.read(path) else { return "" }
                return String(decoding: data, as: UTF8.self)
            }

            for path in try jsonFiles("faktury-kosztowe") {
                let dto = try decoder.decode(InvoiceDTO.self, from: try fs.read(path))
                snapshot.invoices.append(dto.invoice(companyID: company.id, rawXML: text(sibling(path, dto.xml_file))))
                snapshot.statusLogs += dto.history()
            }
            for path in try jsonFiles("faktury-sprzedazowe") {
                let dto = try decoder.decode(SalesDTO.self, from: try fs.read(path))
                snapshot.sales.append(dto.invoice(companyID: company.id, xml: text(sibling(path, dto.xml_file)),
                                                  upo: text(sibling(path, dto.upo_file))))
            }
            if fs.exists("\(root)/nabywcy.json") {
                snapshot.buyers = try decoder.decode([BuyerDTO].self, from: try fs.read("\(root)/nabywcy.json")).map { $0.buyer(companyID: company.id) }
            }
            if fs.exists("\(root)/katalog.json") {
                snapshot.catalog = try decoder.decode([CatalogDTO].self, from: try fs.read("\(root)/katalog.json")).map { $0.item(companyID: company.id) }
            }
            for path in try jsonFiles("przelewy") {
                guard let dto = try? decoder.decode(PaymentFileDTO.self, from: try fs.read(path)),
                      let contentPath = sibling(path, dto.content_file) else { continue }
                let (file, lines) = dto.file(companyID: company.id, content: (try? fs.read(contentPath)) ?? Data())
                snapshot.paymentFiles.append((file: file, lines: lines))
            }
            for path in try jsonFiles("wyciagi") {
                guard let dto = try? decoder.decode(StatementDTO.self, from: try fs.read(path)) else { continue }
                let (statement, txs, matches) = dto.statement(companyID: company.id, content: text(sibling(path, dto.content_file)))
                snapshot.statements.append((statement: statement, transactions: txs, matches: matches))
            }
            try db.restore(snapshot)
            restored.append(company)
        }
        return restored
    }
}

extension String {
    func nonEmptyOr(_ fallback: String) -> String { isEmpty ? fallback : self }
}
