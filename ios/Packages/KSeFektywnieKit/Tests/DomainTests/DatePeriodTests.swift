import Foundation
import Testing
@testable import Domain

@Suite("Okres na listach")
struct DatePeriodTests {
    func d(_ iso: String) -> LocalDate { LocalDate(iso: iso)! }

    @Test("Ten miesiąc i poprzedni miesiąc, także na przełomie roku i w lutym przestępnym")
    func months() {
        #expect(DatePeriod.thisMonth.bounds(today: d("2026-10-15")) == d("2026-10-01")...d("2026-10-31"))
        #expect(DatePeriod.previousMonth.bounds(today: d("2026-10-15")) == d("2026-09-01")...d("2026-09-30"))
        #expect(DatePeriod.previousMonth.bounds(today: d("2027-01-31")) == d("2026-12-01")...d("2026-12-31"))
        #expect(DatePeriod.previousMonth.bounds(today: d("2028-03-31")) == d("2028-02-01")...d("2028-02-29"))
        #expect(DatePeriod.all.bounds(today: d("2026-10-15")) == nil)
    }

    @Test("Własny zakres jest domknięty i odporny na odwrócone daty")
    func custom() {
        let period = DatePeriod.custom(from: d("2026-09-20"), to: d("2026-09-10"))
        #expect(period.contains(d("2026-09-10")))
        #expect(period.contains(d("2026-09-20")))
        #expect(!period.contains(d("2026-09-21")))
        #expect(DatePeriod.all.contains(d("1999-01-01")))
    }

    @Test("Przesuwanie o miesiące przycina dzień")
    func addingMonths() {
        #expect(d("2026-03-31").addingMonths(-1) == d("2026-02-28"))
        #expect(d("2026-01-15").addingMonths(-1) == d("2025-12-15"))
        #expect(d("2026-12-15").addingMonths(1) == d("2027-01-15"))
    }
}
