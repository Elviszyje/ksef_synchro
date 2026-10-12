import Foundation
import GRDB
import Domain

// MARK: - Mapowanie rekordów

extension CatalogItem: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "catalogItem"

    public init(row: Row) throws {
        self.init(id: row["id"], companyID: row["companyId"], name: row["name"], unit: row["unit"],
                  unitPriceNet: Money.decimal(row["unitPriceNet"] as Int64),
                  vatRate: VATRate(rawValue: row["vatRate"]) ?? .standard, useCount: row["useCount"],
                  lastUsedAt: row["lastUsedAt"], updatedAt: row["updatedAt"], updatedByDevice: row["updatedByDevice"])
    }

    public func encode(to c: inout PersistenceContainer) throws {
        c["id"] = id
        c["companyId"] = companyID
        c["name"] = name
        c["unit"] = unit
        c["unitPriceNet"] = Money.db(unitPriceNet)
        c["vatRate"] = vatRate.rawValue
        c["useCount"] = useCount
        c["lastUsedAt"] = lastUsedAt
        c["updatedAt"] = updatedAt
        c["updatedByDevice"] = updatedByDevice
    }
}

extension Buyer: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "buyer"

    public init(row: Row) throws {
        self.init(id: row["id"], companyID: row["companyId"], nip: row["nip"], name: row["name"], address: row["address"],
                  email: row["email"], phone: row["phone"], notes: row["notes"],
                  updatedAt: row["updatedAt"], updatedByDevice: row["updatedByDevice"])
    }

    public func encode(to c: inout PersistenceContainer) throws {
        c["id"] = id
        c["companyId"] = companyID
        c["nip"] = nip
        c["name"] = name
        c["address"] = address
        c["email"] = email
        c["phone"] = phone
        c["notes"] = notes
        c["updatedAt"] = updatedAt
        c["updatedByDevice"] = updatedByDevice
    }
}

/// Wiersz faktury bez pozycji; pozycje są w osobnej tabeli.
struct OutgoingInvoiceRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "outgoingInvoice"
    var invoice: OutgoingInvoice

    init(_ invoice: OutgoingInvoice) { self.invoice = invoice }

    init(row: Row) throws {
        invoice = OutgoingInvoice(
            id: row["id"], companyID: row["companyId"], buyerID: row["buyerId"], invoiceNumber: row["invoiceNumber"],
            issueDate: row["issueDate"], deliveryDate: row["deliveryDate"], paymentDueDate: row["paymentDueDate"],
            paymentForm: PaymentForm(rawValue: row["paymentForm"]) ?? .transfer, currency: row["currency"],
            bankAccountNumber: row["bankAccountNumber"], buyerNIP: row["buyerNip"], buyerName: row["buyerName"],
            buyerAddress: row["buyerAddress"], notes: row["notes"],
            exemptionType: VATExemptionType(rawValue: row["vatExemptionType"]) ?? .act, exemptionBasis: row["vatExemptionBasis"],
            status: OutgoingInvoiceStatus(rawValue: row["status"]) ?? .draft,
            environment: KSeFEnvironment(rawValue: row["environment"]) ?? .test,
            createdAt: row["createdAt"], updatedAt: row["updatedAt"], updatedByDevice: row["updatedByDevice"])
        invoice.ksefSessionReference = row["ksefSessionReference"]
        invoice.ksefInvoiceReference = row["ksefInvoiceReference"]
        invoice.ksefNumber = row["ksefNumber"]
        invoice.generatedXML = row["generatedXml"]
        invoice.upoXML = row["upoXml"]
        invoice.errorMessage = row["errorMessage"]
    }

    func encode(to c: inout PersistenceContainer) throws {
        c["ksefSessionReference"] = invoice.ksefSessionReference
        c["ksefInvoiceReference"] = invoice.ksefInvoiceReference
        c["ksefNumber"] = invoice.ksefNumber
        c["generatedXml"] = invoice.generatedXML
        c["upoXml"] = invoice.upoXML
        c["errorMessage"] = invoice.errorMessage
        c["id"] = invoice.id
        c["companyId"] = invoice.companyID
        c["buyerId"] = invoice.buyerID
        c["invoiceNumber"] = invoice.invoiceNumber
        c["issueDate"] = invoice.issueDate
        c["deliveryDate"] = invoice.deliveryDate
        c["paymentDueDate"] = invoice.paymentDueDate
        c["paymentForm"] = invoice.paymentForm.rawValue
        c["currency"] = invoice.currency
        c["bankAccountNumber"] = invoice.bankAccountNumber
        c["buyerNip"] = invoice.buyerNIP
        c["buyerName"] = invoice.buyerName
        c["buyerAddress"] = invoice.buyerAddress
        c["notes"] = invoice.notes
        c["vatExemptionType"] = invoice.exemptionType.rawValue
        c["vatExemptionBasis"] = invoice.exemptionBasis
        c["status"] = invoice.status.rawValue
        c["environment"] = invoice.environment.rawValue
        c["createdAt"] = invoice.createdAt
        c["updatedAt"] = invoice.updatedAt
        c["updatedByDevice"] = invoice.updatedByDevice
    }
}

