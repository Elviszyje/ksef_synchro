import Foundation
import Testing
@testable import Domain

@Suite("Wizualizacja faktury: treść, kwota słownie, kod QR")
struct VisualizationTests {
    func document(_ fixture: String) throws -> InvoiceDocument {
        let xml = String(decoding: try Fixtures.data("input/fa/\(fixture)"), as: UTF8.self)
        return try #require(InvoiceDocument.parse(xml: xml))
    }

    @Test("Podsumowanie stawek z pól P_13/P_14, suma z P_15")
    func mixedRates() throws {
        let doc = try document("fa3_mixed_rates.xml")
        #expect(doc.number == "FV/MIX/1")
        #expect(doc.issueDate == LocalDate(year: 2026, month: 10, day: 1))
        #expect(doc.seller.name == "Hurtownia Mieszana" && doc.seller.nip == "6260181591")
        #expect(doc.buyer.name == "Moja Firma" && doc.buyer.nip == "1111111111")
        #expect(doc.vatSummary.map(\.rate) == [.rate("23"), .rate("8"), .zeroDomestic, .exempt, .notSubjectAbroad, .reverseCharge, .margin])
        #expect(doc.vatSummary[0].gross == DecimalText.parse("123.00"))
        #expect(doc.totalNet == DecimalText.parse("265.00"))
        #expect(doc.totalVAT == DecimalText.parse("27.00"))
        #expect(doc.totalGross == DecimalText.parse("292.00"))
    }

    @Test("Korekta bez sum: podsumowanie z pozycji, osoba fizyczna jako sprzedawca, zapłacona kartą")
    func correction() throws {
        let doc = try document("fa3_correction_person.xml")
        #expect(doc.kind == .correction && doc.kind.isCorrection)
        #expect(doc.seller.name == "Jan Kowalski")
        #expect(doc.currency == "EUR")
        #expect(doc.vatSummary == [VATSummaryRow(rate: .rate("23"), net: -100, vat: -23)])
        #expect(doc.totalGross == -123)
        #expect(doc.payment.isPaid && doc.payment.paidDate == LocalDate(year: 2026, month: 10, day: 6))
        #expect(doc.payment.formCode == "2")
        #expect(doc.payment.bankAccounts.map(\.number) == ["DE89370400440532013000"])
    }

    @Test("Adnotacje: MPP z FA(2) i podzielona płatność")
    func splitPayment() throws {
        #expect(try document("fa3_split_payment.xml").isSplitPayment)
    }

