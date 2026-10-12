import Foundation

/// mBank VideoTel (.txt): separator `;`, CP1250, bez nagłówka.
/// Pola: RachWN;RachMA;Kwota;Nazwa;Adres1;Adres2;Tytuł;Typ (0 = Elixir).
public struct MBankGenerator: PaymentFileGenerator {
    let debitAccount: String

    public init(payer: PaymentPayer) {
        debitAccount = payer.debitAccount.replacingOccurrences(of: " ", with: "")
    }

    public func lines(for invoice: Invoice, executionDate: LocalDate) -> [String] {
        [[
            debitAccount,
            invoice.bankAccountNumber.replacingOccurrences(of: " ", with: ""),
            PaymentText.formatAmount(invoice.amountGross),
            PaymentText.clean(invoice.sellerName, maxLength: 35),
            PaymentText.clean(invoice.sellerAddress.nonEmpty ?? "NIP \(invoice.sellerNIP)", maxLength: 35),
            "",
            PaymentText.clean("Faktura \(invoice.invoiceNumber)", maxLength: 105),
            "0",
        ].joined(separator: ";")]
    }
}
