import Foundation
import LocalAuthentication
import Observation

/// Blokada aplikacji Face ID / Touch ID z kodem urządzenia jako zapasem.
@Observable
final class AppLock {
    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "appLockEnabled") }
    }
    private(set) var isLocked: Bool
    private var backgroundedAt: Date?
    /// Krótki powrót z tła (np. z arkusza udostępniania) nie wymaga ponownego uwierzytelnienia.
    let gracePeriod: TimeInterval = 30

    init() {
        let enabled = UserDefaults.standard.bool(forKey: "appLockEnabled")
        isEnabled = enabled
        isLocked = enabled
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

    func didEnterBackground() { backgroundedAt = Date() }

    func willEnterForeground() {
        guard isEnabled, let at = backgroundedAt, Date().timeIntervalSince(at) > gracePeriod else { return }
        isLocked = true
    }

    func unlock() async {
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Anuluj")
        do {
            if try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                localizedReason: String(localized: "Odblokuj dostęp do faktur")) {
                isLocked = false
            }
        } catch {
            isLocked = true
        }
    }

    /// Włączenie wymaga udanego uwierzytelnienia, żeby nie zablokować się bez dostępu.
    func enable() async -> Bool {
        let context = LAContext()
        guard (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                 localizedReason: String(localized: "Potwierdź włączenie blokady"))) == true else { return false }
        isEnabled = true
        return true
    }
}
