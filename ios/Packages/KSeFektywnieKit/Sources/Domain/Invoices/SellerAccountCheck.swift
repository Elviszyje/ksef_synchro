import Foundation

/// Ostrzeżenie przed podmianą rachunku: dostawca, który na wcześniejszych fakturach podawał
/// inne konto, a na tej podaje nowe. Porównanie jest lokalne (historia faktur w aplikacji)
/// i niczego nie przesądza — zmiana banku przez dostawcę też tak wygląda.
public enum SellerAccountCheck {
    /// Faktury (spośród `invoices`), których rachunek nie wystąpił na żadnej wcześniejszej
    /// fakturze tego samego dostawcy, choć dostawca ma już historię z innym rachunkiem.
    ///
    /// „Wcześniejsza” znaczy: wystawiona przed daną fakturą. Faktury bez rachunku i bez NIP-u
    /// sprzedawcy są pomijane po obu stronach porównania.
    public static func changedAccounts(in invoices: [Invoice], history: [Invoice]) -> Set<UUID> {
        var bySeller: [String: [Invoice]] = [:]
        for invoice in history where !invoice.sellerNIP.isEmpty && !normalized(invoice.bankAccountNumber).isEmpty {
            bySeller[invoice.sellerNIP, default: []].append(invoice)
        }
        var flagged = Set<UUID>()
        for invoice in invoices {
            let account = normalized(invoice.bankAccountNumber)
            guard !account.isEmpty, let all = bySeller[invoice.sellerNIP] else { continue }
            let earlier = all.filter { $0.id != invoice.id && $0.issueDate < invoice.issueDate }
            guard !earlier.isEmpty else { continue }
            if !earlier.contains(where: { normalized($0.bankAccountNumber) == account }) {
                flagged.insert(invoice.id)
            }
        }
        return flagged
    }

    public static func hasChangedAccount(_ invoice: Invoice, history: [Invoice]) -> Bool {
        changedAccounts(in: [invoice], history: history).contains(invoice.id)
    }

    /// Rachunek bez spacji i prefiksu „PL” — ten sam numer bywa zapisany na kilka sposobów.
    static func normalized(_ account: String) -> String {
        var value = account.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        if value.hasPrefix("PL") { value.removeFirst(2) }
        return value
    }
}
