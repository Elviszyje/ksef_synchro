import Foundation
import Testing
@testable import Domain

@Suite("Faktury sprzedażowe zgodne z Django")
struct SalesTests {
    struct Case {
        let name: String
        let invoice: OutgoingInvoice
    }

    static func spec() throws -> (seller: FA3Seller, now: Date, cases: [Case]) {
        let json = try Fixtures.json("input/outgoing/invoices.json") as! [String: Any]
        let seller = json["seller"] as! [String: String]
        let account = json["bank_account"] as! String
        let now = ISO8601DateFormatter().date(from: json["now"] as! String)!
        let cases = (json["cases"] as! [[String: Any]]).map { c -> Case in
            let i = c["invoice"] as! [String: Any]
            let items = (c["items"] as! [[String: String]]).map {
                OutgoingInvoiceItem(name: $0["name"]!, unit: $0["unit"]!, quantity: DecimalText.parse($0["quantity"]!)!,
                                    unitPriceNet: DecimalText.parse($0["unit_price_net"]!)!, vatRate: VATRate(rawValue: $0["vat_rate"]!)!)
            }
            let form = PaymentForm(rawValue: i["payment_form"] as! String)!
            return Case(name: c["name"] as! String, invoice: OutgoingInvoice(
                companyID: UUID(), invoiceNumber: i["invoice_number"] as! String,
                issueDate: LocalDate(iso: i["issue_date"] as! String)!,
                deliveryDate: (i["delivery_date"] as? String).flatMap(LocalDate.init(iso:)),
                paymentDueDate: LocalDate(iso: i["payment_due_date"] as! String)!,
                paymentForm: form, currency: i["currency"] as! String, bankAccountNumber: form == .transfer ? account : "",
                buyerNIP: i["buyer_nip"] as! String, buyerName: i["buyer_name"] as! String, buyerAddress: i["buyer_address"] as! String,
                exemptionType: VATExemptionType(rawValue: i["vat_exemption_type"] as! String)!,
                exemptionBasis: i["vat_exemption_basis"] as! String, items: items))
        }
        return (FA3Seller(nip: seller["nip"]!, name: seller["name"]!, address: seller["address"]!), now, cases)
    }

    /// Kanoniczna postać dokumentu: ścieżka elementu, atrybuty i tekst, w kolejności dokumentu.
    static func canonical(_ xml: Data) throws -> [String] {
        let tree = try #require(XMLTree.parse(xml))
        var out: [String] = []
        func walk(_ node: Domain.XMLNode, _ path: String) {
            let here = "\(path)/\(node.name)"
            let attrs = node.attributes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
            let text = node.children.isEmpty ? PyText.strip(node.text) : ""
            out.append("\(here)[\(attrs)] \(node.namespace) \(text)")
            for child in node.children { walk(child, here) }
        }
        walk(tree.root, "")
        return out
    }

    @Test("XML FA(3) ma tę samą strukturę i treść co w Django")
    func fa3MatchesDjango() throws {
        let spec = try Self.spec()
        for c in spec.cases {
            let swift = try FA3Generator.generate(c.invoice, seller: spec.seller, now: spec.now, systemInfo: "KSeF Invoices")
            let django = try Fixtures.data("expected/outgoing/\(c.name).xml")
            let a = try Self.canonical(Data(swift.utf8)), b = try Self.canonical(django)
            #expect(a == b, "\(c.name): \(zip(a, b).first { $0 != $1 }.map { "\($0) ≠ \($1)" } ?? "różna liczba elementów")")
        }
    }

    @Test("Kwoty pozycji: ROUND_HALF_UP jak w Django")
    func itemAmounts() throws {
        let spec = try Self.spec()
        let expected = try Fixtures.json("expected/outgoing/item_amounts.json") as! [String: [[String: String]]]
        for c in spec.cases {
            for (item, e) in zip(c.invoice.items, expected[c.name]!) {
                #expect(item.amountNet == DecimalText.parse(e["net"]!), "\(item.name)")
                #expect(item.amountVAT == DecimalText.parse(e["vat"]!), "\(item.name)")
                #expect(item.amountGross == DecimalText.parse(e["gross"]!), "\(item.name)")
            }
        }
    }

    @Test("Zwolnienie wymaga podstawy, brak pozycji i rachunku blokuje generowanie")
    func generatorErrors() throws {
        let spec = try Self.spec()
        var exempt = spec.cases[1].invoice
        exempt.exemptionBasis = "  "
        #expect(throws: FA3GeneratorError.missingExemptionBasis) { try FA3Generator.generate(exempt, seller: spec.seller) }
        #expect(exempt.validationIssues.contains(.missingExemptionBasis))

        var transfer = spec.cases[0].invoice
        transfer.bankAccountNumber = ""
        #expect(throws: FA3GeneratorError.missingBankAccount) { try FA3Generator.generate(transfer, seller: spec.seller) }
        transfer.items = []
        #expect(throws: FA3GeneratorError.noItems) { try FA3Generator.generate(transfer, seller: spec.seller) }
        #expect(spec.cases[0].invoice.validationIssues.isEmpty)
    }

    @Test("Numeracja według wzoru firmy")
    func numbering() {
        #expect(InvoiceNumbering.next(pattern: "FV/{rok}/{nnnn}", year: 2026, existing: []) == "FV/2026/0001")
        #expect(InvoiceNumbering.next(pattern: "FV/{rok}/{nnnn}", year: 2026,
                                      existing: ["FV/2026/0009", "FV/2026/0010", "FV/2025/0099", "FV/2026/abc"]) == "FV/2026/0011")
        #expect(InvoiceNumbering.next(pattern: "{nnn}/{rok}/S", year: 2027, existing: ["005/2027/S"]) == "006/2027/S")
    }

    @Test("Pozycja z katalogu")
    func catalogItem() {
        let entry = CatalogItem(companyID: UUID(), name: "Szkolenie BHP", unit: "os.", unitPriceNet: 350, vatRate: .exempt, useCount: 3)
        let item = entry.makeItem()
        #expect(item.name == "Szkolenie BHP" && item.quantity == 1 && item.amountGross == 350 && item.vatRate == .exempt)
    }
}
