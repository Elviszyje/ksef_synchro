import Foundation
import GRDB
import Domain

extension InvoiceTemplate: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "invoiceTemplate"

    public init(row: Row) throws {
        self.init(id: row["id"], companyID: row["companyId"], name: row["name"],
                  layout: InvoiceLayout(rawValue: row["layout"]) ?? .classic, accentColor: row["accentColor"],
                  language: InvoiceLanguage(rawValue: row["language"]) ?? .pl, logoPNG: row["logoPng"],
                  showQRCode: row["showQrCode"], showAmountInWords: row["showAmountInWords"],
                  showSignatureFields: row["showSignatureFields"], footerText: row["footerText"], closingNote: row["closingNote"],
                  sectionOrder: InvoiceSection.decode(row["sectionOrder"]),
                  logoSide: InvoiceSide(rawValue: row["logoSide"]), qrSide: InvoiceSide(rawValue: row["qrSide"]) ?? .trailing,
                  isDefault: row["isDefault"], updatedAt: row["updatedAt"], updatedByDevice: row["updatedByDevice"])
    }

    public func encode(to c: inout PersistenceContainer) throws {
        c["id"] = id
        c["companyId"] = companyID
        c["name"] = name
        c["layout"] = layout.rawValue
        c["accentColor"] = accentColor
        c["language"] = language.rawValue
        c["logoPng"] = logoPNG
        c["showQrCode"] = showQRCode
        c["showAmountInWords"] = showAmountInWords
        c["showSignatureFields"] = showSignatureFields
        c["footerText"] = footerText
        c["closingNote"] = closingNote
        c["sectionOrder"] = InvoiceSection.encode(sectionOrder)
        c["logoSide"] = logoSide?.rawValue ?? ""
        c["qrSide"] = qrSide.rawValue
        c["isDefault"] = isDefault
        c["updatedAt"] = updatedAt
        c["updatedByDevice"] = updatedByDevice
    }
}

/// Szablony wizualizacji faktur sprzedażowych. Zawsze dokładnie jeden zapisany szablon jest domyślny.
public struct InvoiceTemplateRepository: Sendable {
    let db: AppDatabase
    public let companyID: UUID
    public let device: String

    public init(db: AppDatabase, companyID: UUID, device: String) {
        self.db = db
        self.companyID = companyID
        self.device = device
    }

    /// Zapisane szablony albo wbudowany; domyślny pierwszy.
    public func templates() throws -> [InvoiceTemplate] {
        InvoiceTemplates.effective(try saved(), companyID: companyID)
    }

    public func saved() throws -> [InvoiceTemplate] {
        try db.reader.read { try InvoiceTemplate.filter(Column("companyId") == companyID).fetchAll($0) }
    }

    public func defaultTemplate() throws -> InvoiceTemplate { try templates()[0] }

    public func observe() -> ValueObservation<ValueReducers.Map<ValueReducers.Fetch<[InvoiceTemplate]>, [InvoiceTemplate]>> {
        let companyID = companyID
        return ValueObservation.tracking { try InvoiceTemplate.filter(Column("companyId") == companyID).fetchAll($0) }
            .map { InvoiceTemplates.effective($0, companyID: companyID) }
    }

    /// Zapis (wstawienie albo zmiana). Pierwszy zapisany szablon staje się domyślnym; zaznaczenie
    /// „domyślny” zdejmuje je z pozostałych.
    @discardableResult
    public func save(_ template: InvoiceTemplate, now: Date = Date()) throws -> InvoiceTemplate {
        var template = template
        template.companyID = companyID
        template.name = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
        template.updatedAt = now
        template.updatedByDevice = device
        return try db.writer.write { [template] db in
            var template = template
            let others = try InvoiceTemplate.filter(Column("companyId") == companyID).filter(Column("id") != template.id).fetchAll(db)
            if others.isEmpty { template.isDefault = true }
            if template.isDefault {
                for var other in others where other.isDefault {
                    other.isDefault = false
                    other.updatedAt = now
                    other.updatedByDevice = device
                    try other.update(db)
                }
            } else if !others.contains(where: \.isDefault) {
                template.isDefault = true
            }
            try template.save(db)
            return template
        }
    }

    public func setDefault(_ id: UUID, now: Date = Date()) throws {
        guard var template = try saved().first(where: { $0.id == id }) else { return }
        template.isDefault = true
        try save(template, now: now)
    }

    /// Usuwa szablon; gdy był domyślny, domyślnym zostaje inny (pierwszy alfabetycznie).
    public func delete(_ id: UUID, now: Date = Date()) throws {
        try db.writer.write { db in
            guard let template = try InvoiceTemplate.filter(Column("companyId") == companyID).filter(key: id).fetchOne(db) else { return }
            _ = try template.delete(db)
            guard template.isDefault else { return }
            let rest = try InvoiceTemplate.filter(Column("companyId") == companyID).fetchAll(db)
            if var next = rest.min(by: { $0.name.lowercased() < $1.name.lowercased() }) {
                next.isDefault = true
                next.updatedAt = now
                next.updatedByDevice = device
                try next.update(db)
            }
        }
    }
}
