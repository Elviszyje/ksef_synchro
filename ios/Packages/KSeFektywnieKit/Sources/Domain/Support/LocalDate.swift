import Foundation

/// Data kalendarzowa bez strefy czasowej (odpowiednik `datetime.date`).
///
/// Faktury, terminy płatności i daty transakcji to daty "księgowe" — nie wolno
/// ich przesuwać przy zmianie strefy czasowej telefonu.
public struct LocalDate: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month), day >= 1,
              day <= LocalDate.daysInMonth(year: year, month: month) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parsuje `YYYY-MM-DD` (jak `date.fromisoformat`).
    public init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = c.year!
        self.month = c.month!
        self.day = c.day!
    }

    public static func today(calendar: Calendar = .current) -> LocalDate { LocalDate(Date(), calendar: calendar) }

    public var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var compact: String { String(format: "%04d%02d%02d", year, month, day) }
    public var description: String { iso }

    public func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = LocalDate(iso: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Nieprawidłowa data: \(raw)")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }
}

extension LocalDate {
    enum Order { case dmy, ymd }

    /// Odpowiednik `datetime.strptime` dla formatów typu `%d.%m.%Y`, `%Y-%m-%d`.
    /// `%d`/`%m` przyjmują 1–2 cyfry, `%Y` dokładnie 4 cyfry.
    static func parse(_ text: String, order: Order, separator: Character) -> LocalDate? {
        let parts = text.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }) else { return nil }
        let (y, m, d): (String, String, String)
        switch order {
        case .dmy: (d, m, y) = (parts[0], parts[1], parts[2])
        case .ymd: (y, m, d) = (parts[0], parts[1], parts[2])
        }
        guard y.count == 4, (1...2).contains(m.count), (1...2).contains(d.count) else { return nil }
        return LocalDate(year: Int(y)!, month: Int(m)!, day: Int(d)!)
    }
}

extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
