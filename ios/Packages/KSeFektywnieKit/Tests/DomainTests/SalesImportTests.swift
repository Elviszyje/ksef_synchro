import Foundation
import Testing
@testable import Domain

/// Te same przypadki co `apps/ksef/tests/test_sales_import.py` (SalesParserTests).
@Suite("Import faktur sprzedażowych z KSeF")
struct SalesImportTests {
    static let ns = "http://crd.gov.pl/wzor/2025/06/25/13775/"

    static func xml(_ fa: String, buyer: String = "<NIP>6260181591</NIP><Nazwa>Klient</Nazwa>") -> Data {
        Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <Faktura xmlns="\(ns)">
              <Podmiot1><DaneIdentyfikacyjne><NIP>1111111111</NIP><Nazwa>Moja Firma</Nazwa></DaneIdentyfikacyjne></Podmiot1>
              <Podmiot2><DaneIdentyfikacyjne>\(buyer)</DaneIdentyfikacyjne></Podmiot2>
              <Fa><KodWaluty>PLN</KodWaluty><P_1>2026-10-01</P_1><P_2>FV/X/1</P_2>\(fa)</Fa>
            </Faktura>
            """.utf8)
    }

    static func parse(_ data: Data) -> OutgoingInvoice? {
        SalesImport.invoice(xml: data, ksefNumber: "K1", companyID: UUID(), environment: .production,
                            now: Date(timeIntervalSince1970: 1_790_000_000), device: "d")
    }

    @Test("Faktury wygenerowane przez Django wracają z tymi samymi danymi i kwotami")
    func roundTripOfDjangoFixtures() throws {
        let spec = try SalesTests.spec()
        for c in spec.cases {
            let imported = try #require(Self.parse(try Fixtures.data("expected/outgoing/\(c.name).xml")), "\(c.name)")
            let original = c.invoice
            #expect(imported.status == .imported && imported.ksefNumber == "K1" && !imported.canBeEdited)
            #expect(imported.invoiceNumber == original.invoiceNumber)
            #expect(imported.issueDate == original.issueDate && imported.paymentDueDate == original.paymentDueDate)
            #expect(imported.deliveryDate == original.deliveryDate)
            #expect(imported.paymentForm == original.paymentForm && imported.currency == original.currency)
            #expect(imported.bankAccountNumber == original.bankAccountNumber)
            #expect(imported.buyerNIP == original.buyerNIP && imported.buyerName == original.buyerName)
            #expect(imported.exemptionBasis == original.exemptionBasis)
            #expect(imported.items.map(\.name) == original.items.map(\.name))
            #expect(imported.items.map(\.vatRate) == original.items.map(\.vatRate))
            #expect(imported.items.map(\.quantity) == original.items.map(\.quantity))
            #expect(imported.items.map(\.unitPriceNet) == original.items.map(\.unitPriceNet))
            #expect(imported.amountNet == original.amountNet, "\(c.name)")
            #expect(imported.amountVAT == original.amountVAT, "\(c.name)")
            #expect(imported.amountGross == original.amountGross, "\(c.name)")
            #expect(imported.generatedXML.contains(original.invoiceNumber))
        }
    }

    @Test("VAT pozycji uzgodniony z sumą P_14 faktury")
    func vatReconciliation() throws {
        // 3 × 0,10 zł netto: VAT od pozycji 3 × 0,02 = 0,06, od sumy (0,30 × 23%) = 0,07.
        let rows = (1...3).map {
            "<FaWiersz><NrWierszaFa>\($0)</NrWierszaFa><P_7>Śruba \($0)</P_7><P_8B>1</P_8B><P_9A>0.10</P_9A><P_11>0.10</P_11><P_12>23</P_12></FaWiersz>"
        }.joined()
        let invoice = try #require(Self.parse(Self.xml("<P_13_1>0.30</P_13_1><P_14_1>0.07</P_14_1><P_15>0.37</P_15>\(rows)")))
        #expect(invoice.amountVAT == Decimal(string: "0.07"))
        #expect(invoice.amountGross == Decimal(string: "0.37"))
    }

    @Test("Pozycje liczone od cen brutto")
    func grossPricedRows() throws {
        let row = "<FaWiersz><P_7>Kawa</P_7><P_8B>2</P_8B><P_9B>12.30</P_9B><P_11A>24.60</P_11A><P_12>23</P_12></FaWiersz>"
        let item = try #require(Self.parse(Self.xml("<P_13_1>20.00</P_13_1><P_14_1>4.60</P_14_1><P_15>24.60</P_15>\(row)"))?.items.first)
        #expect(item.amountNet == 20 && item.amountVAT == Decimal(string: "4.60") && item.unitPriceNet == 10)
    }

    @Test("Korekta: pozycje zbiorcze z sum nagłówka i notatka o korygowanej fakturze")
    func correction() throws {
        let rows = "<FaWiersz><P_7>Usługa</P_7><P_8B>1</P_8B><P_9A>100</P_9A><P_11>100</P_11><P_12>23</P_12><StanPrzed>1</StanPrzed></FaWiersz>"
            + "<FaWiersz><P_7>Usługa</P_7><P_8B>1</P_8B><P_9A>80</P_9A><P_11>80</P_11><P_12>23</P_12></FaWiersz>"
        let body = "<P_13_1>-20.00</P_13_1><P_14_1>-4.60</P_14_1><P_15>-24.60</P_15><RodzajFaktury>KOR</RodzajFaktury>"
            + "<DaneFaKorygowanej><NrFaKorygowanej>FV/X/0</NrFaKorygowanej></DaneFaKorygowanej>" + rows
        let invoice = try #require(Self.parse(Self.xml(body)))
        #expect(invoice.notes == "Korekta faktury FV/X/0")
        #expect(invoice.items.map(\.name) == ["Korekta wartości – stawka 23%"])
        #expect(invoice.amountGross == Decimal(string: "-24.60"))
    }

    @Test("Konsument bez NIP, płatność gotówką, termin = data wystawienia")
    func consumerCash() throws {
        let body = "<P_13_1>10</P_13_1><P_14_1>2.30</P_14_1><P_15>12.30</P_15>"
            + "<FaWiersz><P_7>A</P_7><P_8B>1</P_8B><P_9A>10</P_9A><P_11>10</P_11><P_12>23</P_12></FaWiersz>"
            + "<Platnosc><FormaPlatnosci>1</FormaPlatnosci></Platnosc>"
        let invoice = try #require(Self.parse(Self.xml(body, buyer: "<BrakID>1</BrakID><Nazwa>Jan Kowalski</Nazwa>")))
        #expect(invoice.buyerNIP == "" && invoice.buyerName == "Jan Kowalski" && invoice.paymentForm == .cash)
        #expect(invoice.paymentDueDate == LocalDate(year: 2026, month: 10, day: 1))
    }

    @Test("Nieczytelny XML albo brak numeru faktury")
    func unreadable() {
        #expect(Self.parse(Data("<nie-xml".utf8)) == nil)
        #expect(Self.parse(Data(String(decoding: Self.xml(""), as: UTF8.self).replacingOccurrences(of: "<P_2>FV/X/1</P_2>", with: "").utf8)) == nil)
    }

    @Test("Wizualizacja zaimportowanej faktury z oryginalnego XML, z kodem QR")
    func visualization() throws {
        let spec = try SalesTests.spec()
        let invoice = try #require(Self.parse(try Fixtures.data("expected/outgoing/\(spec.cases[0].name).xml")))
        let prepared = try InvoiceVisualization.sales(invoice, seller: spec.seller)
        #expect(!prepared.isDraft)
    }
}
