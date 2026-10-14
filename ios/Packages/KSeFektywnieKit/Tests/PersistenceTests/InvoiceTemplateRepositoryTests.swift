import Foundation
import Testing
import GRDB
import Domain
@testable import Persistence

@Suite("Szablony wizualizacji faktur")
struct InvoiceTemplateRepositoryTests {
    let db: AppDatabase
    let company: Company
    let repo: InvoiceTemplateRepository

    init() throws {
        db = try AppDatabase.inMemory()
        company = Company(nip: "1111111111", name: "F")
        try db.writer.write { [company] in try company.insert($0) }
        repo = InvoiceTemplateRepository(db: db, companyID: company.id, device: "d")
    }

    @Test("Bez zapisanych szablonów działa wbudowany")
    func builtIn() throws {
        #expect(try repo.saved().isEmpty)
        #expect(try repo.defaultTemplate() == InvoiceTemplate.standard(companyID: company.id))
    }

    @Test("Zapis z logo, pierwszy szablon domyślny, zmiana domyślnego, usunięcie")
    func lifecycle() throws {
        let logo = Data([0x89, 0x50, 0x4E, 0x47])
        let first = try repo.save(InvoiceTemplate(companyID: company.id, name: "  Firmowy ", layout: .modern, logoPNG: logo))
        #expect(first.isDefault && first.name == "Firmowy")
        let stored = try #require(try repo.saved().first)
        #expect(stored.logoPNG == logo && stored.layout == .modern && stored.updatedByDevice == "d")

        let second = try repo.save(InvoiceTemplate(companyID: company.id, name: "Angielski", language: .en))
        #expect(!second.isDefault)
        #expect(try repo.templates().map(\.name) == ["Firmowy", "Angielski"])

        try repo.setDefault(second.id)
        #expect(try repo.templates().map(\.name) == ["Angielski", "Firmowy"])
        #expect(try repo.saved().filter(\.isDefault).count == 1)

        // Odznaczenie jedynego domyślnego nie zostawia firmy bez domyślnego szablonu.
        var edited = try repo.defaultTemplate()
        edited.isDefault = false
        try repo.save(edited)
        #expect(try repo.saved().filter(\.isDefault).map(\.id) == [second.id])

        try repo.delete(second.id)
        #expect(try repo.defaultTemplate().id == first.id)
        try repo.delete(first.id)
        #expect(try repo.defaultTemplate().name == "Standardowy")
    }

    @Test("Szablony trafiają do migawki firmy i wracają przy odtworzeniu")
    func snapshot() throws {
        try repo.save(InvoiceTemplate(companyID: company.id, name: "A", logoPNG: Data([1, 2, 3])))
        let snapshot = try #require(try db.snapshot(companyID: company.id))
        #expect(snapshot.templates.map(\.name) == ["A"])
        let fresh = try AppDatabase.inMemory()
        try fresh.restore(snapshot)
        #expect(try fresh.snapshot(companyID: company.id)?.templates == snapshot.templates)
    }
}
