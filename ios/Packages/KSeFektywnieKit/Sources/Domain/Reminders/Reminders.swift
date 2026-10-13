import Foundation

/// Rekord, do którego można ustawić przypomnienie.
public enum ReminderTarget: Hashable, Sendable {
    case invoice(UUID)
    case paymentFile(UUID)

    public var recordType: String {
        switch self {
        case .invoice: "invoice"
        case .paymentFile: "paymentFile"
        }
    }

    public var recordID: UUID {
        switch self {
        case .invoice(let id), .paymentFile(let id): id
        }
    }

    public init?(recordType: String, recordID: UUID) {
        switch recordType {
        case "invoice": self = .invoice(recordID)
        case "paymentFile": self = .paymentFile(recordID)
        default: return nil
        }
    }

    /// Link zapisywany w przypomnieniu: dotknięcie w aplikacji Przypomnienia otwiera rekord.
    public var deepLink: URL {
        switch self {
        case .invoice(let id): URL(string: "ksefektywnie://invoice/\(id.uuidString)")!
        case .paymentFile(let id): URL(string: "ksefektywnie://payment-file/\(id.uuidString)")!
        }
    }

    public init?(deepLink url: URL) {
        guard url.scheme == "ksefektywnie", let host = url.host(), let id = UUID(uuidString: url.lastPathComponent) else { return nil }
        switch host {
        case "invoice": self = .invoice(id)
        case "payment-file": self = .paymentFile(id)
        default: return nil
        }
    }
}

/// Propozycja przypomnienia (tytuł i notatka w języku interfejsu dostarcza warstwa aplikacji).
public struct ReminderDraft: Hashable, Sendable {
    public var target: ReminderTarget
    public var title: String
    public var notes: String
    /// Dzień i godzina przypomnienia (czas lokalny).
    public var due: DateComponents

    public init(target: ReminderTarget, title: String, notes: String, due: DateComponents) {
        self.target = target
        self.title = title
        self.notes = notes
        self.due = due
    }
}

/// Domyślne terminy przypomnień.
public enum ReminderSchedule {
    /// Godzina przypomnień (rano, przed sesją przelewów w banku).
    public static let hour = 9

    /// Dzień przypomnienia o fakturze: 2 dni przed terminem płatności,
    /// ale nigdy w przeszłości (wtedy jutro); bez terminu — jutro.
    public static func invoiceDay(dueDate: LocalDate?, today: LocalDate, calendar: Calendar = .current) -> LocalDate {
        let tomorrow = shift(today, days: 1, calendar: calendar)
        guard let due = dueDate else { return tomorrow }
        let twoDaysBefore = shift(due, days: -2, calendar: calendar)
        return twoDaysBefore > today ? twoDaysBefore : tomorrow
    }

    /// Paczka przelewów: przypomnienie o imporcie pliku w banku — jutro rano.
    public static func paymentFileDay(today: LocalDate, calendar: Calendar = .current) -> LocalDate {
        shift(today, days: 1, calendar: calendar)
    }

    public static func components(_ day: LocalDate, hour: Int = hour) -> DateComponents {
        DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: 0)
    }

    public static func shift(_ day: LocalDate, days: Int, calendar: Calendar = .current) -> LocalDate {
        LocalDate(calendar.date(byAdding: .day, value: days, to: day.date(calendar: calendar))!, calendar: calendar)
    }
}
