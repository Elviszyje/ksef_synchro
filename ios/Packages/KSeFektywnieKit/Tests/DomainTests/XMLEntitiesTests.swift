import Foundation
import Testing
@testable import Domain

@Suite("Encje w nazwach kontrahentów")
struct XMLEntitiesTests {
    @Test("Dekodowanie encji nazwanych, numerycznych i podwójnie zakodowanych")
    func decode() {
        #expect(XMLEntities.decode("Grupa K&amp;K KAJA KANCLERSKA") == "Grupa K&K KAJA KANCLERSKA")
        #expect(XMLEntities.decode("A&amp;amp;B") == "A&B")
        #expect(XMLEntities.decode("&quot;Firma&quot; &#8222;X&#x201D; &lt;sp&gt;") == "\"Firma\" „X” <sp>")
        #expect(XMLEntities.decode("Kowalski & Syn") == "Kowalski & Syn")
        #expect(XMLEntities.decode("R&D; &foo; &") == "R&D; &foo; &")
    }

    @Test("Podwójnie zakodowana nazwa sprzedawcy w XML i w metadanych KSeF")
    func parserAndMetadata() {
        let xml = """
        <Faktura xmlns="http://crd.gov.pl/wzor/2025/06/25/13775/"><Podmiot1><DaneIdentyfikacyjne>\
        <NIP>1111111111</NIP><Nazwa>Grupa K&amp;amp;K</Nazwa></DaneIdentyfikacyjne></Podmiot1></Faktura>
        """
        #expect(FAParser.parse(Data(xml.utf8), ksefReferenceNumber: "R").sellerName == "Grupa K&K")
        let header: JSONValue = .object(["ksefNumber": .string("R"), "seller": .object(["name": .string("Grupa K&amp;K")])])
        #expect(InvoiceMapping.parsed(fromMetadata: header).sellerName == "Grupa K&K")
    }
}

@Suite("Metadane KSeF 2.0")
struct MetadataIssueDateTests {
    @Test("Data wystawienia z pola issueDate (KSeF 2.0), nie z daty synchronizacji")
    func issueDate() {
        let header: JSONValue = .object([
            "ksefNumber": .string("R"), "invoiceNumber": .string("19/10/2026"), "issueDate": .string("2026-10-19"),
            "seller": .object(["nip": .string("1111111111"), "name": .string("KAHLA")]),
        ])
        let parsed = InvoiceMapping.parsed(fromMetadata: header)
        #expect(parsed.issueDate == "2026-10-19")
        let invoice = InvoiceMapping.invoice(from: parsed, companyID: UUID(), today: LocalDate(year: 2026, month: 11, day: 27)!)
        #expect(invoice.issueDate == LocalDate(year: 2026, month: 10, day: 19)!)
    }
}
