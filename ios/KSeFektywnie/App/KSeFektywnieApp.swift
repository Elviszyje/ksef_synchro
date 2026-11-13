import SwiftUI
import StoreKit
import Domain

@main
struct KSeFektywnieApp: App {
    @State private var model = AppModel.live()
    @State private var lock = AppLock()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            // Po ponownym otwarciu bazy powstaje nowy model — `id` odtwarza widoki i zadania na nim.
            RootView(retryStartup: { model = AppModel.live() })
                .id(ObjectIdentifier(model))
                .environment(model)
                .environment(lock)
                .task { await TipJar.finishPendingTransactions() }
                .task(id: ObjectIdentifier(model)) {
                    // Atrapa bez bazy nie może dotykać lustra iCloud ani Przypomnień.
                    guard !model.databaseUnavailable else { return }
                    model.reminders.start(database: model.database) { [model] in model.reminderLinks }
                    await model.cloud.start()
                }
                .onOpenURL { url in model.openTarget = ReminderTarget(deepLink: url) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, let hours = model.company?.syncIntervalHours {
                BackgroundSync.schedule(afterHours: hours)
            }
        }
        .backgroundTask(.appRefresh(BackgroundSync.taskID)) {
            await model.backgroundRefresh()
        }
    }
}