    @Test("Faktura sprzedażowa: szkic z XML wygenerowanym w locie, przyjęta z kodem QR")
    func sales() throws {
        let seller = FA3Seller(nip: "1111111111", name: "Firma Demo Sp. z o.o.", address: "ul. Testowa 10\n00-950 Warszawa")
        var invoice = OutgoingInvoice(
            companyID: UUID(), invoiceNumber: "FV/2026/0003", issueDate: LocalDate(year: 2026, month: 10, day: 13)!,
            deliveryDate: LocalDate(year: 2026, month: 10, day: 10), paymentDueDate: LocalDate(year: 2026, month: 10, day: 27)!,
            bankAccountNumber: "61109010140000071219812874", buyerNIP: "6260181591", buyerName: "Hurtownia Ołówek",
            buyerAddress: "ul. Przykładowa 1\n00-001 Warszawa", exemptionBasis: "art. 43 ust. 1 pkt 29 lit. a ustawy o VAT",
            items: [OutgoingInvoiceItem(name: "Konsultacje IT", unit: "h", quantity: DecimalText.parse("1.5")!, unitPriceNet: 200),
                    OutgoingInvoiceItem(name: "Szkolenie", unit: "os.", quantity: 2, unitPriceNet: 350, vatRate: .exempt)])

        let draft = try InvoiceVisualization.sales(invoice, seller: seller)
        #expect(draft.isDraft)
        #expect(draft.document.verificationURL == nil)
        let doc = draft.document
        #expect(doc.seller.addressLines == ["ul. Testowa 10", "00-950 Warszawa"])
        #expect(doc.buyer.name == "Hurtownia Ołówek")
        #expect(doc.saleDate == LocalDate(year: 2026, month: 10, day: 10))
        #expect(doc.lines.map(\.name) == ["Konsultacje IT", "Szkolenie"])
        #expect(doc.lines[0].quantity == DecimalText.parse("1.5") && doc.lines[0].net == 300 && doc.lines[1].vatRate == "zw")
        #expect(doc.vatSummary.map(\.rate) == [.rate("23"), .exempt])
        #expect(doc.totalGross == invoice.amountGross)
        #expect(doc.annotations == [.exemption(basis: "art. 43 ust. 1 pkt 29 lit. a ustawy o VAT")])
        #expect(doc.payment.dueDates == [invoice.paymentDueDate] && doc.payment.formCode == "6")
        #expect(doc.payment.bankAccounts.map(\.number) == ["61109010140000071219812874"])

        invoice.generatedXML = try FA3Generator.generate(invoice, seller: seller)
        invoice.status = .accepted
        invoice.ksefNumber = "1111111111-20261013-0100A0B0C0D0-E1"
        let accepted = try InvoiceVisualization.sales(invoice, seller: seller)
        #expect(!accepted.isDraft)
        #expect(accepted.document.ksefNumber == invoice.ksefNumber)
        let url = try #require(accepted.document.verificationURL).absoluteString
        #expect(url == "https://qr-test.ksef.mf.gov.pl/invoice/1111111111/13-10-2026/"
                + KSeFVerification.fileHash(Data(invoice.generatedXML.utf8)))
    }

    @Test("Skrót pliku do kodu QR: SHA-256 w Base64URL bez dopełnienia")
    func qrHash() {
        #expect(KSeFVerification.fileHash(Data("abc".utf8)) == "ungWv48Bz-pBQUDeXa4iI7ADYaOWF3qctBD_YfIAFa0")
        let url = KSeFVerification.url(environment: .production, sellerNIP: "1111111111",
                                       issueDate: LocalDate(year: 2026, month: 2, day: 1)!, invoiceXML: Data("abc".utf8))
        #expect(url.absoluteString == "https://qr.ksef.mf.gov.pl/invoice/1111111111/01-02-2026/ungWv48Bz-pBQUDeXa4iI7ADYaOWF3qctBD_YfIAFa0")
    }

    @Test("Kwota słownie po polsku: odmiana liczebników i walut", arguments: [
        ("0", "PLN", "zero złotych 00/100"),
        ("1", "PLN", "jeden złoty 00/100"),
        ("2.05", "PLN", "dwa złote 05/100"),
        ("5", "PLN", "pięć złotych 00/100"),
        ("12", "PLN", "dwanaście złotych 00/100"),
        ("22", "PLN", "dwadzieścia dwa złote 00/100"),
        ("1234.56", "PLN", "tysiąc dwieście trzydzieści cztery złote 56/100"),
        ("2000", "PLN", "dwa tysiące złotych 00/100"),
        ("5000", "PLN", "pięć tysięcy złotych 00/100"),
        ("12000", "PLN", "dwanaście tysięcy złotych 00/100"),
        ("22113", "PLN", "dwadzieścia dwa tysiące sto trzynaście złotych 00/100"),
        ("1000000", "EUR", "milion euro 00/100"),
        ("3200000.99", "USD", "trzy miliony dwieście tysięcy dolarów 99/100"),
        ("-123", "PLN", "minus sto dwadzieścia trzy złote 00/100"),
        ("15", "SEK", "piętnaście SEK 00/100"),
    ])
    func polishWords(amount: String, currency: String, expected: String) {
        #expect(AmountInWords.polish(DecimalText.parse(amount)!, currency: currency) == expected)
    }

    @Test("Kwota słownie po angielsku")
    func englishWords() {
        #expect(AmountInWords.english(DecimalText.parse("1234.56")!, currency: "EUR") == "one thousand two hundred thirty-four EUR 56/100")
        #expect(AmountInWords.english(DecimalText.parse("2000017")!, currency: "PLN") == "two million seventeen PLN 00/100")
    }

    @Test("Formaty liczb i dat zależne od języka szablonu")
    func formats() {
        let pl = InvoiceLabels(.pl), en = InvoiceLabels(.en), both = InvoiceLabels(.plEn)
        #expect(pl.amount(DecimalText.parse("1234567.5")!) == "1\u{00A0}234\u{00A0}567,50")
        #expect(en.amount(DecimalText.parse("-1234.5")!) == "-1,234.50")
        #expect(pl.quantity(DecimalText.parse("1.500")!) == "1,5")
        #expect(pl.date(LocalDate(year: 2026, month: 2, day: 1)!) == "01.02.2026")
        #expect(en.date(LocalDate(year: 2026, month: 2, day: 1)!) == "2026-02-01")
        #expect(both.seller == "Sprzedawca / Seller")
        #expect(both.nip == "NIP / Tax ID")
        #expect(pl.lineRate("23") == "23%" && pl.lineRate("zw") == "zw" && pl.lineRate("0 KR") == "0% KR")
        #expect(pl.title(.correction) == "Faktura korygująca")
    }

    @Test("Szablony: wbudowany, gdy brak zapisanych; domyślny pierwszy; kolor z hex")
    func templates() {
        let company = UUID()
        #expect(InvoiceTemplates.effective([], companyID: company).map(\.name) == ["Standardowy"])
        let a = InvoiceTemplate(companyID: company, name: "B angielski", language: .en)
        let b = InvoiceTemplate(companyID: company, name: "A zwykły")
        let c = InvoiceTemplate(companyID: company, name: "Z domyślny", isDefault: true)
        #expect(InvoiceTemplates.effective([a, b, c], companyID: company).map(\.name) == ["Z domyślny", "A zwykły", "B angielski"])
        #expect(InvoiceTemplate.rgb("#FF8000")! == (1, 128.0 / 255, 0))
        #expect(InvoiceTemplate.rgb("zly") == nil)
        #expect(InvoiceTemplate.hex(red: 1, green: 128.0 / 255, blue: 0) == "#FF8000")
        #expect(InvoiceTemplate(companyID: company, name: "x", accentColor: "??").accentRGB == InvoiceTemplate.rgb("#1A56DB")!)
    }
}
