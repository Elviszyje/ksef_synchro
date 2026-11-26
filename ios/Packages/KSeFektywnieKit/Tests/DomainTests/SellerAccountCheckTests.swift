import Foundation
import Testing
@testable import Domain

@Suite("Ostrzeżenie o zmianie rachunku dostawcy")
struct SellerAccountCheckTests {
    let company = UUID()

    func inv(_ nip: String, _ account: String, _ month: Int, _ day: Int = 5) -> Invoice {
        Invoice(companyID: company, ksefReferenceNumber: UUID().uuidString, invoiceNumber: "FV/\(month)/\(day)",
                sellerName: "Dostawca \(nip)", sellerNIP: nip, issueDate: LocalDate(year: 2026, month: month, day: day)!,
                bankAccountNumber: account)
    }

    @Test("Nowy rachunek przy istniejącej historii jest oznaczany, znany rachunek nie")
    func changed() {
        let old1 = inv("111", "11 1111", 1), old2 = inv("111", "111111", 2)
        let same = inv("111", "PL111111", 3)
        let different = inv("111", "222222", 4)
        let history = [old1, old2, same, different]
        #expect(!SellerAccountCheck.hasChangedAccount(same, history: history))
        #expect(SellerAccountCheck.hasChangedAccount(different, history: history))
        #expect(SellerAccountCheck.changedAccounts(in: history, history: history) == [different.id])
    }

    @Test("Pierwsza faktura dostawcy, brak rachunku i późniejsze faktury nie dają ostrzeżenia")
    func noWarning() {
        let first = inv("222", "333333", 1)
        let noAccount = inv("222", "", 2)
        let later = inv("222", "444444", 6)
        #expect(!SellerAccountCheck.hasChangedAccount(first, history: [first, noAccount, later]))
        #expect(!SellerAccountCheck.hasChangedAccount(noAccount, history: [first, noAccount, later]))
        // Inny dostawca z innym rachunkiem nie ma znaczenia.
        let other = inv("333", "555555", 3)
        #expect(!SellerAccountCheck.hasChangedAccount(other, history: [first, later, other]))
        // Powrót do rachunku używanego wcześniej nie jest zmianą.
        let back = inv("222", "333333", 7)
        #expect(!SellerAccountCheck.hasChangedAccount(back, history: [first, later, back]))
    }
}
