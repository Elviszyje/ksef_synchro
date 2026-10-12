import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppLock.self) private var lock
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.company == nil {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        // Rozmycie w przełączniku aplikacji i ekran blokady.
        .overlay {
            if lock.isLocked || scenePhase != .active && lock.isEnabled {
                LockScreen()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: lock.didEnterBackground()
            case .active: lock.willEnterForeground()
            default: break
            }
        }
    }
}

enum AppTab: String, Hashable {
    case invoices, sales, payments, statements, settings
}

struct MainTabView: View {
    @State private var selection: AppTab = DebugLaunch.initialTab ?? .invoices

    var body: some View {
        TabView(selection: $selection) {
            Tab("Faktury", systemImage: "doc.text", value: .invoices) { InvoicesView() }
            Tab("Sprzedaż", systemImage: "square.and.pencil", value: .sales) { SalesListView() }
            Tab("Przelewy", systemImage: "banknote", value: .payments) {
                ComingSoonView(title: "Przelewy", symbol: "banknote")
            }
            Tab("Wyciągi", systemImage: "tray.and.arrow.down", value: .statements) {
                ComingSoonView(title: "Wyciągi", symbol: "tray.and.arrow.down")
            }
            Tab("Ustawienia", systemImage: "gearshape", value: .settings) { SettingsView() }
        }
    }
}

/// Argumenty uruchomienia do zrzutów ekranu i testów UI (tylko Debug):
/// `-demo`, `-tab sales`, `-open-sale 2` (otwiera n-ty szkic faktury sprzedażowej).
enum DebugLaunch {
    static var initialTab: AppTab? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "tab").flatMap(AppTab.init(rawValue:))
        #else
        nil
        #endif
    }

    static var openSaleIndex: Int? {
        #if DEBUG
        let value = UserDefaults.standard.integer(forKey: "open-sale")
        return value > 0 ? value : nil
        #else
        nil
        #endif
    }
}

struct LockScreen: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill").font(.system(size: 48)).foregroundStyle(.secondary)
                Text("KS-eFektywnie").font(.title2.bold())
                if lock.isLocked {
                    Button("Odblokuj") { Task { await lock.unlock() } }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .task { if lock.isLocked { await lock.unlock() } }
    }
}

struct ComingSoonView: View {
    let title: LocalizedStringKey
    let symbol: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: symbol)
            } description: {
                Text("Ta część aplikacji pojawi się w kolejnej wersji roboczej.")
            }
            .navigationTitle(title)
        }
    }
}
