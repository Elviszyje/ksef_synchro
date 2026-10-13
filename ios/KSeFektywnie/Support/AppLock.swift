import Foundation
import LocalAuthentication
import Observation
import AppServices

/// Blokada aplikacji Face ID / Touch ID z kodem urządzenia jako zapasem.
/// Logika przejść jest w `AppLockState` (testy w pakiecie); tu tylko LocalAuthentication.
@Observable
final class AppLock {
    private(set) var state: AppLockState

    var isEnabled: Bool { state.isEnabled }
    var isLocked: Bool { state.isLocked }
    var isAuthenticating: Bool { state.isAuthenticating }

    init() {
        var grace: TimeInterval = 30
        #if DEBUG
        // Testy na symulatorze: -lockGraceSeconds 2
        if UserDefaults.standard.object(forKey: "lockGraceSeconds") != nil {
            grace = UserDefaults.standard.double(forKey: "lockGraceSeconds")
        }
        #endif
        state = AppLockState(enabled: UserDefaults.standard.bool(forKey: "appLockEnabled"), gracePeriod: grace)
    }

    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return String(localized: "kod urządzenia")
        }
    }

    var isAvailable: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }

    func didEnterBackground() { state.didEnterBackground(at: Date()) }

    func didBecomeActive() { state.didBecomeActive(at: Date()) }

    /// Jedno wywołanie Face ID naraz; wynik zapisany niezależnie od zmian stanu sceny w trakcie.
    func unlock() async {
        guard state.beginAuthentication() else { return }
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Anuluj")
        let success = (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                         localizedReason: String(localized: "Odblokuj dostęp do faktur"))) ?? false
        state.finishAuthentication(success: success)
    }

    /// Włączenie wymaga udanego uwierzytelnienia, żeby nie zablokować się bez dostępu.
    func enable() async -> Bool {
        let context = LAContext()
        guard (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                 localizedReason: String(localized: "Potwierdź włączenie blokady"))) == true else { return false }
        state.enable()
        UserDefaults.standard.set(true, forKey: "appLockEnabled")
        return true
    }

    func disable() {
        state.disable()
        UserDefaults.standard.set(false, forKey: "appLockEnabled")
    }
}
