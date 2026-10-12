import Foundation
import GRDB
import Domain

// Mapowanie modeli Domain na wiersze SQLite. Jawne (bez Codable), bo kwoty
// w bazie są w groszach, a daty księgowe jako `YYYY-MM-DD`.

extension LocalDate: DatabaseValueConvertible {
    public var databaseValue: DatabaseValue { iso.databaseValue }
    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> LocalDate? {
        String.fromDatabaseValue(dbValue).flatMap(LocalDate.init(iso:))
    }
}

enum Money {
    static func db(_ value: Decimal) -> Int64 { value.minorUnits }
    static func db(_ value: Decimal?) -> Int64? { value?.minorUnits }
    static func decimal(_ value: Int64) -> Decimal { Decimal(minorUnits: value) }
    static func decimal(_ value: Int64?) -> Decimal? { value.map(Decimal.init(minorUnits:)) }
}

extension Company: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "company"

    public init(row: Row) throws {
        self.init(
            id: row["id"], nip: row["nip"], name: row["name"], address: row["address"],
            ksefEnvironment: KSeFEnvironment(rawValue: row["ksefEnvironment"]) ?? .test,
            syncIntervalHours: row["syncIntervalHours"], lastSyncAt: row["lastSyncAt"],
            invoiceNumberPattern: row["invoiceNumberPattern"], defaultPaymentDays: row["defaultPaymentDays"],
            createdAt: row["createdAt"], updatedAt: row["updatedAt"], updatedByDevice: row["updatedByDevice"])
    }

    public func encode(to c: inout PersistenceContainer) throws {
        c["id"] = id
        c["nip"] = nip
        c["name"] = name
        c["address"] = address
        c["ksefEnvironment"] = ksefEnvironment.rawValue
        c["syncIntervalHours"] = syncIntervalHours
        c["lastSyncAt"] = lastSyncAt
        c["invoiceNumberPattern"] = invoiceNumberPattern
        c["defaultPaymentDays"] = defaultPaymentDays
        c["createdAt"] = createdAt
        c["updatedAt"] = updatedAt
        c["updatedByDevice"] = updatedByDevice
    }
}

extension CompanyBankAccount: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "companyBankAccount"

    public init(row: Row) throws {
        self.init(id: row["id"], companyID: row["companyId"], accountNumber: row["accountNumber"],
                  label: row["label"], isDefault: row["isDefault"])
    }

    public func encode(to c: inout PersistenceContainer) throws {
        c["id"] = id
        c["companyId"] = companyID
        c["accountNumber"] = accountNumber
        c["label"] = label
        c["isDefault"] = isDefault
    }
}

extension Invoice: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "invoice"

    public init(row: Row) throws {
        self.init(
            id: row["id"], companyID: row["companyId"],
            ksefReferenceNumber: row["ksefReferenceNumber"], invoiceNumber: row["invoiceNumber"],
            sellerName: row["sellerName"], sellerNIP: row["sellerNip"], sellerAddress: row["sellerAddress"], buyerNIP: row["buyerNip"],
            amountNet: Money.decimal(row["amountNet"] as Int64), amountVAT: Money.decimal(row["amountVat"] as Int64),
            amountGross: Money.decimal(row["amountGross"] as Int64), currency: row["currency"],
            isSplitPayment: row["isSplitPayment"], vatAmountSplit: Money.decimal(row["vatAmountSplit"] as Int64?),
            issueDate: row["issueDate"], paymentDueDate: row["paymentDueDate"],
            bankAccountNumber: row["bankAccountNumber"], paymentTitle: row["paymentTitle"],
            paymentDate: row["paymentDate"], paymentForm: row["paymentForm"],
            status: InvoiceStatus(rawValue: row["status"]) ?? .new, notes: row["notes"],
            invoiceType: row["invoiceType"], description: row["description"], rawXML: row["rawXml"],
            syncedAt: row["syncedAt"], updatedAt: row["updatedAt"], updatedByDevice: row["updatedByDevice"])
    }

    public func encode(to c: inout PersistenceContainer) throws {
        c["id"] = id
        c["companyId"] = companyID
        c["ksefReferenceNumber"] = ksefReferenceNumber
        c["invoiceNumber"] = invoiceNumber
        c["sellerName"] = sellerName
        c["sellerNip"] = sellerNIP
        c["sellerAddress"] = sellerAddress
        c["buyerNip"] = buyerNIP
        c["amountNet"] = Money.db(amountNet)
        c["amountVat"] = Money.db(amountVAT)
        c["amountGross"] = Money.db(amountGross)
        c["currency"] = currency
        c["isSplitPayment"] = isSplitPayment
        c["vatAmountSplit"] = Money.db(vatAmountSplit)
        c["issueDate"] = issueDate
        c["paymentDueDate"] = paymentDueDate
        c["bankAccountNumber"] = bankAccountNumber
        c["paymentTitle"] = paymentTitle
        c["paymentDate"] = paymentDate
        c["paymentForm"] = paymentForm
        c["status"] = status.rawValue
        c["notes"] = notes
        c["invoiceType"] = invoiceType
        c["description"] = description
        c["rawXml"] = rawXML
        c["syncedAt"] = syncedAt
        c["updatedAt"] = updatedAt
        c["updatedByDevice"] = updatedByDevice
    }
}

/// Wpis historii statusu z identyfikatorem faktury.
public struct InvoiceStatusLogEntry: Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "invoiceStatusLog"
    public var invoiceID: UUID
    public var change: InvoiceStatusChange
    public var device: String

    public init(invoiceID: UUID, change: InvoiceStatusChange, device: String) {
        self.invoiceID = invoiceID
        self.change = change
        self.device = device
    }

    public init(row: Row) throws {
        invoiceID = row["invoiceId"]
        change = InvoiceStatusChange(from: InvoiceStatus(rawValue: row["fromStatus"]) ?? .new,
                                     to: InvoiceStatus(rawValue: row["toStatus"]) ?? .new,
                                     at: row["changedAt"], note: row["note"])
        device = row["device"]
    }

    public func encode(to c: inout PersistenceContainer) throws {
        c["invoiceId"] = invoiceID
        c["fromStatus"] = change.from.rawValue
        c["toStatus"] = change.to.rawValue
        c["changedAt"] = change.at
        c["note"] = change.note
        c["device"] = device
    }
}
