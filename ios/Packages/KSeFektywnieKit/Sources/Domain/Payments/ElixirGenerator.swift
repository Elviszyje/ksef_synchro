import Foundation

/// Elixir-0 (.pli): separator `,`, pola tekstowe w cudzysłowach, kwoty w groszach, CP1250.
/// Specyfikacja: `format_danych.pdf`, strony 13–17.
public struct ElixirGenerator: PaymentFileGenerator {
    let debitAccount: String
    let senderName: String

    public init(payer: PaymentPayer) {
        debitAccount = payer.debitAccount.replacingOccurrences(of: " ", with: "")
        let name = PyText.prefix(payer.name, 35)
        let address = PyText.prefix(payer.address, 35)
        senderName = PaymentText.clean("\(name) \(address)", maxLength: 140)
    }

    public func lines(for invoice: Invoice, executionDate: LocalDate) -> [String] {
        let receiver = PaymentText.clean("\(invoice.sellerName) \(invoice.sellerAddress)", maxLength: 140)
        let title: String
        let nip: String
        if invoice.isSplitPayment {
            // Kwota VAT zachowuje przecinek (`/VAT/23,09/`, `format_danych.pdf` s. 15–17);
            // przecinki usuwamy tylko z reszty tytułu. Pole jest w cudzysłowach.
            let (vat, rest) = PaymentText.splitPaymentTitle(invoice)
            let full = PyText.prefix(vat + rest, 140)
            let vatPart = PyText.prefix(full, vat.unicodeScalars.count)
            let restPart = String(String.UnicodeScalarView(full.unicodeScalars.dropFirst(vat.unicodeScalars.count)))
            title = "\"" + vatPart.replacingOccurrences(of: "\"", with: "") + Self.unquotable(restPart) + "\""
            nip = "\"\(invoice.sellerNIP)\""
        } else {
            title = Self.quote(PaymentText.clean("Faktura \(invoice.invoiceNumber)", maxLength: 140))
            nip = invoice.sellerNIP.isEmpty ? "\"\"" : "\"\(invoice.sellerNIP)\""
        }
        return [[
            "",
            executionDate.compact,
            String(invoice.amountGross.minorUnits),
            "", "",
            "\"\(debitAccount)\"",
            "\"\(invoice.bankAccountNumber)\"",
            Self.quote(senderName),
            Self.quote(receiver),
            "", "",
            title,
            "", "", "", "",
            nip,
        ].joined(separator: ",")]
    }

    /// `_q`: usuwa cudzysłowy i przecinki, opakowuje w cudzysłowy.
    static func quote(_ text: String) -> String { "\"" + unquotable(text) + "\"" }

    static func unquotable(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: ",", with: "")
    }
}
