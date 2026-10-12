import Foundation
import Testing
@testable import Domain

@Suite("Wyciągi bankowe i matcher zgodne z Django")
struct StatementTests {
    static let files = (try? Fixtures.files(in: "input/statements")) ?? []

    @Test("Detekcja i parsowanie", arguments: files)
    func statement(_ file: URL) throws {
        let name = file.deletingPathExtension().lastPathComponent
        let expected = try Fixtures.json("expected/statements/\(name).json") as! [String: Any]
        let content = try StatementImporter.decode(Data(contentsOf: file))

        let detect = expected["detect"] as! [String: Bool]
        #expect(MT940Parser.detect(content) == detect["mt940"])
        #expect(ErsteCSVParser.detect(content) == detect["erste"])
        #expect(VeloBankCSVParser.detect(content) == detect["velobank"])

        let stmt = try StatementImporter.parse(content)
        expectString(stmt.bankKey, expected["bank_key"], "bank_key")
        expectString(stmt.accountNumber, expected["account_number"], "account_number")
        expectDate(stmt.statementDate, expected["statement_date"], "statement_date")

        let txs = expected["transactions"] as! [[String: Any]]
        try #require(stmt.transactions.count == txs.count)
        for (a, e) in zip(stmt.transactions, txs) {
            expectDate(a.transactionDate, e["transaction_date"], "transaction_date")
            expectDate(a.valueDate, e["value_date"], "value_date")
            expectDecimal(a.amount, e["amount"], "amount")
            expectString(a.currency, e["currency"], "currency")
            #expect(a.isCredit == e["is_credit"] as? Bool)
            expectString(a.description, e["description"], "description")
            expectString(a.counterparty, e["counterparty"], "counterparty")
            expectString(a.reference, e["reference"], "reference")
        }
    }

    @Test("Plik CP1250 zachowuje polskie znaki")
    func cp1250Statement() throws {
        let csv = "\"Nr rachunku\";\"Data transakcji\";\"Data ksiegowania\";\"Opis transakcji\";\"Kwota\";\"Waluta\"\r\n"
            + "\"1\";\"12.10.2026\";\"12.10.2026\";\"Opłata za usługę żółtą\";\"-1,00\";\"PLN\"\r\n"
        let stmt = try StatementImporter.parse(data: CP1250.encode(csv))
        #expect(stmt.transactions.first?.description == "Opłata za usługę żółtą")
    }

    @Test("Nieznany format")
    func unknown() {
        #expect(throws: StatementError.unrecognizedFormat) { try StatementImporter.parse("to nie jest wyciąg") }
    }

    struct Candidate: MatchCandidate {
        let id: Int
        let invoiceNumber: String
        let sellerNIP: String
        let amountGross: Decimal
        let bankAccountNumber: String
    }

    @Test("Matcher")
    func matcher() throws {
        let input = try Fixtures.json("input/matcher/case.json") as! [String: Any]
        let candidates = (input["invoices"] as! [[String: Any]]).map {
            Candidate(id: $0["id"] as! Int, invoiceNumber: $0["invoice_number"] as! String, sellerNIP: $0["seller_nip"] as! String,
                      amountGross: DecimalText.parse($0["amount_gross"] as! String)!, bankAccountNumber: $0["bank_account_number"] as! String)
        }
        let txs = (input["transactions"] as! [[String: Any]]).map {
            MatchableTransaction(amount: DecimalText.parse($0["amount"] as! String)!, isCredit: $0["is_credit"] as! Bool,
                                 description: $0["description"] as! String, reference: $0["reference"] as! String)
        }
        let expected = try Fixtures.json("expected/matcher/case.json") as! [[String: Any]]
        let actual = InvoiceMatcher.match(txs, candidates: candidates)
        try #require(actual.count == expected.count, "\(actual)")
        for (a, e) in zip(actual, expected) {
            #expect(a.transactionIndex == e["transaction_index"] as? Int)
            #expect(a.invoiceID == e["invoice_id"] as? Int)
            #expect(a.type.rawValue == e["match_type"] as? String)
            #expect(a.confidence.rawValue == e["confidence"] as? String)
        }
    }
}
