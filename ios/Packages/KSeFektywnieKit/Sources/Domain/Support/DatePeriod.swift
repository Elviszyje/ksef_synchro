import Foundation

/// Okres na listach (faktury, sprzedaż, wyciągi): szybkie miesiące albo własny zakres dat.
public enum DatePeriod: Hashable, Sendable {
    case all
    case thisMonth
    case previousMonth
    /// Zakres domknięty z obu stron.
    case custom(from: LocalDate, to: LocalDate)

    public var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    /// Granice okresu (włącznie) albo nil dla „całego okresu”.
    public func bounds(today: LocalDate = .today()) -> ClosedRange<LocalDate>? {
        switch self {
        case .all:
            return nil
        case .thisMonth:
            return today.firstOfMonth...today.lastOfMonth
        case .previousMonth:
            let previous = today.firstOfMonth.addingMonths(-1)
            return previous...previous.lastOfMonth
        case .custom(let from, let to):
            return min(from, to)...max(from, to)
        }
    }

    public func contains(_ date: LocalDate, today: LocalDate = .today()) -> Bool {
        bounds(today: today)?.contains(date) ?? true
    }
}

extension LocalDate {
    public var firstOfMonth: LocalDate { LocalDate(year: year, month: month, day: 1)! }

    public var lastOfMonth: LocalDate {
        LocalDate(year: year, month: month, day: LocalDate.daysInMonth(year: year, month: month))!
    }

    /// Przesunięcie o miesiące; dzień przycinany do długości miesiąca (31.03 − 1 → 28/29.02).
    public func addingMonths(_ months: Int) -> LocalDate {
        let index = year * 12 + (month - 1) + months
        let y = index / 12, m = index % 12 + 1
        return LocalDate(year: y, month: m, day: min(day, LocalDate.daysInMonth(year: y, month: m)))!
    }
}
