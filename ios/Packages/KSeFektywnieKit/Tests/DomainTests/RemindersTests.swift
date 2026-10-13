import Foundation
import Testing
@testable import Domain

@Suite("Przypomnienia")
struct RemindersTests {
    let today = LocalDate(year: 2026, month: 10, day: 13)!

    @Test("Termin przypomnienia o fakturze")
    func invoiceDay() {
        #expect(ReminderSchedule.invoiceDay(dueDate: LocalDate(year: 2026, month: 10, day: 25), today: today) == LocalDate(year: 2026, month: 10, day: 23))
        // Termin za blisko albo minął — jutro.
        #expect(ReminderSchedule.invoiceDay(dueDate: LocalDate(year: 2026, month: 10, day: 14), today: today) == LocalDate(year: 2026, month: 10, day: 14))
        #expect(ReminderSchedule.invoiceDay(dueDate: LocalDate(year: 2026, month: 10, day: 1), today: today) == LocalDate(year: 2026, month: 10, day: 14))
        #expect(ReminderSchedule.invoiceDay(dueDate: nil, today: today) == LocalDate(year: 2026, month: 10, day: 14))
        // Przełom miesiąca.
        #expect(ReminderSchedule.invoiceDay(dueDate: LocalDate(year: 2026, month: 11, day: 1), today: today) == LocalDate(year: 2026, month: 10, day: 30))
    }

    @Test("Link w przypomnieniu prowadzi do rekordu")
    func deepLinks() {
        let id = UUID()
        for target in [ReminderTarget.invoice(id), .paymentFile(id)] {
            #expect(ReminderTarget(deepLink: target.deepLink) == target)
            #expect(ReminderTarget(recordType: target.recordType, recordID: id) == target)
        }
        #expect(ReminderTarget(deepLink: URL(string: "https://example.com/invoice/\(id)")!) == nil)
        #expect(ReminderTarget(deepLink: URL(string: "ksefektywnie://other/\(id)")!) == nil)
    }

    @Test("Godzina 9:00")
    func components() {
        let c = ReminderSchedule.components(today)
        #expect(c.year == 2026 && c.month == 10 && c.day == 13 && c.hour == 9 && c.minute == 0)
    }
}
