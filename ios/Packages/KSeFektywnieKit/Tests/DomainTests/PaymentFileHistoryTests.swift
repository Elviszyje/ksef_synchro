import Foundation
import Testing
@testable import Domain

@Suite("Historia paczek przelewów")
struct PaymentFileHistoryTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09

    func summary(_ name: String, bank: String, daysAgo: Double, count: Int, paid: Int,
                 sellers: [String] = [], numbers: [String] = []) -> PaymentFileSummary {
        let file = PaymentFile(companyID: UUID(), format: .forBank(bank), bankKey: bank, debitAccount: "1",
                               fileName: name, content: Data(), totalAmount: 100, invoiceCount: count,
                               createdAt: now.addingTimeInterval(-daysAgo * 86_400))
        return PaymentFileSummary(file: file, paidCount: paid, sellerNames: sellers, invoiceNumbers: numbers)
    }

    @Test("Stan rozliczenia paczki")
    func settlement() {
        #expect(summary("a", bank: "erste", daysAgo: 1, count: 3, paid: 0).settlement == .pending)
        #expect(summary("a", bank: "erste", daysAgo: 1, count: 3, paid: 1).settlement == .partial)
        #expect(summary("a", bank: "erste", daysAgo: 1, count: 3, paid: 3).settlement == .settled)
    }

    @Test("Filtry: bank, okres, stan, wyszukiwanie po sprzedawcy i numerze faktury")
    func filters() {
        let all = [
            summary("przelewy_A_Erste_Bank.txt", bank: "erste", daysAgo: 5, count: 2, paid: 2, sellers: ["Hurtownia Ołówek"], numbers: ["FV/1"]),
            summary("przelewy_B_mBank.txt", bank: "mbank", daysAgo: 40, count: 2, paid: 0, sellers: ["Serwis IT"], numbers: ["FV/2"]),
            summary("przelewy_C_PKO_BP.pli", bank: "pko_bp", daysAgo: 200, count: 4, paid: 1, sellers: ["Energia"], numbers: ["E/9"]),
        ]
        var f = PaymentFileFilter()
        #expect(f.apply(all, now: now).count == 3)
        #expect(!f.isActive)

        f.bankKeys = ["mbank", "pko_bp"]
        #expect(f.apply(all, now: now).map(\.file.bankKey) == ["mbank", "pko_bp"])

        f = PaymentFileFilter()
        f.period = .last30Days
        #expect(f.apply(all, now: now).map(\.file.bankKey) == ["erste"])
        f.period = .last90Days
        #expect(f.apply(all, now: now).count == 2)

        f = PaymentFileFilter()
        f.settlements = [.pending, .partial]
        #expect(f.apply(all, now: now).map(\.file.bankKey) == ["mbank", "pko_bp"])
        #expect(f.isActive)

        f = PaymentFileFilter()
        f.search = "ołówek"
        #expect(f.apply(all, now: now).map(\.file.bankKey) == ["erste"])
        f.search = "e/9"
        #expect(f.apply(all, now: now).map(\.file.bankKey) == ["pko_bp"])
        f.search = "mBank"
        #expect(f.apply(all, now: now).map(\.file.bankKey) == ["mbank"])
    }
}
