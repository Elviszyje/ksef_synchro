import Foundation

/// Mapowanie wyników KSeF na fakturę — port pomocników z `apps/ksef/tasks.py`.
public enum InvoiceMapping {
    /// `_parsed_from_metadata`: faktura z metadanych zapytania, gdy XML jest niedostępny.
    public static func parsed(fromMetadata header: JSONValue, buyerNIPFallback: String = "") -> ParsedInvoice {
        let ref = JSONValue.firstTruthy(header["ksefNumber"], header["ksefReferenceNumber"]).stringValue
        let number = JSONValue.firstTruthy(header["invoiceNumber"], header["invoiceNo"]).stringValue

        let subjectBy = JSONValue.firstTruthy(header["subjectBy"], header["seller"])
        let identBy = JSONValue.firstTruthy(subjectBy["identifier"], subjectBy["subjectIdentifier"])
        let sellerNIP = JSONValue.firstTruthy(subjectBy["nip"], identBy["identifier"], identBy["value"]).stringValue
        let sellerName = JSONValue.firstTruthy(subjectBy["subjectName"], subjectBy["name"],
                                               subjectBy["fullName"], subjectBy["tradeName"]).stringValue

        let subjectTo = JSONValue.firstTruthy(header["subjectTo"], header["buyer"])
        let identTo = JSONValue.firstTruthy(subjectTo["identifier"], subjectTo["subjectIdentifier"])
        let buyerNIP = JSONValue.firstTruthy(subjectTo["nip"], identTo["identifier"], identTo["value"]).stringValue.nonEmpty ?? buyerNIPFallback

        func amount(_ keys: String...) -> Decimal {
            keys.lazy.map { header[$0] }.first(where: \.isTruthy)?.decimalValue ?? 0
        }

        var parsed = ParsedInvoice(ksefReferenceNumber: ref)
        parsed.invoiceNumber = number.nonEmpty ?? ref
        parsed.sellerNIP = sellerNIP
        parsed.sellerName = sellerName
        parsed.buyerNIP = buyerNIP
        parsed.issueDate = header["invoiceIssueDate"].stringValue
        parsed.amountGross = amount("gross", "grossAmount", "grossValue")
        parsed.amountNet = amount("net", "netAmount", "netValue")
        parsed.amountVAT = amount("vat", "vatAmount", "vatValue")
        parsed.currency = JSONValue.firstTruthy(header["currency"], header["currencyCode"]).stringValue.nonEmpty ?? "PLN"
        parsed.paymentTitle = number.isEmpty ? "Faktura \(ref)" : "Faktura \(number)"
        return parsed
    }

    /// `_parsed_to_invoice_fields`: nowa faktura z wyniku parsowania.
    public static func invoice(from parsed: ParsedInvoice, companyID: UUID, today: LocalDate, now: Date = Date(), device: String = "") -> Invoice {
        Invoice(
            companyID: companyID,
            ksefReferenceNumber: parsed.ksefReferenceNumber,
            invoiceNumber: parsed.invoiceNumber.nonEmpty ?? parsed.ksefReferenceNumber,
            sellerName: parsed.sellerName.nonEmpty ?? parsed.sellerNIP.nonEmpty ?? unknownSeller,
            sellerNIP: parsed.sellerNIP,
            sellerAddress: parsed.sellerAddress,
            buyerNIP: parsed.buyerNIP,
            amountNet: parsed.amountNet,
            amountVAT: parsed.amountVAT,
            amountGross: parsed.amountGross,
            currency: PyText.strip(PyText.prefix(parsed.currency.nonEmpty ?? "PLN", 3)).uppercased(),
            isSplitPayment: parsed.isSplitPayment,
            vatAmountSplit: parsed.vatAmountSplit,
            issueDate: date(parsed.issueDate) ?? today,
            paymentDueDate: date(parsed.paymentDueDate),
            bankAccountNumber: parsed.bankAccountNumber,
            paymentTitle: parsed.paymentTitle,
            paymentDate: date(parsed.paymentDate),
            paymentForm: parsed.paymentForm,
            status: parsed.isPaid ? .paid : .new,
            invoiceType: parsed.invoiceType,
            description: parsed.description,
            rawXML: parsed.rawXML,
            syncedAt: now,
            updatedAt: now,
            updatedByDevice: device
        )
    }

    public static let unknownSeller = "Nieznany sprzedawca"

    /// `_update_invoice_from_api`: aktualizacja istniejącej faktury nowymi danymi z KSeF.
    /// Zachowuje status i notatki użytkownika; pól z XML nie nadpisuje pustymi wartościami.
    public static func merge(_ incoming: Invoice, into existing: inout Invoice, now: Date = Date(), device: String = "") -> InvoiceStatusChange? {
        existing.invoiceNumber = incoming.invoiceNumber
        existing.sellerNIP = incoming.sellerNIP
        existing.buyerNIP = incoming.buyerNIP
        existing.amountGross = incoming.amountGross
        existing.currency = incoming.currency
        existing.issueDate = incoming.issueDate
        existing.paymentTitle = incoming.paymentTitle

        if incoming.amountNet != 0 { existing.amountNet = incoming.amountNet }
        if incoming.amountVAT != 0 { existing.amountVAT = incoming.amountVAT }
        if let v = incoming.paymentDueDate { existing.paymentDueDate = v }
        if !incoming.bankAccountNumber.isEmpty { existing.bankAccountNumber = incoming.bankAccountNumber }
        if !incoming.sellerAddress.isEmpty { existing.sellerAddress = incoming.sellerAddress }
        if !incoming.rawXML.isEmpty { existing.rawXML = incoming.rawXML }
        if incoming.isSplitPayment { existing.isSplitPayment = true }
        if let v = incoming.vatAmountSplit, v != 0 { existing.vatAmountSplit = v }
        if !incoming.invoiceType.isEmpty { existing.invoiceType = incoming.invoiceType }
        if !incoming.description.isEmpty { existing.description = incoming.description }
        if let v = incoming.paymentDate { existing.paymentDate = v }
        if !incoming.paymentForm.isEmpty { existing.paymentForm = incoming.paymentForm }
        if !incoming.sellerName.isEmpty && incoming.sellerName != unknownSeller { existing.sellerName = incoming.sellerName }

        existing.updatedAt = now
        existing.updatedByDevice = device
        if incoming.paymentDate != nil && existing.status != .paid {
            return existing.forceStatus(.paid, note: "KSeF: faktura oznaczona w XML jako zapłacona.", at: now, device: device)
        }
        return nil
    }

    static func date(_ text: String?) -> LocalDate? {
        guard let text, !text.isEmpty else { return nil }
        return LocalDate(iso: PyText.prefix(text, 10))
    }
}
