import SwiftUI
import Domain
import KSeFClient

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppLock.self) private var lock
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Firma") {
                    NavigationLink { CompanySettingsView() } label: {
                        LabeledContent(model.company?.name ?? "", value: model.company?.nip ?? "")
                    }
                    NavigationLink { BankAccountsView() } label: {
                        LabeledContent("Rachunki bankowe", value: "\(model.bankAccounts.count)")
                    }
                    NavigationLink { CatalogView() } label: {
                        Label("Katalog pozycji", systemImage: "shippingbox")
                    }
                }

                Section {
                    NavigationLink { KSeFSettingsView() } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Połączenie z KSeF")
                                Text(model.ksefToken == nil ? "Nie skonfigurowano" : "Token zapisany")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "link") }
                    }
                }

                Section {
                    NavigationLink { CloudSettingsView() } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("iCloud Drive")
                                Text(model.cloud.isEnabled ? "Kopia danych włączona" : "Wyłączona")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "icloud") }
                    }
                }

                Section {
                    Toggle(isOn: Binding(get: { lock.isEnabled }, set: { on in
                        if on { Task { _ = await lock.enable() } } else { lock.isEnabled = false }
                    })) {
                        Label("Blokada \(lock.biometryName)", systemImage: "faceid")
                    }
                    .disabled(!lock.isAvailable)
                } header: {
                    Text("Bezpieczeństwo")
                } footer: {
                    Text("Po włączeniu aplikacja wymaga uwierzytelnienia przy uruchomieniu i po powrocie z tła.")
                }

                Section("Pomoc") {
                    NavigationLink { KSeFGuideView() } label: {
                        Label("Jak połączyć się z KSeF", systemImage: "questionmark.circle")
                    }
                }

                Section {
                    NavigationLink { TipJarView() } label: {
                        Label("Tip for developer", systemImage: "cup.and.saucer")
                    }
                } footer: {
                    Text("Aplikacja jest bezpłatna i nie wyświetla reklam. Napiwek wspiera jej dalszy rozwój i niczego nie odblokowuje.")
                }

                Section {
                    LabeledContent("Wersja", value: Bundle.main.appVersion)
                    Button("Usuń wszystkie dane", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle("Ustawienia")
            .confirmationDialog("Usunąć wszystkie dane z tego iPhone'a?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Usuń", role: .destructive) { try? model.deleteAllData() }
            } message: {
                Text("Faktury, pliki przelewów, wyciągi i token KSeF zostaną usunięte z telefonu. Pliki w iCloud Drive też znikną przy najbliższym zapisie — wyłącz wcześniej kopię w iCloud, jeśli chcesz je zachować.")
            }
        }
    }
}

struct NotificationsToggle: View {
    @State private var enabled = BackgroundSync.notificationsEnabled

    var body: some View {
        Toggle(isOn: Binding(get: { enabled }, set: { on in
            if on {
                Task {
                    let granted = await BackgroundSync.requestNotificationPermission()
                    enabled = granted
                    BackgroundSync.notificationsEnabled = granted
                }
            } else {
                enabled = false
                BackgroundSync.notificationsEnabled = false
            }
        })) {
            Label("Powiadomienia o nowych fakturach", systemImage: "bell.badge")
        }
    }
}

struct CompanySettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var address = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("NIP", value: model.company?.nip ?? "")
                TextField("Nazwa firmy", text: $name)
                TextField("Adres (do plików bankowych)", text: $address, axis: .vertical)
            } footer: {
                Text("W plikach Elixir-0 nazwa i adres są skracane do 35 znaków każde.")
            }
        }
        .navigationTitle("Firma")
        .onAppear {
            name = model.company?.name ?? ""
            address = model.company?.address ?? ""
        }
        .onDisappear {
            try? model.updateCompany { $0.name = name; $0.address = address }
        }
    }
}

struct BankAccountsView: View {
    @Environment(AppModel.self) private var model
    @State private var number = ""
    @State private var label = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                ForEach(model.bankAccounts) { account in
                    VStack(alignment: .leading) {
                        Text(account.label.isEmpty ? BankDetection.label(for: account.bankKey).nonEmptyOr(String(localized: "Rachunek")) : account.label)
                        Text(account.accountNumber.groupedNRB).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text("Format pliku: \(PaymentFileFormat.forBank(account.bankKey).label)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .onDelete { idx in idx.map { model.bankAccounts[$0] }.forEach { try? model.deleteBankAccount($0) } }
            } footer: {
                Text("Rachunek obciążany przy przelewach. Format pliku dla banku jest dobierany automatycznie: Erste i mBank mają własne formaty, pozostałe banki Elixir-0.")
            }

            Section("Dodaj rachunek") {
                TextField("Numer rachunku (26 cyfr)", text: $number).keyboardType(.numberPad)
                TextField("Opis (opcjonalnie)", text: $label)
                if let error { Text(error).foregroundStyle(.red) }
                Button("Dodaj") { add() }.disabled(number.filter(\.isNumber).count != 26)
            }
        }
        .navigationTitle("Rachunki bankowe")
    }

