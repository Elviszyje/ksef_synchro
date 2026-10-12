import Foundation
import Testing
@testable import Domain

@Suite("Reguły domenowe zgodne z Django")
struct DomainRulesTests {
    @Test("Przejścia statusów")
    func transitions() throws {
        let json = try Fixtures.json("expected/domain/status_transitions.json") as! [String: [String: [String]]]
        for (kind, table) in [("standard", InvoiceStatusRules.standard), ("correction", InvoiceStatusRules.correction)] {
            let expected = json[kind]!
            #expect(Set(table.keys.map(\.rawValue)) == Set(expected.keys), "\(kind)")
            for (from, to) in expected {
                #expect(table[InvoiceStatus(rawValue: from)!]!.map(\.rawValue) == to, "\(kind) \(from)")
            }
        }
    }

    @Test("Zaakceptowana korekta staje się opłacona")
    func correctionAutoPaid() throws {
        var inv = Invoice(companyID: UUID(), ksefReferenceNumber: "R", invoiceNumber: "K", amountGross: -10,
                          issueDate: LocalDate(year: 2026, month: 1, day: 1)!)
        let log = try inv.changeStatus(to: .accepted)
        #expect(inv.status == .paid)
        #expect(log.map(\.to) == [.accepted, .paid])
        #expect(throws: InvoiceStatusError.self) { try inv.changeStatus(to: .new) }
    }

    @Test("Rozpoznawanie banku")
    func bankDetection() throws {
        for e in try Fixtures.json("expected/domain/bank_detection.json") as! [[String: String]] {
            let key = BankDetection.bankKey(for: e["account"]!)
            #expect(key == e["bank_key"], "\(e["account"]!)")
            #expect(BankDetection.label(for: key) == e["label"])
            #expect(BankDetection.fileSuffix(for: key) == e["file_suffix"])
            #expect(PaymentFileFormat.forBank(key).fileExtension == e["extension"])
        }
    }

    @Test("Czyszczenie tekstu do plików bankowych")
    func cleanText() throws {
        for e in try Fixtures.json("expected/domain/clean_text.json") as! [[String: Any]] {
            #expect(PaymentText.clean(e["input"] as! String, maxLength: e["max_len"] as! Int) == e["output"] as? String,
                    "\(e["input"]!)")
        }
    }

    @Test("Format kwoty (zaokrąglenie bankierskie)")
    func formatAmount() throws {
        for e in try Fixtures.json("expected/domain/format_amount.json") as! [[String: String]] {
            #expect(PaymentText.formatAmount(DecimalText.parse(e["input"]!)!) == e["output"], "\(e["input"]!)")
        }
    }

    @Test("Normalizacja numeru faktury")
    func normalizeInvoiceNumber() throws {
        for e in try Fixtures.json("expected/domain/normalize_invoice_nr.json") as! [[String: String]] {
            #expect(InvoiceMatcher.normalizeInvoiceNumber(e["input"]!) == e["output"], "\(e["input"]!)")
        }
    }

    @Test("Przeterminowanie")
    func overdue() {
        let today = LocalDate(year: 2026, month: 10, day: 11)!
        var inv = Invoice(companyID: UUID(), ksefReferenceNumber: "R", invoiceNumber: "A",
                          issueDate: today, paymentDueDate: LocalDate(year: 2026, month: 10, day: 10)!)
        #expect(inv.isOverdue(today: today))
        inv.status = .sentForPayment
        #expect(!inv.isOverdue(today: today))
    }

    @Test("CP1250 w obie strony")
    func cp1250RoundTrip() {
        let text = "Zażółć gęślą jaźń ŁÓDŹ €"
        #expect(CP1250.decode(CP1250.encode(text)) == text)
        #expect(CP1250.encode("✓") == Data([0x3F]))
    }

    @Test("CSV w semantyce Pythona")
    func csv() {
        #expect(CSVReader.rows("a,\"b,c\",\"d\"\"e\"\n\"x\"y,z") == [["a", "b,c", "d\"e"], ["xy", "z"]])
        #expect(CSVReader.rows("a,\r\n\r\nb") == [["a", ""], [], ["b"]])
        #expect(CSVReader.rows("\"multi\nline\",1") == [["multi\nline", "1"]])
    }
}
