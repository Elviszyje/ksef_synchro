import Foundation
import GRDB

/// Schemat bazy. Zasady:
/// - identyfikatory to UUID w postaci tekstu (łączenie danych między urządzeniami w v2),
/// - każda tabela danych ma `companyId` (gotowość na wiele firm),
/// - kwoty jako INTEGER w groszach (dokładne sumy w SQL, brak błędów zmiennoprzecinkowych),
/// - daty księgowe jako tekst `YYYY-MM-DD`, znaczniki czasu jako DATETIME GRDB,
/// - rekordy edytowalne mają `updatedAt` i `updatedByDevice` (rozstrzyganie konfliktów iCloud).
enum Schema {
    static func v1(_ db: Database) throws {
        try db.create(table: "company") { t in
            t.primaryKey("id", .text)
            t.column("nip", .text).notNull().unique()
            t.column("name", .text).notNull()
            t.column("address", .text).notNull().defaults(to: "")
            t.column("ksefEnvironment", .text).notNull().defaults(to: "test")
            t.column("syncIntervalHours", .integer).notNull().defaults(to: 6)
            t.column("lastSyncAt", .datetime)
            t.column("invoiceNumberPattern", .text).notNull().defaults(to: "FV/{rok}/{nnnn}")
            t.column("defaultPaymentDays", .integer).notNull().defaults(to: 14)
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
            t.column("updatedByDevice", .text).notNull().defaults(to: "")
        }

        try db.create(table: "companyBankAccount") { t in
            t.primaryKey("id", .text)
            t.belongsTo("company", onDelete: .cascade).notNull()
            t.column("accountNumber", .text).notNull()
            t.column("label", .text).notNull().defaults(to: "")
            t.column("isDefault", .boolean).notNull().defaults(to: false)
            t.uniqueKey(["companyId", "accountNumber"])
        }

        try db.create(table: "invoice") { t in
            t.primaryKey("id", .text)
            t.belongsTo("company", onDelete: .cascade).notNull()
            t.column("ksefReferenceNumber", .text).notNull()
            t.column("invoiceNumber", .text).notNull()
            t.column("sellerName", .text).notNull()
            t.column("sellerNip", .text).notNull().indexed()
            t.column("sellerAddress", .text).notNull()
            t.column("buyerNip", .text).notNull()
            t.column("amountNet", .integer).notNull()
            t.column("amountVat", .integer).notNull()
            t.column("amountGross", .integer).notNull()
            t.column("currency", .text).notNull()
            t.column("isSplitPayment", .boolean).notNull()
            t.column("vatAmountSplit", .integer)
            t.column("issueDate", .text).notNull()
            t.column("paymentDueDate", .text)
            t.column("bankAccountNumber", .text).notNull()
            t.column("paymentTitle", .text).notNull()
            t.column("paymentDate", .text)
            t.column("paymentForm", .text).notNull()
            t.column("status", .text).notNull()
            t.column("notes", .text).notNull()
            t.column("invoiceType", .text).notNull()
            t.column("description", .text).notNull()
            t.column("rawXml", .text).notNull()
            t.column("syncedAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
            t.column("updatedByDevice", .text).notNull()
            t.uniqueKey(["companyId", "ksefReferenceNumber"])
        }
        try db.create(index: "invoice_status_issueDate", on: "invoice", columns: ["companyId", "status", "issueDate"])
        try db.create(index: "invoice_due", on: "invoice", columns: ["companyId", "paymentDueDate", "status"])

        try db.create(table: "invoiceStatusLog") { t in
            t.autoIncrementedPrimaryKey("id")
            t.belongsTo("invoice", onDelete: .cascade).notNull()
            t.column("fromStatus", .text).notNull()
            t.column("toStatus", .text).notNull()
            t.column("changedAt", .datetime).notNull()
            t.column("note", .text).notNull()
            t.column("device", .text).notNull()
        }

        try db.create(table: "paymentFile") { t in
            t.primaryKey("id", .text)
            t.belongsTo("company", onDelete: .cascade).notNull()
            t.column("format", .text).notNull()
            t.column("bankKey", .text).notNull()
            t.column("debitAccount", .text).notNull()
            t.column("fileName", .text).notNull()
            t.column("content", .blob).notNull()
            t.column("totalAmount", .integer).notNull()
            t.column("invoiceCount", .integer).notNull()
            t.column("createdAt", .datetime).notNull()
        }

        try db.create(table: "paymentFileItem") { t in
            t.autoIncrementedPrimaryKey("id")
            t.belongsTo("paymentFile", onDelete: .cascade).notNull()
            t.belongsTo("invoice", onDelete: .restrict).notNull()
            t.column("amount", .integer).notNull()
            t.column("lineNumber", .integer).notNull()
            t.uniqueKey(["paymentFileId", "invoiceId"])
        }

        try db.create(table: "bankStatement") { t in
            t.primaryKey("id", .text)
            t.belongsTo("company", onDelete: .cascade).notNull()
            t.column("fileName", .text).notNull()
            t.column("accountNumber", .text).notNull()
            t.column("statementDate", .text)
            t.column("status", .text).notNull()
            t.column("fileFormat", .text).notNull()
            t.column("rawContent", .text).notNull()
            t.column("uploadedAt", .datetime).notNull()
            t.column("confirmedAt", .datetime)
        }

        try db.create(table: "bankTransaction") { t in
            t.primaryKey("id", .text)
            t.belongsTo("bankStatement", onDelete: .cascade).notNull()
            t.column("transactionDate", .text).notNull()
            t.column("valueDate", .text).notNull()
            t.column("amount", .integer).notNull()
            t.column("currency", .text).notNull()
            t.column("isDebit", .boolean).notNull()
            t.column("description", .text).notNull()
            t.column("counterparty", .text).notNull()
            t.column("reference", .text).notNull()
            t.column("isMatched", .boolean).notNull().defaults(to: false)
        }

        try db.create(table: "transactionMatch") { t in
            t.primaryKey("id", .text)
            t.belongsTo("bankTransaction", onDelete: .cascade).notNull()
            t.belongsTo("invoice", onDelete: .cascade).notNull()
            t.column("matchType", .text).notNull()
            t.column("confidence", .text).notNull()
            t.column("isConfirmed", .boolean).notNull().defaults(to: false)
            t.column("confirmedAt", .datetime)
            t.uniqueKey(["bankTransactionId", "invoiceId"])
        }

        try db.create(table: "ksefSyncLog") { t in
            t.primaryKey("id", .text)
            t.belongsTo("company", onDelete: .cascade).notNull()
            t.column("startedAt", .datetime).notNull()
            t.column("finishedAt", .datetime)
            t.column("status", .text).notNull()
            t.column("invoicesFetched", .integer).notNull().defaults(to: 0)
            t.column("invoicesNew", .integer).notNull().defaults(to: 0)
            t.column("errorMessage", .text).notNull().defaults(to: "")
            t.column("currentStage", .text).notNull().defaults(to: "")
        }

        // Kolejka XML do pobrania: KSeF limituje pobieranie XML (ok. 64/h), więc
        // synchronizacja musi być wznawialna między uruchomieniami aplikacji.
        try db.create(table: "ksefXmlQueue") { t in
            t.belongsTo("company", onDelete: .cascade).notNull()
            t.column("ksefNumber", .text).notNull()
            t.column("enqueuedAt", .datetime).notNull()
            t.column("attempts", .integer).notNull().defaults(to: 0)
            t.column("notBefore", .datetime)
            t.primaryKey(["companyId", "ksefNumber"])
        }

        try db.create(table: "buyer") { t in
            t.primaryKey("id", .text)
            t.belongsTo("company", onDelete: .cascade).notNull()
            t.column("nip", .text).notNull()
            t.column("name", .text).notNull()
            t.column("address", .text).notNull()
            t.column("email", .text).notNull().defaults(to: "")
            t.column("phone", .text).notNull().defaults(to: "")
            t.column("notes", .text).notNull().defaults(to: "")
            t.column("updatedAt", .datetime).notNull()
            t.column("updatedByDevice", .text).notNull().defaults(to: "")
            t.uniqueKey(["companyId", "nip"])
        }

        try db.create(table: "outgoingInvoice") { t in
            t.primaryKey("id", .text)
            t.belongsTo("company", onDelete: .cascade).notNull()
            t.belongsTo("buyer", onDelete: .setNull)
            t.column("invoiceNumber", .text).notNull()
            t.column("issueDate", .text).notNull()
            t.column("deliveryDate", .text)
            t.column("paymentDueDate", .text).notNull()
            t.column("paymentForm", .text).notNull()
            t.column("currency", .text).notNull().defaults(to: "PLN")
            t.column("bankAccountNumber", .text).notNull().defaults(to: "")
            t.column("buyerNip", .text).notNull()
            t.column("buyerName", .text).notNull()
            t.column("buyerAddress", .text).notNull()
            t.column("notes", .text).notNull().defaults(to: "")
            t.column("status", .text).notNull()
            t.column("ksefSessionReference", .text).notNull().defaults(to: "")
            t.column("ksefInvoiceReference", .text).notNull().defaults(to: "")
            t.column("ksefNumber", .text).notNull().defaults(to: "")
            t.column("generatedXml", .text).notNull().defaults(to: "")
            t.column("upoXml", .text).notNull().defaults(to: "")
            t.column("errorMessage", .text).notNull().defaults(to: "")
            t.column("environment", .text).notNull()
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
            t.column("updatedByDevice", .text).notNull().defaults(to: "")
            t.uniqueKey(["companyId", "environment", "invoiceNumber"])
        }

        try db.create(table: "outgoingInvoiceItem") { t in
            t.autoIncrementedPrimaryKey("id")
            t.belongsTo("outgoingInvoice", onDelete: .cascade).notNull()
            t.column("lp", .integer).notNull()
            t.column("name", .text).notNull()
            t.column("unit", .text).notNull()
            t.column("quantity", .text).notNull()       // Decimal(10,3) jako tekst
            t.column("unitPriceNet", .integer).notNull()
            t.column("vatRate", .text).notNull()
            t.column("amountNet", .integer).notNull()
            t.column("amountVat", .integer).notNull()
            t.column("amountGross", .integer).notNull()
        }

        // Stan lustra iCloud: co i w jakiej wersji zapisaliśmy do katalogu.
        try db.create(table: "cloudMirrorState") { t in
            t.column("path", .text).notNull().primaryKey()
            t.column("recordType", .text).notNull()
            t.column("recordId", .text).notNull()
            t.column("recordUpdatedAt", .datetime).notNull()
            t.column("contentHash", .text).notNull()
            t.column("writtenAt", .datetime).notNull()
        }
    }

    /// v2: podstawa zwolnienia z VAT na fakturze sprzedażowej i katalog pozycji.
    static func v2(_ db: Database) throws {
        try db.alter(table: "outgoingInvoice") { t in
            t.add(column: "vatExemptionType", .text).notNull().defaults(to: "ustawa")
            t.add(column: "vatExemptionBasis", .text).notNull().defaults(to: "")
        }
        try db.create(table: "catalogItem") { t in
            t.primaryKey("id", .text)
            t.belongsTo("company", onDelete: .cascade).notNull()
            t.column("name", .text).notNull()
            t.column("unit", .text).notNull()
            t.column("unitPriceNet", .integer).notNull()
            t.column("vatRate", .text).notNull()
            t.column("useCount", .integer).notNull().defaults(to: 0)
            t.column("lastUsedAt", .datetime)
            t.column("updatedAt", .datetime).notNull()
            t.column("updatedByDevice", .text).notNull().defaults(to: "")
            t.uniqueKey(["companyId", "name", "unit"])
        }
    }
}
