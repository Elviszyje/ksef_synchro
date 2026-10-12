import Foundation

/// Erste Bank Polska (.txt): separator `|`, nagłówek `4120414|1`, CP1250.
/// Typ 1 — przelew zwykły, typ 6 — MPP. Specyfikacja: `format_danych.pdf`.
public struct ErsteBankGenerator: PaymentFileGenerator {
    let debitAccount: String

    public init(payer: PaymentPayer) {
        debitAccount = payer.debitAccount.replacingOccurrences(of: " ", with: "")
    }

    public func headerLines() -> [String] { ["4120414|1"] }

    public func lines(for invoice: Invoice, executionDate: LocalDate) -> [String] {
        let name = PaymentText.clean(invoice.sellerName, maxLength: 80)
        let address = PaymentText.clean(invoice.sellerAddress.nonEmpty ?? "NIP \(invoice.sellerNIP)", maxLength: 60)
        let amount = PaymentText.formatAmount(invoice.amountGross)

        if invoice.isSplitPayment {
            let (vat, rest) = PaymentText.splitPaymentTitle(invoice)
            let title = PyText.prefix(vat + rest, 140)
            return [["6", debitAccount, invoice.bankAccountNumber, name, address, amount, "1", title, "", ""].joined(separator: "|")]
        }
        let title = PaymentText.clean("Faktura \(invoice.invoiceNumber)", maxLength: 140)
        return [["1", debitAccount, invoice.bankAccountNumber, name, address, amount, "1", title, "", invoice.sellerNIP, ""].joined(separator: "|")]
    }
}