    private func add() {
        guard Validation.isValidNRB(number) else {
            error = String(localized: "Nieprawidłowy numer rachunku — sprawdź cyfry kontrolne.")
            return
        }
        do {
            try model.addBankAccount(number.filter(\.isNumber), label: label)
            number = ""
            label = ""
            error = nil
        } catch {
            self.error = error.userMessage
        }
    }
}

struct KSeFSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var token = ""
    @State private var testState: TestState = .idle
    @State private var pendingXML = 0

    enum TestState: Equatable { case idle, running, ok, failed(String) }

    var body: some View {
        Form {
            Section {
                Picker("Środowisko", selection: Binding(
                    get: { model.company?.ksefEnvironment ?? .production },
                    set: { env in try? model.updateCompany { $0.ksefEnvironment = env } })) {
                    ForEach(KSeFEnvironment.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                LabeledContent("NIP", value: model.company?.nip ?? "")
            }

            Section {
                SecureField("Wklej token KSeF", text: $token)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                Button("Zapisz token") {
                    model.ksefToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
                    token = ""
                    testState = .idle
                }
                .disabled(token.isEmpty)
                if model.ksefToken != nil {
                    Button("Usuń token", role: .destructive) { model.ksefToken = nil }
                }
            } header: {
                Text("Token")
            } footer: {
                Text("Token jest przechowywany wyłącznie w pęku kluczy tego iPhone'a. Nie trafia do kopii zapasowej ani do iCloud.")
            }

            Section {
                Button {
                    Task { await test() }
                } label: {
                    HStack {
                        Text("Testuj połączenie")
                        Spacer()
                        switch testState {
                        case .running: ProgressView()
                        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                        case .idle: EmptyView()
                        }
                    }
                }
                .disabled(model.ksefToken == nil || testState == .running)
                if case .failed(let message) = testState { Text(message).font(.footnote).foregroundStyle(.red) }
                if testState == .ok { Text("Połączenie działa.").font(.footnote).foregroundStyle(.green) }

                Button {
                    Task { await model.sync(); refreshPending() }
                } label: {
                    HStack {
                        Text("Synchronizuj teraz")
                        Spacer()
                        if model.syncInProgress { ProgressView() }
                    }
                }
                .disabled(model.ksefToken == nil || model.syncInProgress)
                if let message = model.syncMessage { Text(message).font(.footnote) }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let last = model.company?.lastSyncAt {
                        Text("Ostatnia synchronizacja: \(last.formatted(date: .abbreviated, time: .shortened))")
                    }
                    if pendingXML > 0 { Text("Faktury czekające na pobranie treści: \(pendingXML)") }
                }
            }

            Section {
                NotificationsToggle()
            } footer: {
                Text("Aplikacja sprawdza KSeF w tle mniej więcej co tyle godzin, ile wynosi interwał synchronizacji. Moment uruchomienia wybiera iOS, więc nie jest to gwarantowane — po otwarciu aplikacji przeciągnij listę faktur, aby zsynchronizować od razu.")
            }

            Section {
                NavigationLink { KSeFGuideView() } label: {
                    Label("Instrukcja krok po kroku", systemImage: "list.number")
                }
            }
        }
        .navigationTitle("KSeF")
        .onAppear(perform: refreshPending)
    }

    private func refreshPending() {
        pendingXML = (try? model.syncStore?.pendingXMLCount()) ?? 0
    }

    private func test() async {
        testState = .running
        do {
            try await model.testConnection()
            testState = .ok
        } catch {
            testState = .failed(error.userMessage)
        }
    }
}

extension Bundle {
    var appVersion: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}

extension String {
    func nonEmptyOr(_ fallback: String) -> String { isEmpty ? fallback : self }

    /// NRB w grupach: `61 1090 1014 0000 0712 1981 2874`.
    var groupedNRB: String {
        guard count == 26 else { return self }
        var out = String(prefix(2))
        var rest = dropFirst(2)
        while !rest.isEmpty { out += " " + rest.prefix(4); rest = rest.dropFirst(4) }
        return out
    }
}
