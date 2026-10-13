import Foundation
import Testing
@testable import AppServices

@Suite("Blokada Face ID")
struct AppLockStateTests {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    @Test("Zgłoszony błąd: po odblokowaniu Face ID powrót do stanu aktywnego nie blokuje ponownie")
    func unlockAfterLongBackground() {
        var lock = AppLockState(enabled: true)
        let began1 = lock.beginAuthentication()
        #expect(began1)
        lock.finishAuthentication(success: true)
        #expect(!lock.isLocked)

        lock.didEnterBackground(at: t0)
        lock.didBecomeActive(at: t0.addingTimeInterval(120))
        #expect(lock.isLocked)

        // Okno Face ID: nieaktywna → aktywna, a sukces przychodzi przed albo po powrocie.
        let began2 = lock.beginAuthentication()
        #expect(began2)
        lock.finishAuthentication(success: true)
        lock.didBecomeActive(at: t0.addingTimeInterval(125))
        #expect(!lock.isLocked)

        // Kolejne powroty bez zejścia w tło też nie blokują.
        lock.didBecomeActive(at: t0.addingTimeInterval(500))
        #expect(!lock.isLocked)
    }

    @Test("Powrót z tła w czasie trwania Face ID nie nadpisuje wyniku")
    func activationDuringAuthentication() {
        var lock = AppLockState(enabled: true)
        lock.didEnterBackground(at: t0)
        lock.didBecomeActive(at: t0.addingTimeInterval(60))
        let began3 = lock.beginAuthentication()
        #expect(began3)
        lock.didEnterBackground(at: t0.addingTimeInterval(61))
        lock.didBecomeActive(at: t0.addingTimeInterval(200))
        lock.finishAuthentication(success: true)
        #expect(!lock.isLocked)
        lock.didBecomeActive(at: t0.addingTimeInterval(201))
        #expect(!lock.isLocked)
    }

    @Test("Krótki pobyt w tle mieści się w okresie karencji")
    func gracePeriod() {
        var lock = AppLockState(enabled: true)
        lock.finishAuthentication(success: true)
        _ = lock.beginAuthentication()
        lock.didEnterBackground(at: t0)
        lock.didBecomeActive(at: t0.addingTimeInterval(10))
        #expect(!lock.isLocked)
    }

    @Test("Tylko jedno uwierzytelnienie naraz; anulowanie zostawia blokadę")
    func singleAuthentication() {
        var lock = AppLockState(enabled: true)
        let began4 = lock.beginAuthentication()
        #expect(began4)
        let began5 = lock.beginAuthentication()
        #expect(!began5)
        lock.finishAuthentication(success: false)
        #expect(lock.isLocked && !lock.isAuthenticating)
        let began6 = lock.beginAuthentication()
        #expect(began6)
    }

    @Test("Wyłączona blokada nigdy nie blokuje")
    func disabled() {
        var lock = AppLockState(enabled: true)
        lock.disable()
        #expect(!lock.isLocked)
        lock.didEnterBackground(at: t0)
        lock.didBecomeActive(at: t0.addingTimeInterval(1000))
        #expect(!lock.isLocked)
        let began7 = lock.beginAuthentication()
        #expect(!began7)
        lock.enable()
        #expect(!lock.isLocked, "włączenie po udanym uwierzytelnieniu nie blokuje od razu")
    }
}
