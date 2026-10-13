import Foundation

/// Stan blokady aplikacji (Face ID / kod urządzenia) — czysta logika bez LocalAuthentication.
///
/// Okno Face ID przełącza aplikację w stan nieaktywny, a po jego zamknięciu iOS zgłasza
/// powrót do stanu aktywnego. Te przejścia nie mogą ponownie zablokować aplikacji,
/// a znacznik zejścia w tło musi być czyszczony po każdym powrocie i po odblokowaniu.
public struct AppLockState: Equatable, Sendable {
    public private(set) var isEnabled: Bool
    public private(set) var isLocked: Bool
    public private(set) var isAuthenticating = false
    public let gracePeriod: TimeInterval
    private var backgroundedAt: Date?

    public init(enabled: Bool, gracePeriod: TimeInterval = 30) {
        isEnabled = enabled
        isLocked = enabled
        self.gracePeriod = gracePeriod
    }

    /// Aplikacja zeszła w tło (nie: okno Face ID, które daje tylko stan nieaktywny).
    public mutating func didEnterBackground(at now: Date) {
        guard isEnabled, !isAuthenticating else { return }
        backgroundedAt = now
    }

    /// Aplikacja znów aktywna: blokada tylko po dłuższym pobycie w tle.
    public mutating func didBecomeActive(at now: Date) {
        defer { backgroundedAt = nil }
        guard isEnabled, !isAuthenticating, let since = backgroundedAt,
              now.timeIntervalSince(since) > gracePeriod else { return }
        isLocked = true
    }

    /// Czy rozpocząć uwierzytelnienie (blokuje równoległe wywołania Face ID).
    public mutating func beginAuthentication() -> Bool {
        guard isLocked, !isAuthenticating else { return false }
        isAuthenticating = true
        return true
    }

    public mutating func finishAuthentication(success: Bool) {
        isAuthenticating = false
        if success {
            isLocked = false
            backgroundedAt = nil
        }
    }

    public mutating func enable() {
        isEnabled = true
        backgroundedAt = nil
    }

    public mutating func disable() {
        isEnabled = false
        isLocked = false
        isAuthenticating = false
        backgroundedAt = nil
    }
}
