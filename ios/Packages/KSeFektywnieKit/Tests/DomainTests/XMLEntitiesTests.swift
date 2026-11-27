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
