import Foundation
import EventKit
import Observation
import GRDB
import Domain
import Persistence

/// Integracja z aplikacją Przypomnienia (EventKit).
@Observable
final class RemindersService {
    struct ReminderInfo: Equatable {
        let identifier: String
        let title: String
        let due: Date?
        let isCompleted: Bool
        let listName: String
    }

    private let store = EKEventStore()
    private(set) var authorization = EKEventStore.authorizationStatus(for: .reminder)
    private var observation: AnyDatabaseCancellable?

    var hasAccess: Bool { authorization == .fullAccess }
    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    /// iOS nie ma trybu "tylko zapis" dla przypomnień — potrzebny pełny dostęp.
    func requestAccess() async -> Bool {
        if hasAccess { return true }
        let granted = (try? await store.requestFullAccessToReminders()) ?? false
        authorization = EKEventStore.authorizationStatus(for: .reminder)
        return granted
    }

    var lists: [EKCalendar] { store.calendars(for: .reminder).sorted { $0.title < $1.title } }

    var defaultList: EKCalendar? { store.defaultCalendarForNewReminders() ?? lists.first }

    func info(_ identifier: String) -> ReminderInfo? {
        guard hasAccess, let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return nil }
        return ReminderInfo(identifier: identifier, title: reminder.title ?? "",
                            due: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                            isCompleted: reminder.isCompleted, listName: reminder.calendar?.title ?? "")
    }

    /// Tworzy albo aktualizuje przypomnienie; zwraca jego identyfikator.
    func save(_ draft: ReminderDraft, listID: String?, existing identifier: String?) throws -> String {
        let reminder = identifier.flatMap { store.calendarItem(withIdentifier: $0) as? EKReminder } ?? EKReminder(eventStore: store)
        reminder.title = draft.title
        reminder.notes = draft.notes
        reminder.url = draft.target.deepLink
        reminder.dueDateComponents = draft.due
        reminder.alarms?.forEach { reminder.removeAlarm($0) }
        if let date = Calendar.current.date(from: draft.due) { reminder.addAlarm(EKAlarm(absoluteDate: date)) }
        reminder.calendar = lists.first { $0.calendarIdentifier == listID } ?? reminder.calendar ?? defaultList
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    func remove(_ identifier: String) throws {
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return }
        try store.remove(reminder, commit: true)
    }

    /// Odhacza przypomnienia faktur opłaconych i paczek rozliczonych (wywoływane po zmianach w bazie).
    func completeFinished(links: ReminderLinkRepository) {
        guard hasAccess, let finished = try? links.finished() else { return }
        var changed = false
        for (target, identifier) in finished {
            guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
                try? links.unlink(target)   // przypomnienie usunięte w aplikacji Przypomnienia
                continue
            }
            if !reminder.isCompleted {
                reminder.isCompleted = true
                try? store.save(reminder, commit: false)
                changed = true
            }
            try? links.unlink(target)
        }
        if changed { try? store.commit() }
    }

    /// Obserwuje zmiany statusów faktur i odhacza zakończone przypomnienia.
    func start(database: AppDatabase, links: @escaping @MainActor @Sendable () -> ReminderLinkRepository?) {
        authorization = EKEventStore.authorizationStatus(for: .reminder)
        let region = DatabaseRegionObservation(tracking: [Table("invoice"), Table("reminderLink")])
        observation = region.start(in: database.writer, onError: { _ in }, onChange: { [weak self] _ in
            Task { @MainActor in
                guard let self, let repo = links() else { return }
                self.completeFinished(links: repo)
            }
        })
        if let repo = links() { completeFinished(links: repo) }
    }
}

/// Domyślne treści przypomnień w języku interfejsu.
enum ReminderDrafts {
    static func invoice(_ invoice: Invoice, today: LocalDate = .today()) -> ReminderDraft {
        let title: String
        switch invoice.status {
        case .disputed: title = String(localized: "Wyjaśnij fakturę: \(invoice.sellerName) (\(invoice.invoiceNumber))")
        case .sentForPayment: title = String(localized: "Sprawdź zapłatę: \(invoice.sellerName) (\(invoice.invoiceNumber))")
        default: title = String(localized: "Zapłać: \(invoice.sellerName) (\(invoice.invoiceNumber))")
        }
        var lines = [
            String(localized: "Faktura \(invoice.invoiceNumber)"),
            String(localized: "Sprzedawca: \(invoice.sellerName), NIP \(invoice.sellerNIP)"),
            String(localized: "Kwota: \(invoice.amountGross.money(invoice.currency))"),
        ]
        if let due = invoice.paymentDueDate { lines.append(String(localized: "Termin płatności: \(due.formatted)")) }
        if !invoice.bankAccountNumber.isEmpty { lines.append(String(localized: "Rachunek: \(invoice.bankAccountNumber.groupedNRB)")) }
        if invoice.isSplitPayment { lines.append(String(localized: "Mechanizm podzielonej płatności (MPP)")) }
        let day = ReminderSchedule.invoiceDay(dueDate: invoice.paymentDueDate, today: today)
        return ReminderDraft(target: .invoice(invoice.id), title: title, notes: lines.joined(separator: "\n"),
                             due: ReminderSchedule.components(day))
    }

    static func paymentFile(_ file: PaymentFile, invoices: [Invoice], today: LocalDate = .today()) -> ReminderDraft {
        let bank = BankDetection.label(for: file.bankKey).nonEmptyOr(file.format.label)
        let title = String(localized: "Zaimportuj przelewy w banku: \(bank), \(file.totalAmount.money())")
        var lines = [String(localized: "Plik: \(file.fileName)"), String(localized: "Rachunek obciążany: \(file.debitAccount.groupedNRB)")]
        lines += invoices.map { "• \($0.sellerName) — \($0.invoiceNumber) — \($0.amountGross.money($0.currency))" }
        return ReminderDraft(target: .paymentFile(file.id), title: title, notes: lines.joined(separator: "\n"),
                             due: ReminderSchedule.components(ReminderSchedule.paymentFileDay(today: today)))
    }
}
