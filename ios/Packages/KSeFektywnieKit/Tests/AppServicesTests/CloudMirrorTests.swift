import Foundation
import Testing
import Domain
import Persistence
@testable import AppServices

@Suite("Katalog iCloud: lustro i odtworzenie")
struct CloudMirrorTests {
    let root: URL
    let fs: CoordinatedFileSystem
    let db: AppDatabase
    let company: Company
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "mirror-\(UUID().uuidString)")
        fs = CoordinatedFileSystem(root: root)
        db = try AppDatabase.inMemory()
        company = try DemoData.seed(db: db, device: "dev-A", today: LocalDate(year: 2026, month: 10, day: 12)!, now: Self.now)
        // Plik przelewów, żeby lustro miało też katalog "przelewy".
        let account = try #require(try db.snapshot(companyID: company.id)?.bankAccounts.first)
        let payments = PaymentFileRepository(db: db, companyID: company.id, device: "dev-A")
        let payable = try payments.payableInvoices()
        try payments.generate(invoiceIDs: payable.map(\.id), debitAccount: account,
                              payer: PaymentPayer(debitAccount: account.accountNumber, name: company.name, address: company.address),
                              date: LocalDate(year: 2026, month: 10, day: 12)!, now: Self.now)
    }

    func json(_ path: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: try fs.read(path)) as! [String: Any]
    }

    @Test("Struktura katalogu i format JSON jak w API Django")
    func layout() throws {
        let report = try CloudMirror(db: db, fileSystem: fs, deviceID: "dev-A").sync(now: Self.now)
        #expect(report.written > 10 && report.removed == 0)
        let files = try fs.files(under: "")
        #expect(files.contains("manifest.json"))
        #expect(files.contains("1111111111/firma.json"))
        #expect(files.contains("1111111111/nabywcy.json") && files.contains("1111111111/katalog.json"))
        #expect(files.contains { $0.hasPrefix("1111111111/faktury-kosztowe/2026/2026-10/") && $0.hasSuffix(".xml") })
        #expect(files.contains { $0.hasPrefix("1111111111/faktury-sprzedazowe/test/2026/FV-2026-0002") })
        #expect(files.contains { $0.hasPrefix("1111111111/przelewy/2026-") && $0.hasSuffix("Erste_Bank.txt") })
        #expect(files.contains { $0.hasPrefix("1111111111/wyciagi/") && $0.hasSuffix("wyciag_demo.sta.json") })
        #expect(files.allSatisfy { $0.unicodeScalars.allSatisfy(\.isASCII) })

        let invoicePath = try #require(files.first { $0.contains("faktury-kosztowe") && $0.hasSuffix(".json") })
        let invoice = try json(invoicePath)
        #expect(invoice["amount_gross"] is String)
        #expect(invoice["ksef_reference_number"] is String)
        #expect(invoice["schema_version"] as? Int == 1)
        #expect((invoice["amount_gross"] as! String).contains("."))

        let manifest = try #require(CloudMirror.manifest(in: fs))
        #expect(manifest.deviceID == "dev-A" && manifest.companies == ["Firma Demo Sp. z o.o."])
    }

    @Test("Odtworzenie na nowym urządzeniu daje te same dane")
    func roundTrip() throws {
        try CloudMirror(db: db, fileSystem: fs, deviceID: "dev-A").sync(now: Self.now)
        let fresh = try AppDatabase.inMemory()
        let restored = try CloudMirror.restore(from: fs, into: fresh)
        #expect(restored.map(\.id) == [company.id])

        let a = try #require(try db.snapshot(companyID: company.id))
        let b = try #require(try fresh.snapshot(companyID: company.id))
        #expect(a.company == b.company)
        #expect(a.bankAccounts == b.bankAccounts)
        #expect(a.invoices == b.invoices)
        #expect(a.statusLogs.map(\.change) == b.statusLogs.map(\.change))
        #expect(a.sales.map(\.id) == b.sales.map(\.id))
        #expect(zip(a.sales, b.sales).allSatisfy { $0.items.map(\.amountGross) == $1.items.map(\.amountGross) && $0.exemptionBasis == $1.exemptionBasis })
        #expect(a.buyers == b.buyers)
        #expect(a.catalog == b.catalog)
        #expect(a.paymentFiles.map(\.file) == b.paymentFiles.map(\.file))
        #expect(a.paymentFiles.map(\.lines) == b.paymentFiles.map(\.lines))
        #expect(a.statements.map(\.statement) == b.statements.map(\.statement))
        #expect(a.statements.map(\.transactions) == b.statements.map(\.transactions))
        #expect(a.statements.map(\.matches) == b.statements.map(\.matches))

        // Drugie urządzenie przejmuje istniejące pliki bez ponownego zapisu do iCloud.
        let before = Dictionary(uniqueKeysWithValues: try fs.files(under: "").map { ($0, try fs.read($0)) })
        let adopted = try CloudMirror(db: fresh, fileSystem: fs, deviceID: "dev-B").sync(now: Self.now)
        for (path, data) in before where (try? fs.read(path)) != data && path != "manifest.json" {
            Issue.record("zmieniony po odtworzeniu: \(path)\n\(String(decoding: data, as: UTF8.self).prefix(600))\n---\n\(String(decoding: try fs.read(path), as: UTF8.self).prefix(600))")
        }
        #expect(adopted.written == 0 && adopted.removed == 0)
        // Ponowne odtworzenie nie dubluje firmy.
        #expect(try CloudMirror.restore(from: fs, into: fresh).isEmpty)
    }

    @Test("Zapis różnicowy i usuwanie plików po skasowanych rekordach")
    func incremental() throws {
        let mirror = CloudMirror(db: db, fileSystem: fs, deviceID: "dev-A")
        let first = try mirror.sync(now: Self.now)
        let second = try mirror.sync(now: Self.now)
        #expect(second == MirrorReport(written: 0, removed: 0, unchanged: first.written))

        let invoices = InvoiceRepository(db: db, companyID: company.id, device: "dev-A")
        let target = try #require(try invoices.fetch().first)
        try invoices.updateNotes(target.id, notes: "zmiana", now: Self.now)
        #expect(try mirror.sync(now: Self.now).written == 1)

        let statements = StatementRepository(db: db, companyID: company.id, device: "dev-A")
        try statements.delete(try #require(try statements.summaries().first).id)
        let afterDelete = try mirror.sync(now: Self.now)
        #expect(afterDelete.removed == 2)
        #expect(try fs.files(under: "1111111111/wyciagi").isEmpty)

        // Pliki usunięte ręcznie z iCloud wracają po pełnym zapisie.
        try FileManager.default.removeItem(at: root.appending(path: "1111111111/katalog.json"))
        #expect(try mirror.sync(now: Self.now).written == 1)
        #expect(try mirror.rewriteAll(now: Self.now).written == 0)
    }

    @Test("Daty: cykl zapis → odczyt → zapis daje ten sam tekst", arguments: 0..<200)
    func dateStability(_ seed: Int) throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000 + Double(seed) * 0.0013579 + Double.random(in: 0..<0.001))
        let text = CloudDate.format(date)
        let parsed = try #require(CloudDate.parse(text))
        #expect(CloudDate.format(parsed) == text)
        // Odczyt przez GRDB (obcina do ms) i ponowny zapis też daje ten sam tekst.
        let db = try AppDatabase.inMemory()
        let stored = try db.writer.write { db -> Date in
            try db.execute(sql: "CREATE TABLE t (d DATETIME)")
            try db.execute(sql: "INSERT INTO t VALUES (?)", arguments: [parsed])
            return try Date.fetchOne(db, sql: "SELECT d FROM t")!
        }
        #expect(CloudDate.format(stored) == text)
    }

    @Test("Bezpieczne nazwy plików")
    func safeNames() {
        #expect(CloudMirror.safeName("FV/2026/0001") == "FV-2026-0001")
        #expect(CloudMirror.safeName("Wyciąg łódź.sta") == "Wyciag-lodz.sta")
        #expect(CloudMirror.safeName("///") == "plik")
    }
}
