import SwiftUI
import GRDB

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppLock.self) private var lock
    @Environment(\.scenePhase) private var scenePhase
    /// Ponowne otwarcie bazy, gdy przy starcie była niedostępna.
    var retryStartup: () -> Void = {}

    var body: some View {
        Group {
            if model.databaseUnavailable {
                DatabaseUnavailableView(details: model.startupError, retry: retryStartup)
            } else if model.company == nil || DebugLaunch.showWelcome {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        // Rozmycie w przełączniku aplikacji i ekran blokady.
        .overlay {
            if lock.isLocked || scenePhase != .active && lock.isEnabled {
                LockScreen(sceneIsActive: scenePhase == .active)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: lock.didEnterBackground()
            case .active:
                lock.didBecomeActive()
                model.refreshTokenState()
                Task { await model.syncIfStale() }
            default: break
            }
        }
    }
}

/// Baza nie dała się otworzyć przy starcie (zwykle: aplikacja uruchomiona w tle, zanim telefon
/// został odblokowany). Dane są na dysku — nie pokazujemy ekranu powitalnego, tylko ponawiamy.
struct DatabaseUnavailableView: View {
    @Environment(\.scenePhase) private var scenePhase
    let details: String?
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Dane są chwilowo niedostępne", systemImage: "lock.doc")
        } description: {
            Text("Nie udało się otworzyć bazy aplikacji. Twoje dane są bezpieczne — odblokuj telefon i spróbuj ponownie.")
            if let details { Text(details).font(.appCaption) }
        } actions: {
            Button("Spróbuj ponownie", action: retry)
                .buttonStyle(.glassProminent)
        }
        // Powrót na pierwszy plan oznacza odblokowany telefon. Bez próby przy samym pojawieniu się
        // widoku: przy trwałym błędzie każda nieudana próba odtwarza widok i zapętliłaby się.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { retry() }
        }
    }
}

enum AppTab: String, Hashable {
    /// `sales` nie ma własnej zakładki — to widok „Sprzedaż” w zakładce Faktury (argument `-tab sales`).
    case dashboard, invoices, sales, payments, statements, settings
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: AppTab = DebugLaunch.initialTab.map { $0 == .sales ? .invoices : $0 } ?? .dashboard
    @State private var invoiceKind: InvoiceKind = DebugLaunch.initialTab == .sales ? .sales : .cost
    @State private var flight = PaymentsFlight()
    @State private var reminderPresenter = ReminderPresenter()
    @State private var payableCount = 0

    var body: some View {
        TabView(selection: $selection) {
            Tab("Pulpit", systemImage: "chart.bar", value: .dashboard) {
                DashboardView(openPayments: { selection = .payments },
                              openInvoices: { invoiceKind = .cost; selection = .invoices })
            }
            Tab("Faktury", systemImage: "doc.text", value: .invoices) { InvoicesTab(kind: $invoiceKind) }
            Tab("Przelewy", systemImage: "arrow.left.arrow.right", value: .payments) { PaymentsView() }
                .badge(payableCount)
            Tab("Wyciągi", systemImage: "tray.and.arrow.down", value: .statements) { StatementsView() }
            Tab("Ustawienia", systemImage: "gearshape", value: .settings) { SettingsView() }
        }
        .environment(flight)
        .environment(reminderPresenter)
        .sheet(item: $reminderPresenter.request) { request in
            ReminderEditor(draft: request.draft, dueDate: request.dueDate, existing: request.existing, onSave: request.onSave)
        }
        .overlay { PaymentsFlightOverlay(tabFraction: 0.5).environment(flight) }
        .sensoryFeedback(.impact(weight: .light), trigger: flight.landings)
        .onChange(of: model.openTarget) { _, target in
            switch target {
            case .invoice?: invoiceKind = .cost; selection = .invoices
            case .paymentFile?: selection = .payments
            case nil: break
            }
        }
        .task { await observePayable() }
        .task { await model.syncIfStale() }
    }

    /// Licznik faktur „Do zapłaty” na zakładce Przelewy. Gdy leci miniaturka,
    /// licznik zmienia się dopiero przy jej lądowaniu.
    private func observePayable() async {
        guard let payments = model.payments else { return }
        do {
            for try await value in payments.observePayable().values(in: model.database.reader) {
                let count = value.count
                if !flight.flights.isEmpty && count > payableCount {
                    try? await Task.sleep(for: .milliseconds(700))
                }
                withAnimation(.snappy) { payableCount = count }
            }
        } catch {}
    }
}

/// Argumenty uruchomienia do zrzutów ekranu i testów UI (tylko Debug):
/// `-demo`, `-tab invoices|sales|payments|statements|settings` (domyślnie Pulpit), `-open-sale 2` (n-ty szkic sprzedaży), `-open-statement YES` (pierwszy wyciąg).
enum DebugLaunch {
    static var initialTab: AppTab? {
        #if DEBUG
        // Flagi otwierające coś na liście faktur działają tylko wtedy, gdy ta zakładka jest na ekranie.
        if let tab = UserDefaults.standard.string(forKey: "tab").flatMap(AppTab.init(rawValue:)) { return tab }
        return openInvoiceNumber != nil || autoSwipe != nil || dumpExports ? .invoices : nil
        #else
        nil
        #endif
    }

    /// `-open-invoice FV/2026/0008`
    static var openInvoiceNumber: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "open-invoice")
        #else
        nil
        #endif
    }

    /// `-auto-approve YES` razem z `-open-invoice`: po chwili zatwierdza fakturę (nagrywanie animacji).
    static var autoApprove: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "auto-approve")
        #else
        false
        #endif
    }

    /// `-auto-swipe disputed|accepted`: po chwili wykonuje gest na pierwszej fakturze listy.
    static var autoSwipe: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "auto-swipe")
        #else
        nil
        #endif
    }

    /// `-dump-exports YES`: zapisuje eksport listy faktur (xlsx i pdf) do Documents/exports (weryfikacja wyglądu).
    static var dumpExports: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "dump-exports")
        #else
        false
        #endif
    }

    /// `-store-shots YES`: zrzuty do sklepu — bez paska „Tryb demo”.
    static var storeShots: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "store-shots")
        #else
        false
        #endif
    }

    /// `-welcome YES`: plansza powitalna mimo istniejącej firmy, bez szukania kopii w iCloud (zrzuty do sklepu).
    static var showWelcome: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "welcome")
        #else
        false
        #endif
    }

    /// `-select-payable YES`: zaznacza wszystkie faktury w zakładce Przelewy (zrzuty ekranu).
    static var selectAllPayable: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "select-payable")
        #else
        false
        #endif
    }

    static var openPaymentHistory: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "open-payment-history")
        #else
        false
        #endif
    }

    static var openDashboard: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "open-dashboard")
        #else
        false
        #endif
    }

    static var openFirstStatement: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "open-statement")
        #else
        false
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
    let sceneIsActive: Bool

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill").font(.system(size: 48)).foregroundStyle(.secondary)
                Text("KS-eFektywnie").font(.appTitle2.bold())
                if lock.isLocked {
                    Button("Odblokuj") { Task { await lock.unlock() } }
                        .buttonStyle(.glassProminent)
                        .disabled(lock.isAuthenticating)
                }
            }
        }
        // Face ID uruchamia się sam przy każdym zablokowaniu, ale tylko w aktywnej scenie
        // (wywołane w stanie nieaktywnym kończy się błędem i zostawiało blokadę).
        .task(id: lock.isLocked && sceneIsActive) {
            if lock.isLocked && sceneIsActive { await lock.unlock() }
        }
    }
}
