import Foundation

/// Wygenerowany plik przelewów (historia paczek).
public struct PaymentFile: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var companyID: UUID
    public var format: PaymentFileFormat
    public var bankKey: String
    public var debitAccount: String
    public var fileName: String
    public var content: Data
    public var totalAmount: Decimal
    public var invoiceCount: Int
    public var createdAt: Date

    public init(id: UUID = UUID(), companyID: UUID, format: PaymentFileFormat, bankKey: String, debitAccount: String,
                fileName: String, content: Data, totalAmount: Decimal, invoiceCount: Int, createdAt: Date = Date()) {
        self.id = id
        self.companyID = companyID
        self.format = format
        self.bankKey = bankKey
        self.debitAccount = debitAccount
        self.fileName = fileName
        self.content = content
        self.totalAmount = totalAmount
        self.invoiceCount = invoiceCount
        self.createdAt = createdAt
    }
}

public enum PaymentFileError: Error, Equatable, LocalizedError {
    case noInvoices
    case invoiceNotPayable(invoiceNumber: String)
    case paidInvoiceInBatch

    public var errorDescription: String? {
        switch self {
        case .noInvoices: "Nie wybrano faktur."
        case .invoiceNotPayable(let n): "Faktura \(n) nie jest zaakceptowana lub nie ma numeru rachunku."
        case .paidInvoiceInBatch: "Nie można zresetować paczki — co najmniej jedna faktura ma status \"Opłacona\"."
        }
    }
}
