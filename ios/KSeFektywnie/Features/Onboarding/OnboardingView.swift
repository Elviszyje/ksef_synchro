import SwiftUI
import Domain

/// Pierwsze uruchomienie: profil firmy. Token KSeF wpisuje się potem w Ustawieniach,
/// prowadzony przez przewodnik krok po kroku.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var nip = ""
    @State private var name = ""
    @State private var address = ""
    @State private var environment = KSeFEnvironment.production
    @State private var error: String?
    @State private var backup: (location: CloudSync.Location, companies: [String], writtenAt: Date)?
    @State private var restoring = false
    @State private var restoreProgress: (Int, Int) = (0, 0)
    /// Najpierw plansza powitalna, formularz firmy dopiero po „Połącz z KSeF”.
    @State private var showForm = false

    private var nipValid: Bool { Validation.isValidNIP(nip) }

    var body: some View {
        NavigationStack {
            WelcomeView(hasBackup: backup != nil, error: error,
                        connect: { showForm = true },
                        tryDemo: { do { try model.startDemo() } catch { self.error = error.userMessage } })
                .navigationDestination(isPresented: $showForm) { form }
                .task { if !DebugLaunch.showWelcome { backup = await CloudSync.availableBackup() } }
        }
    }

    private var form: some View {
            Form {
                if let backup {
                    Section {
                        Button {
                            Task { await restore(backup.location) }
                        } label: {
                            HStack {
                                Label("Przywróć dane z iCloud", systemImage: "icloud.and.arrow.down")
                                Spacer()
                                if restoring { ProgressView() }
                            }
                        }
                        .disabled(restoring)
                        if restoring && restoreProgress.1 > 0 {
                            ProgressView(value: Double(restoreProgress.0), total: Double(restoreProgress.1))
                        }
                    } header: {
                        Text("Znaleziono kopię")
                    } footer: {
                        Text("\(backup.companies.joined(separator: ", ")) — zapisano \(backup.writtenAt.formatted(date: .abbreviated, time: .shortened)). Token KSeF trzeba będzie wpisać ponownie.")
                    }
                }

                CompanyFieldsSection(nip: $nip, name: $name, address: $address)
                KSeFEnvironmentSection(environment: $environment)

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }

                Section {
                    Button("Dalej") { save() }
                        .buttonStyle(.appPrimary)
                        .disabled(!nipValid || name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

            }
            .appScreenBackground()
            .navigationTitle("Konfiguracja")
            .navigationBarTitleDisplayMode(.inline)
    }

    private func restore(_ location: CloudSync.Location) async {
        restoring = true
        defer { restoring = false }
        do {
            try await model.restoreFromCloud(location) { done, total in
                Task { @MainActor in restoreProgress = (done, total) }
            }
        } catch {
            self.error = error.userMessage
        }
    }

    private func save() {
        do {
            try model.createCompany(nip: nip.filter(\.isNumber), name: name.trimmingCharacters(in: .whitespaces),
                                    address: address.trimmingCharacters(in: .whitespacesAndNewlines), environment: environment)
        } catch {
            self.error = error.userMessage
        }
    }
}

/// Plansza powitalna: co robi aplikacja i dlaczego dane zostają na telefonie.
private struct WelcomeView: View {
    let hasBackup: Bool
    let error: String?
    let connect: () -> Void
    let tryDemo: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    AppMark(size: 36)
                    Text("KS-eFektywnie").font(.grotesk(17, .bold, relativeTo: .headline))
                }

                illustration.padding(.top, 30)

                Text("Z faktury prosto do przelewu.")
                    .font(.grotesk(34, .bold, relativeTo: .largeTitle))
                    .tracking(-1)
                    .padding(.top, 30)
                Text("Faktury z KSeF, pliki przelewów i rozliczanie wyciągów — na Twoim telefonie.")
                    .font(.grotesk(16, relativeTo: .body))
                    .foregroundStyle(Color.appMuted)
                    .padding(.top, 10)

                VStack(alignment: .leading, spacing: 10) {
                    point("Token KSeF zostaje w telefonie")
                    point("Bez konta i bez serwera")
                    point("Za darmo, bez abonamentu")
                }
                .padding(.top, 20)

                if let error {
                    Text(error).font(.appFootnote).foregroundStyle(Color.appDanger).padding(.top, 14)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                Button(action: connect) {
                    Text(hasBackup ? "Połącz z KSeF lub przywróć kopię" : "Połącz z KSeF")
                }
                .buttonStyle(.appPrimary)
                Button("Wypróbuj na przykładowych danych", action: tryDemo)
                    .font(.grotesk(15, .medium, relativeTo: .subheadline))
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .background(Color.appBackground)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    /// Faktura z KSeF zamienia się w plik dla banku.
    private var illustration: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Stal i Pręt Budmax Demo S.A.").font(.grotesk(15, .medium, relativeTo: .subheadline)).lineLimit(1)
                    Text(verbatim: "FV/2026/0005 · KSeF").font(.mono(12)).foregroundStyle(Color.appMuted)
                }
                Spacer(minLength: 8)
                Text(Decimal(24600).money()).font(.grotesk(16, .medium, relativeTo: .subheadline)).monospacedDigit()
            }
            .appCard(padding: 16)
            Image(systemName: "arrow.down")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.appOnPrimary)
                .frame(width: 36, height: 36)
                .background(Color.appPrimaryFill, in: .circle)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plik dla banku").font(.grotesk(15, .medium, relativeTo: .subheadline))
                        .foregroundStyle(Color.appOnGraphite)
                    Text(verbatim: "Erste · mBank · Elixir-0").font(.mono(12)).foregroundStyle(Color.appOnGraphiteMuted)
                }
                Spacer(minLength: 8)
                Text("gotowy")
                    .font(.grotesk(13, .bold, relativeTo: .footnote))
                    .foregroundStyle(Color.appGraphite)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.appMint, in: .capsule)
            }
            .padding(16)
            .background(Color.appFeatureCard, in: .rect(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.appMint.opacity(0.5)))
        }
        .accessibilityHidden(true)
    }

    private func point(_ text: LocalizedStringKey) -> some View {
        Label { Text(text).font(.grotesk(15, .medium, relativeTo: .subheadline)) } icon: {
            Image(systemName: "checkmark.circle").foregroundStyle(Color.appAccent)
        }
    }
}

/// Znak aplikacji: wiersze faktury przechodzące w strzałkę przelewu.
struct AppMark: View {
    var size: CGFloat = 36

    var body: some View {
        Canvas { context, canvas in
            let unit = canvas.width / 240
            var path = Path()
            path.move(to: CGPoint(x: 50 * unit, y: 74 * unit)); path.addLine(to: CGPoint(x: 142 * unit, y: 74 * unit))
            path.move(to: CGPoint(x: 50 * unit, y: 120 * unit)); path.addLine(to: CGPoint(x: 108 * unit, y: 120 * unit))
            path.move(to: CGPoint(x: 50 * unit, y: 166 * unit)); path.addLine(to: CGPoint(x: 182 * unit, y: 166 * unit))
            path.move(to: CGPoint(x: 150 * unit, y: 134 * unit)); path.addLine(to: CGPoint(x: 184 * unit, y: 166 * unit))
            path.addLine(to: CGPoint(x: 150 * unit, y: 198 * unit))
            context.stroke(path, with: .color(.appGraphite), style: StrokeStyle(lineWidth: 22 * unit, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .background(Color.appMint, in: .rect(cornerRadius: size * 0.28))
        .accessibilityHidden(true)
    }
}
