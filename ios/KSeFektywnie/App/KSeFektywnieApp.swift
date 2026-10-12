import SwiftUI
import StoreKit

@main
struct KSeFektywnieApp: App {
    @State private var model = AppModel.live()
    @State private var lock = AppLock()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(lock)
                .task { await TipJar.finishPendingTransactions() }
        }
    }
}