public enum SalesError: Error, Equatable, LocalizedError {
    case duplicateNumber(String)
    case notEditable
    case invalid([SalesValidationIssue])

    public var errorDescription: String? {
        switch self {
        case .duplicateNumber(let n): "Faktura o numerze \(n) już istnieje."
        case .notEditable: "Fakturę można edytować tylko w statusie szkicu."
        case .invalid: "Faktura ma niekompletne dane."
        }
    }
}

// MARK: - Faktury sprzedażowe

/// Faktury sprzedażowe jednej firmy. Zapis szkicu zapamiętuje pozycje w katalogu
/// i (opcjonalnie) nabywcę — tak jak formularz w Django.
public struct SalesRepository: Sendable {
    let db: AppDatabase
    public let companyID: UUID
    public let device: String

    public init(db: AppDatabase, companyID: UUID, device: String) {
        self.db = db
        self.companyID = companyID
        self.device = device
    }

    public func invoices() throws -> [OutgoingInvoice] {
        try db.reader.read { db in
            let records = try OutgoingInvoiceRecord.filter(Column("companyId") == companyID)
                .order(Column("issueDate").desc, Column("invoiceNumber").desc).fetchAll(db)
            return try records.map { try withItems($0.invoice, db) }
        }
    }

    public func find(_ id: UUID) throws -> OutgoingInvoice? {
        try db.reader.read { db in
            try OutgoingInvoiceRecord.filter(Column("companyId") == companyID).filter(key: id).fetchOne(db)
                .map { try withItems($0.invoice, db) }
        }
    }

    public func observe() -> ValueObservation<ValueReducers.Fetch<[OutgoingInvoice]>> {
        let companyID = companyID
        return ValueObservation.tracking { db in
            try OutgoingInvoiceRecord.filter(Column("companyId") == companyID)
                .order(Column("issueDate").desc, Column("invoiceNumber").desc).fetchAll(db)
                .map { try withItems($0.invoice, db) }
        }
    }

    /// Kolejny numer według wzoru firmy, osobno dla środowiska testowego i produkcyjnego.
    public func nextNumber(pattern: String, year: Int, environment: KSeFEnvironment) throws -> String {
        let existing = try db.reader.read {
            try String.fetchAll($0, sql: "SELECT invoiceNumber FROM outgoingInvoice WHERE companyId = ? AND environment = ?",
                                arguments: [companyID, environment.rawValue])
        }
        return InvoiceNumbering.next(pattern: pattern, year: year, existing: existing)
    }

