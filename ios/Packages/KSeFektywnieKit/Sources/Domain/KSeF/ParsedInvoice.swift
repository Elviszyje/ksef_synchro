import Foundation

/// Wynik parsowania XML FA lub metadanych KSeF (port `ParsedInvoice`).
/// Daty pozostają tekstem — tak jak w Pythonie, konwersja następuje przy mapowaniu.
public struct ParsedInvoice: Hashable, Sendable {
    public var invoiceNumber = ""
    public var ksefReferenceNumber = ""
    public var issueDate: String?
    public var paymentDueDate: String?

    public var sellerName = ""
    public var sellerNIP = ""
    public var sellerAddress = ""
    public var buyerNIP = ""

    public var amountNet: Decimal = 0
    public var amountVAT: Decimal = 0
    public var amountGross: Decimal = 0
    public var currency = "PLN"

    public var invoiceType = ""
    public var description = ""

    public var isSplitPayment = false
    public var vatAmountSplit: Decimal?

    public var bankAccountNumber = ""
    public var paymentTitle = ""

    public var isPaid = false
    public var paymentDate: String?
    public var paymentForm = ""

    public var rawXML = ""

    public init(ksefReferenceNumber: String = "") {
        self.ksefReferenceNumber = ksefReferenceNumber
    }
}

/// Pozycja faktury (`FaWiersz`) w postaci tekstowej, do wyświetlenia w szczególe.
public struct InvoiceLineItem: Hashable, Sendable, Codable {
    public var nr: String
    public var name: String
    public var unit: String
    public var qty: String
    public var unitPrice: String
    public var netValue: String
    public var vatRate: String
}
