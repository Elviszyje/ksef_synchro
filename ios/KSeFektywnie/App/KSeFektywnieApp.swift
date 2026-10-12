import SwiftUI
import StoreKit

@main
struct KSeFektywnieApp: App {
    @State private var model = AppModel.live()
    @State private var lock = AppLock()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(lock)
                .task { await TipJar.finishPendingTransactions() }
                .task { await model.cloud.start() }
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