    /// Zapis szkicu (nowego lub edytowanego). Pozycje trafiają do katalogu,
    /// a nabywca do listy nabywców, gdy `saveBuyer` jest włączone.
    @discardableResult
    public func saveDraft(_ draft: OutgoingInvoice, saveBuyer: Bool, now: Date = Date()) throws -> OutgoingInvoice {
        let issues = draft.validationIssues
        guard issues.isEmpty else { throw SalesError.invalid(issues) }
        return try db.writer.write { db in
            var invoice = draft
            invoice.companyID = companyID
            // Poprawiona faktura odrzucona przez KSeF wraca do szkicu.
            if invoice.status == .rejected { invoice.status = .draft }
            invoice.updatedAt = now
            invoice.updatedByDevice = device
            if let existing = try OutgoingInvoiceRecord.filter(key: invoice.id).fetchOne(db), !existing.invoice.canBeEdited {
                throw SalesError.notEditable
            }
            let duplicate = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM outgoingInvoice WHERE companyId = ? AND environment = ? AND invoiceNumber = ? AND id != ?
                """, arguments: [companyID, invoice.environment.rawValue, invoice.invoiceNumber, invoice.id]) ?? 0
            if duplicate > 0 { throw SalesError.duplicateNumber(invoice.invoiceNumber) }

            if saveBuyer {
                invoice.buyerID = try upsertBuyer(invoice, db: db, now: now)
            }
            try OutgoingInvoiceRecord(invoice).save(db)
            try insertSalesItems(invoice, db)
            try CatalogRepository.remember(invoice.items, companyID: companyID, device: device, now: now, db: db)
            return invoice
        }
    }

    /// Zmiana stanu wysyłki (bez walidacji formularza) — używane przez usługę wysyłki.
    @discardableResult
    public func updateSubmission(_ id: UUID, now: Date = Date(), _ change: (inout OutgoingInvoice) -> Void) throws -> OutgoingInvoice? {
        try db.writer.write { db in
            guard let record = try OutgoingInvoiceRecord.filter(Column("companyId") == companyID).filter(key: id).fetchOne(db) else { return nil }
            var invoice = try withItems(record.invoice, db)
            change(&invoice)
            invoice.updatedAt = now
            invoice.updatedByDevice = device
            try OutgoingInvoiceRecord(invoice).update(db)
            return invoice
        }
    }

    /// Faktury wysłane, których wynik nie jest jeszcze znany (albo brak UPO).
    public func awaitingKSeF() throws -> [OutgoingInvoice] {
        try invoices().filter { $0.status == .sending || ($0.status == .accepted && $0.upoXML.isEmpty) }
    }

    public func deleteDraft(_ id: UUID) throws {
        try db.writer.write { db in
            guard let record = try OutgoingInvoiceRecord.filter(Column("companyId") == companyID).filter(key: id).fetchOne(db) else { return }
            guard record.invoice.status == .draft else { throw SalesError.notEditable }
            _ = try record.delete(db)
        }
    }

    /// Podstawy zwolnienia użyte wcześniej + najczęstsze (podpowiedzi w formularzu).
    public func exemptionSuggestions() throws -> [String] {
        let used = try db.reader.read {
            try String.fetchAll($0, sql: """
                SELECT vatExemptionBasis FROM outgoingInvoice WHERE companyId = ? AND vatExemptionBasis != ''
                GROUP BY vatExemptionBasis ORDER BY MAX(updatedAt) DESC LIMIT 20
                """, arguments: [companyID])
        }
        var seen = Set<String>()
        return (used + VATExemptionSuggestions.common).filter { seen.insert($0).inserted }
    }

    public func buyers(matching query: String = "") throws -> [Buyer] {
        try db.reader.read { db in
            var request = Buyer.filter(Column("companyId") == companyID)
            let q = query.trimmingCharacters(in: .whitespaces)
            if !q.isEmpty { request = request.filter(Column("name").like("%\(q)%") || Column("nip").like("%\(q)%")) }
            return try request.order(Column("updatedAt").desc).limit(50).fetchAll(db)
        }
    }

    private func upsertBuyer(_ invoice: OutgoingInvoice, db: Database, now: Date) throws -> UUID {
        if var buyer = try Buyer.filter(Column("companyId") == companyID).filter(Column("nip") == invoice.buyerNIP).fetchOne(db) {
            buyer.name = invoice.buyerName
            buyer.address = invoice.buyerAddress
            buyer.updatedAt = now
            buyer.updatedByDevice = device
            try buyer.update(db)
            return buyer.id
        }
        let buyer = Buyer(companyID: companyID, nip: invoice.buyerNIP, name: invoice.buyerName, address: invoice.buyerAddress,
                          updatedAt: now, updatedByDevice: device)
        try buyer.insert(db)
        return buyer.id
    }
}

private func withItems(_ invoice: OutgoingInvoice, _ db: Database) throws -> OutgoingInvoice {
    try salesWithItems(invoice, db)
}

// MARK: - Katalog pozycji

public struct CatalogRepository: Sendable {
    let db: AppDatabase
    public let companyID: UUID
    public let device: String

    public init(db: AppDatabase, companyID: UUID, device: String) {
        self.db = db
        self.companyID = companyID
        self.device = device
    }

    /// Najczęściej i najświeżej używane najpierw; wyszukiwanie po fragmencie nazwy.
    public func items(matching query: String = "") throws -> [CatalogItem] {
        let request = request(query)
        return try db.reader.read { try request.fetchAll($0) }
    }

    public func observe(_ query: String = "") -> ValueObservation<ValueReducers.Fetch<[CatalogItem]>> {
        let request = request(query)
        return ValueObservation.tracking { try request.fetchAll($0) }
    }

    func request(_ query: String) -> QueryInterfaceRequest<CatalogItem> {
        var request = CatalogItem.filter(Column("companyId") == companyID)
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { request = request.filter(Column("name").like("%\(q)%")) }
        return request.order(Column("useCount").desc, Column("lastUsedAt").desc, Column("name"))
    }

    public func update(_ item: CatalogItem, now: Date = Date()) throws {
        var updated = item
        updated.updatedAt = now
        updated.updatedByDevice = device
        try db.writer.write { [updated] in try updated.update($0) }
    }

    /// Usunięcie z katalogu nie zmienia zapisanych faktur — pozycje faktur są kopiami.
    public func delete(_ id: UUID) throws {
        _ = try db.writer.write { try CatalogItem.filter(Column("companyId") == companyID).filter(key: id).deleteAll($0) }
    }

    /// Port `CatalogItem.remember`: ta sama nazwa i jednostka → aktualizacja ceny, stawki i licznika.
    static func remember(_ items: [OutgoingInvoiceItem], companyID: UUID, device: String, now: Date, db: Database) throws {
        for item in items {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let unit = item.unit.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOr("szt.")
            if var entry = try CatalogItem.filter(Column("companyId") == companyID)
                .filter(Column("name") == name).filter(Column("unit") == unit).fetchOne(db) {
                entry.unitPriceNet = item.unitPriceNet
                entry.vatRate = item.vatRate
                entry.useCount += 1
                entry.lastUsedAt = now
                entry.updatedAt = now
                entry.updatedByDevice = device
                try entry.update(db)
            } else {
                try CatalogItem(companyID: companyID, name: name, unit: unit, unitPriceNet: item.unitPriceNet,
                                vatRate: item.vatRate, useCount: 1, lastUsedAt: now, updatedAt: now, updatedByDevice: device).insert(db)
            }
        }
    }
}

extension String {
    func nonEmptyOr(_ fallback: String) -> String { isEmpty ? fallback : self }
}
