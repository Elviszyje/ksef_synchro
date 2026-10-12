import Foundation

/// Faktura kosztowa (odpowiednik `apps.invoices.models.Invoice`).
///
/// Identyfikator to UUID, a nie autoinkrement: rekordy będą kiedyś łączone
/// między urządzeniami przez katalog iCloud.
public struct Invoice: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var companyID: UUID

    public var ksefReferenceNumber: String
    public var invoiceNumber: String

    public var sellerName: String
    public var sellerNIP: String
    public var sellerAddress: String
    public var buyerNIP: String

    public var amountNet: Decimal
    public var amountVAT: Decimal
    public var amountGross: Decimal
    public var currency: String

    public var isSplitPayment: Bool
    public var vatAmountSplit: Decimal?

    public var issueDate: LocalDate
    public var paymentDueDate: LocalDate?

    public var bankAccountNumber: String
    public var paymentTitle: String
    public var paymentDate: LocalDate?
    public var paymentForm: String

    public var status: InvoiceStatus
    public var notes: String
    public var invoiceType: String
    public var description: String
    public var rawXML: String

    public var syncedAt: Date
    public var updatedAt: Date
    /// Urządzenie, które ostatnio zmieniło rekord (rozstrzyganie konfliktów iCloud w v2).
    public var updatedByDevice: String

    public init(
        id: UUID = UUID(), companyID: UUID, ksefReferenceNumber: String, invoiceNumber: String,
        sellerName: String = "", sellerNIP: String = "", sellerAddress: String = "", buyerNIP: String = "",
        amountNet: Decimal = 0, amountVAT: Decimal = 0, amountGross: Decimal = 0, currency: String = "PLN",
        isSplitPayment: Bool = false, vatAmountSplit: Decimal? = nil,
        issueDate: LocalDate, paymentDueDate: LocalDate? = nil,
        bankAccountNumber: String = "", paymentTitle: String = "", paymentDate: LocalDate? = nil, paymentForm: String = "",
        status: InvoiceStatus = .new, notes: String = "", invoiceType: String = "", description: String = "", rawXML: String = "",
        syncedAt: Date = Date(), updatedAt: Date = Date(), updatedByDevice: String = ""
    ) {
        self.id = id
        self.companyID = companyID
        self.ksefReferenceNumber = ksefReferenceNumber
        self.invoiceNumber = invoiceNumber
        self.sellerName = sellerName
        self.sellerNIP = sellerNIP
        self.sellerAddress = sellerAddress
        self.buyerNIP = buyerNIP
        self.amountNet = amountNet
        self.amountVAT = amountVAT
        self.amountGross = amountGross
        self.currency = currency
        self.isSplitPayment = isSplitPayment
        self.vatAmountSplit = vatAmountSplit
        self.issueDate = issueDate
        self.paymentDueDate = paymentDueDate
        self.bankAccountNumber = bankAccountNumber
        self.paymentTitle = paymentTitle
        self.paymentDate = paymentDate
        self.paymentForm = paymentForm
        self.status = status
        self.notes = notes
        self.invoiceType = invoiceType
        self.description = description
        self.rawXML = rawXML
        self.syncedAt = syncedAt
        self.updatedAt = updatedAt
        self.updatedByDevice = updatedByDevice
    }

    public var isCorrection: Bool { invoiceType == "KOR" || amountGross < 0 }

    public func isOverdue(today: LocalDate) -> Bool {
        guard let due = paymentDueDate, status != .paid, status != .sentForPayment else { return false }
        return due < today
    }

    public var canBeSelectedForPayment: Bool { status == .accepted && !bankAccountNumber.isEmpty }

    public var allowedTransitions: [InvoiceStatus] {
        InvoiceStatusRules.allowedTransitions(isCorrection: isCorrection, from: status)
    }

    /// Zmiana statusu z walidacją (port `_apply_status_change` + sprawdzenia z widoku).
    /// Zwraca wpisy historii; zaakceptowana korekta przechodzi od razu w `oplacona`.
    @discardableResult
    public mutating func changeStatus(to newStatus: InvoiceStatus, note: String = "", at now: Date = Date(), device: String = "") throws -> [InvoiceStatusChange] {
        guard allowedTransitions.contains(newStatus) else {
            throw InvoiceStatusError.transitionNotAllowed(from: status, to: newStatus)
        }
        var log = [InvoiceStatusChange(from: status, to: newStatus, at: now, note: note)]
        status = newStatus
        if isCorrection && newStatus == .accepted {
            log.append(InvoiceStatusChange(from: .accepted, to: .paid, at: now,
                                           note: "Korekta — automatycznie oznaczona jako opłacona."))
            status = .paid
        }
        updatedAt = now
        updatedByDevice = device
        return log
    }

    /// Zmiana statusu wynikająca z działania systemu (plik przelewów, wyciąg),
    /// bez reguł przejść — odpowiednik bezpośrednich zapisów w widokach Django.
    @discardableResult
    public mutating func forceStatus(_ newStatus: InvoiceStatus, note: String, at now: Date = Date(), device: String = "") -> InvoiceStatusChange? {
        guard newStatus != status else { return nil }
        let change = InvoiceStatusChange(from: status, to: newStatus, at: now, note: note)
        status = newStatus
        updatedAt = now
        updatedByDevice = device
        return change
    }
}
