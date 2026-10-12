import Foundation
import Testing
@testable import Domain

@Suite("Parser FA(2)/FA(3) zgodny z Django")
struct FAParserTests {
    static let xmlFiles = (try? Fixtures.files(in: "input/fa").filter { $0.pathExtension == "xml" }) ?? []

    @Test("Pola sparsowanej faktury", arguments: xmlFiles)
    func parsedFields(_ file: URL) throws {
        let name = file.deletingPathExtension().lastPathComponent
        let expected = try Fixtures.json("expected/fa/\(name).json") as! [String: Any]
        let p = expected["parsed"] as! [String: Any]
        let parsed = FAParser.parse(try Data(contentsOf: file), ksefReferenceNumber: "REF-\(name)")

        expectString(parsed.invoiceNumber, p["invoice_number"], "invoice_number")
        expectString(parsed.ksefReferenceNumber, p["ksef_reference_number"], "ksef_reference_number")
        expectString(parsed.issueDate, p["issue_date"], "issue_date")
        expectString(parsed.paymentDueDate, p["payment_due_date"], "payment_due_date")
        expectString(parsed.sellerName, p["seller_name"], "seller_name")
        expectString(parsed.sellerNIP, p["seller_nip"], "seller_nip")
        expectString(parsed.sellerAddress, p["seller_address"], "seller_address")
        expectString(parsed.buyerNIP, p["buyer_nip"], "buyer_nip")
        expectDecimal(parsed.amountNet, p["amount_net"], "amount_net")
        expectDecimal(parsed.amountVAT, p["amount_vat"], "amount_vat")
        expectDecimal(parsed.amountGross, p["amount_gross"], "amount_gross")
        expectString(parsed.currency, p["currency"], "currency")
        expectString(parsed.invoiceType, p["invoice_type"], "invoice_type")
        expectString(parsed.description, p["description"], "description")
        #expect(parsed.isSplitPayment == p["is_split_payment"] as? Bool)
        expectDecimal(parsed.vatAmountSplit, p["vat_amount_split"], "vat_amount_split")
        expectString(parsed.bankAccountNumber, p["bank_account_number"], "bank_account_number")
        expectString(parsed.paymentTitle, p["payment_title"], "payment_title")
        #expect(parsed.isPaid == p["is_paid"] as? Bool)
        expectString(parsed.paymentDate, p["payment_date"], "payment_date")
        expectString(parsed.paymentForm, p["payment_form"], "payment_form")
        #expect(parsed.rawXML == String(decoding: try Data(contentsOf: file), as: UTF8.self))

        let items = expected["line_items"] as! [[String: String]]
        let actualItems = FAParser.lineItems(rawXML: parsed.rawXML)
        #expect(actualItems.count == items.count)
        for (a, e) in zip(actualItems, items) {
            #expect(a == InvoiceLineItem(nr: e["nr"]!, name: e["name"]!, unit: e["unit"]!, qty: e["qty"]!,
                                         unitPrice: e["unit_price"]!, netValue: e["net_value"]!, vatRate: e["vat_rate"]!))
        }

        if let f = expected["invoice_fields"] as? [String: Any] {
            let inv = InvoiceMapping.invoice(from: parsed, companyID: UUID(), today: LocalDate(year: 2000, month: 1, day: 1)!)
            expectString(inv.invoiceNumber, f["invoice_number"], "invoice_number")
            expectString(inv.sellerName, f["seller_name"], "seller_name")
            expectString(inv.currency, f["currency"], "currency")
            expectDate(inv.issueDate, f["issue_date"], "issue_date")
            expectDate(inv.paymentDueDate, f["payment_due_date"], "payment_due_date")
            expectDate(inv.paymentDate, f["payment_date"], "payment_date")
            expectString(inv.status.rawValue, f["status"], "status")
            expectDecimal(inv.amountGross, f["amount_gross"], "amount_gross")
        }
    }

    @Test("Faktura z metadanych KSeF (bez XML)")
    func metadata() throws {
        let headers = try JSONDecoder().decode([JSONValue].self, from: Fixtures.data("input/fa/metadata.json"))
        let expected = try Fixtures.json("expected/fa/metadata.json") as! [[String: Any]]
        #expect(headers.count == expected.count)
        for (header, e) in zip(headers, expected) {
            let p = InvoiceMapping.parsed(fromMetadata: header, buyerNIPFallback: "1132854320")
            expectString(p.ksefReferenceNumber, e["ksef_reference_number"], "ksef_reference_number")
            expectString(p.invoiceNumber, e["invoice_number"], "invoice_number")
            expectString(p.sellerNIP, e["seller_nip"], "seller_nip")
            expectString(p.sellerName, e["seller_name"], "seller_name")
            expectString(p.buyerNIP, e["buyer_nip"], "buyer_nip")
            expectString(p.issueDate, e["issue_date"], "issue_date")
            expectDecimal(p.amountGross, e["amount_gross"], "amount_gross")
            expectDecimal(p.amountNet, e["amount_net"], "amount_net")
            expectDecimal(p.amountVAT, e["amount_vat"], "amount_vat")
            expectString(p.currency, e["currency"], "currency")
            expectString(p.paymentTitle, e["payment_title"], "payment_title")
        }
    }

    @Test("Aktualizacja faktury z KSeF zachowuje dane użytkownika")
    func mergeKeepsUserData() throws {
        let company = UUID()
        var existing = Invoice(companyID: company, ksefReferenceNumber: "R", invoiceNumber: "A",
                               amountNet: 100, issueDate: LocalDate(year: 2026, month: 1, day: 1)!,
                               bankAccountNumber: "61109010140000071219812874", status: .accepted, notes: "moja notatka")
        let incoming = Invoice(companyID: company, ksefReferenceNumber: "R", invoiceNumber: "A2",
                               sellerName: InvoiceMapping.unknownSeller, amountNet: 0, amountGross: 123,
                               issueDate: LocalDate(year: 2026, month: 1, day: 2)!)
        let change = InvoiceMapping.merge(incoming, into: &existing)
        #expect(change == nil)
        #expect(existing.invoiceNumber == "A2")
        #expect(existing.amountNet == 100)
        #expect(existing.amountGross == 123)
        #expect(existing.bankAccountNumber == "61109010140000071219812874")
        #expect(existing.status == .accepted)
        #expect(existing.notes == "moja notatka")
        #expect(existing.sellerName == "")
    }
}
