import Foundation
import BackgroundTasks
import UserNotifications
import AppServices

/// Synchronizacja w tle (BGAppRefreshTask) i powiadomienia o nowych fakturach.
/// iOS sam decyduje, kiedy uruchomić zadanie — to uzupełnienie, nie gwarancja.
enum BackgroundSync {
    static let taskID = "pl.ksefektywnie.app.refresh"

    static var notificationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "newInvoiceNotifications") }
        set { UserDefaults.standard.set(newValue, forKey: "newInvoiceNotifications") }
    }

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
    /// Wywoływane przez system w tle: krótka synchronizacja (mały budżet XML) i powiadomienie.
    func backgroundRefresh() async {
        defer { if let hours = company?.syncIntervalHours { BackgroundSync.schedule(afterHours: hours) } }
        guard let company, ksefToken != nil, let client = try? makeClient() else { return }
        let service = KSeFSyncService(company: company, source: client, db: database, device: deviceID)
        guard let result = try? await service.run(xmlBudget: 5) else { return }
        await BackgroundSync.notifyNewInvoices(result.new)
        await refreshSalesSubmissions()
        reload()
    }
}
