import Foundation
import GRDB
import Domain

/// Filtr listy faktur (odpowiednik `InvoiceFilter` z Django).
public struct InvoiceFilter: Hashable, Sendable {
    public var statuses: Set<InvoiceStatus> = []
    public var search = ""
    public var issuedFrom: LocalDate?
    public var issuedTo: LocalDate?
    public var overdueOnly = false
    public var splitPaymentOnly = false

    public init() {}
}

/// Dostęp do faktur kosztowych jednej firmy.
public struct InvoiceRepository: Sendable {
    let db: AppDatabase
    public let companyID: UUID
    public let device: String

    public init(db: AppDatabase, companyID: UUID, device: String) {
        self.db = db
        self.companyID = companyID
        self.device = device
    }

    func base() -> QueryInterfaceRequest<Invoice> {
        Invoice.filter(Column("companyId") == companyID)
    }

    public func request(_ filter: InvoiceFilter, today: LocalDate = .today()) -> QueryInterfaceRequest<Invoice> {
        var request = base()
        if !filter.statuses.isEmpty {
            request = request.filter(filter.statuses.map(\.rawValue).contains(Column("status")))
        }
        if let from = filter.issuedFrom { request = request.filter(Column("issueDate") >= from) }
        if let to = filter.issuedTo { request = request.filter(Column("issueDate") <= to) }
        if filter.splitPaymentOnly { request = request.filter(Column("isSplitPayment") == true) }
        if filter.overdueOnly {
            request = request
                .filter(Column("paymentDueDate") < today)
                .filter(![InvoiceStatus.paid.rawValue, InvoiceStatus.sentForPayment.rawValue].contains(Column("status")))
        }
        let term = filter.search.trimmingCharacters(in: .whitespaces)
        if !term.isEmpty {
            let pattern = "%\(term)%"
            request = request.filter(
                Column("invoiceNumber").like(pattern) || Column("sellerName").like(pattern)
                || Column("sellerNip").like(pattern) || Column("ksefReferenceNumber").like(pattern))
        }
        return request.order(Column("issueDate").desc, Column("syncedAt").desc)
    }

    public func fetch(_ filter: InvoiceFilter = InvoiceFilter(), today: LocalDate = .today()) throws -> [Invoice] {
        let request = request(filter, today: today)
        return try db.reader.read { try request.fetchAll($0) }
    }

    public func find(_ id: UUID) throws -> Invoice? {
        try db.reader.read { try base().filter(key: id).fetchOne($0) }
    }

    public func statusLog(_ id: UUID) throws -> [InvoiceStatusLogEntry] {
        try db.reader.read {
            try InvoiceStatusLogEntry.filter(Column("invoiceId") == id).order(Column("changedAt").desc, Column("id").desc).fetchAll($0)
        }
    }

    /// Zapis wyników synchronizacji: nowe faktury dodaje, istniejące scala
    /// (status i notatki użytkownika zostają). Zwraca liczbę nowych.
    @discardableResult
    public func upsertFromKSeF(_ incoming: [Invoice], now: Date = Date()) throws -> Int {
        try db.writer.write { db in
            var created = 0
            for invoice in incoming {
                if var existing = try base().filter(Column("ksefReferenceNumber") == invoice.ksefReferenceNumber).fetchOne(db) {
                    if let change = InvoiceMapping.merge(invoice, into: &existing, now: now, device: device) {
                        try InvoiceStatusLogEntry(invoiceID: existing.id, change: change, device: device).insert(db)
                    }
                    try existing.update(db)
                } else {
                    var new = invoice
                    new.companyID = companyID
                    try new.insert(db)
                    created += 1
                }
            }
            return created
        }
    }

    public func changeStatus(_ id: UUID, to status: InvoiceStatus, note: String = "", now: Date = Date()) throws {
        try db.writer.write { db in
            guard var invoice = try base().filter(key: id).fetchOne(db) else { return }
            let changes = try invoice.changeStatus(to: status, note: note, at: now, device: device)
            try invoice.update(db)
            for change in changes { try InvoiceStatusLogEntry(invoiceID: id, change: change, device: device).insert(db) }
        }
    }

    /// Zmiana zbiorcza: faktury, dla których przejście jest niedozwolone, są pomijane.
    @discardableResult
    public func changeStatus(_ ids: [UUID], to status: InvoiceStatus, now: Date = Date()) throws -> Int {
        try db.writer.write { db in
            var changed = 0
            for id in ids {
                guard var invoice = try base().filter(key: id).fetchOne(db), invoice.allowedTransitions.contains(status) else { continue }
                let changes = try invoice.changeStatus(to: status, note: "Zmiana zbiorcza z listy faktur.", at: now, device: device)
                try invoice.update(db)
                for change in changes { try InvoiceStatusLogEntry(invoiceID: id, change: change, device: device).insert(db) }
                changed += 1
            }
            return changed
        }
    }

    /// Cofnięcie ostatniej zmiany statusu (np. przypadkowe przesunięcie na liście).
    /// Działa tylko, gdy faktura nadal ma status `expected` — inaczej nic nie zmienia i zwraca false.
    @discardableResult
    public func revertStatus(_ id: UUID, from expected: InvoiceStatus, to previous: InvoiceStatus, now: Date = Date()) throws -> Bool {
        try db.writer.write { db in
            guard var invoice = try base().filter(key: id).fetchOne(db), invoice.status == expected,
                  let change = invoice.forceStatus(previous, note: "Cofnięto zmianę statusu.", at: now, device: device) else { return false }
            try invoice.update(db)
            try InvoiceStatusLogEntry(invoiceID: id, change: change, device: device).insert(db)
            return true
        }
    }

    public func updateNotes(_ id: UUID, notes: String, now: Date = Date()) throws {
        try db.writer.write { db in
            guard var invoice = try base().filter(key: id).fetchOne(db) else { return }
            invoice.notes = notes
            invoice.updatedAt = now
            invoice.updatedByDevice = device
            try invoice.update(db)
        }
    }

    /// Obserwacja listy dla SwiftUI.
    public func observe(_ filter: InvoiceFilter, today: LocalDate = .today()) -> ValueObservation<ValueReducers.Fetch<[Invoice]>> {
        let request = request(filter, today: today)
        return ValueObservation.tracking { try request.fetchAll($0) }
    }
}
