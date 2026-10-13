import Foundation

/// Paczka przelewów z danymi do historii: stan rozliczenia i dane do wyszukiwania.
public struct PaymentFileSummary: Identifiable, Hashable, Sendable {
    public enum Settlement: String, CaseIterable, Sendable {
        /// Żadna faktura z paczki nie jest jeszcze opłacona.
        case pending
        /// Część faktur opłacona (np. po imporcie wyciągu).
        case partial
        /// Wszystkie faktury opłacone.
        case settled
    }

    public var file: PaymentFile
    public var paidCount: Int
    public var sellerNames: [String]
    public var invoiceNumbers: [String]
    public var id: UUID { file.id }

    public init(file: PaymentFile, paidCount: Int, sellerNames: [String], invoiceNumbers: [String]) {
        self.file = file
        self.paidCount = paidCount
        self.sellerNames = sellerNames
        self.invoiceNumbers = invoiceNumbers
    }

    public var settlement: Settlement {
        if paidCount == 0 { return .pending }
        return paidCount >= file.invoiceCount ? .settled : .partial
    }
}

/// Filtry historii paczek.
public struct PaymentFileFilter: Hashable, Sendable {
    public enum Period: String, CaseIterable, Sendable {
        case all, last30Days, last90Days, thisYear
    }

    public var search = ""
    public var bankKeys: Set<String> = []
    public var period: Period = .all
    public var settlements: Set<PaymentFileSummary.Settlement> = []

    public init() {}

    public var isActive: Bool { !bankKeys.isEmpty || period != .all || !settlements.isEmpty }

    public func apply(_ summaries: [PaymentFileSummary], now: Date = Date(), calendar: Calendar = .current) -> [PaymentFileSummary] {
        let term = search.trimmingCharacters(in: .whitespaces).lowercased()
        return summaries.filter { s in
            if !bankKeys.isEmpty && !bankKeys.contains(s.file.bankKey) { return false }
            if !settlements.isEmpty && !settlements.contains(s.settlement) { return false }
            switch period {
            case .all: break
            case .last30Days: if s.file.createdAt < now.addingTimeInterval(-30 * 86_400) { return false }
            case .last90Days: if s.file.createdAt < now.addingTimeInterval(-90 * 86_400) { return false }
            case .thisYear:
                if calendar.component(.year, from: s.file.createdAt) != calendar.component(.year, from: now) { return false }
            }
            if !term.isEmpty {
                let haystack = ([s.file.fileName] + s.sellerNames + s.invoiceNumbers).map { $0.lowercased() }
                if !haystack.contains(where: { $0.contains(term) }) { return false }
            }
            return true
        }
    }
}
