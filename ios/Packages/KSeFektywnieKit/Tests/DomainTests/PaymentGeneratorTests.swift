import Foundation
import Testing
@testable import Domain

@Suite("Pliki przelewów bajt w bajt zgodne z Django")
struct PaymentGeneratorTests {
    struct Spec {
        let payer: PaymentPayer
        let date: LocalDate
        let invoices: [Invoice]
    }

    static func spec() throws -> Spec {
        let json = try Fixtures.json("input/payments/invoices.json") as! [String: Any]
        let company = json["company"] as! [String: String]
        let invoices = (json["invoices"] as! [[String: Any]]).map { raw in
            Invoice(
                companyID: UUID(), ksefReferenceNumber: "", invoiceNumber: raw["invoice_number"] as! String,
                sellerName: raw["seller_name"] as! String, sellerNIP: raw["seller_nip"] as! String,
                sellerAddress: raw["seller_address"] as! String,
                amountVAT: DecimalText.parse(raw["amount_vat"] as! String)!,
                amountGross: DecimalText.parse(raw["amount_gross"] as! String)!,
                isSplitPayment: raw["is_split_payment"] as! Bool,
                vatAmountSplit: (raw["vat_amount_split"] as? String).flatMap(DecimalText.parse),
                issueDate: LocalDate(year: 2026, month: 1, day: 1)!,
                bankAccountNumber: raw["bank_account_number"] as! String)
        }
        return Spec(payer: PaymentPayer(debitAccount: company["debit_account"]!, name: company["name"]!, address: company["address"]!),
                    date: LocalDate(iso: json["execution_date"] as! String)!, invoices: invoices)
    }

    @Test("Erste Bank i mBank", arguments: [PaymentFileFormat.erste, .mbank])
    func nativeFormats(_ format: PaymentFileFormat) throws {
        let s = try Self.spec()
        let actual = format.generator(payer: s.payer).generate(s.invoices, executionDate: s.date)
        let expected = try Fixtures.data("expected/payments/\(format.rawValue).\(format.fileExtension)")
        #expect(actual == expected, "\(CP1250.decode(actual) ?? "")")
    }

    /// Kwota VAT w tytule MPP zachowuje przecinek (`format_danych.pdf`, s. 15–17).
    @Test("Elixir-0")
    func elixir() throws {
        let s = try Self.spec()
        let actual = PaymentFileFormat.elixir.generator(payer: s.payer).generate(s.invoices, executionDate: s.date)
        let expected = try Fixtures.data("expected/payments/elixir.pli")
        #expect(actual == expected, "\(CP1250.decode(actual) ?? "")")
        #expect(CP1250.decode(actual)?.contains("/VAT/4600,00/") == true)
    }

    @Test("Nazwa pliku jak w Django")
    func fileName() {
        let d = LocalDate(year: 2026, month: 10, day: 11)!
        #expect(PaymentFileFormat.fileName(bankKey: "erste", date: d) == "przelewy_20261011_Erste_Bank.txt")
        #expect(PaymentFileFormat.fileName(bankKey: "pko_bp", date: d) == "przelewy_20261011_PKO_BP.pli")
        #expect(PaymentFileFormat.fileName(bankKey: "hsbc", date: d) == "przelewy_20261011_Przelew.pli")
    }
}
