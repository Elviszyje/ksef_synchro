import Foundation
import UIKit
import BackgroundTasks
import UserNotifications
import AppServices
import KSeFClient

/// Synchronizacja w tle (BGAppRefreshTask) i powiadomienia o nowych fakturach.
/// iOS sam decyduje, kiedy uruchomić zadanie — to uzupełnienie, nie gwarancja.
enum BackgroundSync {
    static let taskID = "pl.ksefektywnie.app.refresh"

    static var notificationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "newInvoiceNotifications") }
        set { UserDefaults.standard.set(newValue, forKey: "newInvoiceNotifications") }
    }

    /// Ostatnie uruchomienie synchronizacji przez system i jego wynik. iOS sam wybiera moment
    /// (albo nie uruchamia jej wcale), więc bez tego zapisu nie da się odróżnić „system nie
    /// uruchomił” od „uruchomił, ale się nie udało”.
    static var lastRun: (date: Date, outcome: String)? {
        get {
            let defaults = UserDefaults.standard
            guard let date = defaults.object(forKey: "backgroundSyncLastRunAt") as? Date else { return nil }
            return (date, defaults.string(forKey: "backgroundSyncLastOutcome") ?? "")
        }
        set {
            UserDefaults.standard.set(newValue?.date, forKey: "backgroundSyncLastRunAt")
            UserDefaults.standard.set(newValue?.outcome, forKey: "backgroundSyncLastOutcome")
        }
    }

    /// Czy system w ogóle pozwala tej aplikacji odświeżać się w tle (ustawienie użytkownika,
    /// tryb niskiego zużycia energii).
    static var isAllowedBySystem: Bool { UIApplication.shared.backgroundRefreshStatus == .available }

    /// Prosi system o kolejne uruchomienie po upływie interwału synchronizacji firmy.
    static func schedule(afterHours hours: Int) {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date().addingTimeInterval(TimeInterval(max(1, hours) * 3600))
        try? BGTaskScheduler.shared.submit(request)
    }

    static func requestNotificationPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    static func notifyNewInvoices(_ count: Int) async {
        guard notificationsEnabled, count > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Nowe faktury w KSeF")
        content.body = String(localized: "Pobrano nowe faktury kosztowe: \(count).")
        content.sound = .default
        let request = UNNotificationRequest(identifier: "new-invoices-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

extension AppModel {
    /// Wywoływane przez system w tle: krótka synchronizacja każdej firmy z tokenem (mały budżet XML)
    /// i jedno powiadomienie o nowych fakturach.
    func backgroundRefresh() async {
        // Bez dostępu do bazy (telefon jeszcze nieodblokowany po restarcie) nie znamy interwału —
        // i tak prosimy o kolejne uruchomienie, żeby łańcuch odświeżeń się nie urwał.
        defer {
            if let hours = companies.map(\.syncIntervalHours).min() ?? (databaseUnavailable ? 6 : nil) {
                BackgroundSync.schedule(afterHours: hours)
            }
        }
        func record(_ outcome: String) { BackgroundSync.lastRun = (Date(), outcome) }
        guard !databaseUnavailable else {
            record(String(localized: "Baza danych była niedostępna (telefon nie został jeszcze odblokowany po uruchomieniu)."))
            return
        }
        let connected = companies.filter { Keychain.ksefToken(for: $0.id) != nil }
        guard !connected.isEmpty else {
            if company != nil { record(KSeFError.missingToken.userMessage) }
            return
        }
        var outcomes: [String] = []
        var newInvoices = 0
        for target in connected {
            let prefix = connected.count > 1 ? "\(target.name): " : ""
            do {
                let client = try makeClient(for: target)
                let result = try await KSeFSyncService(company: target, source: client, db: database, device: deviceID).run(xmlBudget: 5)
                outcomes.append(prefix + SyncSummary.text(result))
                newInvoices += result.new
                await KSeFSendService(company: target, sender: client, db: database, device: deviceID).refreshPending()
            } catch {
                outcomes.append(prefix + error.userMessage)
            }
        }
        record(outcomes.joined(separator: "\n"))
        await BackgroundSync.notifyNewInvoices(newInvoices)
        reload()
    }
}
