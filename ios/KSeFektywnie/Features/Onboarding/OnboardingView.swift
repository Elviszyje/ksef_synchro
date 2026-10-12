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

    private var nipValid: Bool { Validation.isValidNIP(nip) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Witaj w KS-eFektywnie").font(.title2.bold())
                        Text("Faktury kosztowe z KSeF, pliki przelewów i rozliczanie wyciągów — wszystko na Twoim telefonie, bez zakładania konta.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

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

                Section {
                    TextField("NIP", text: $nip)
                        .keyboardType(.numberPad)
                        .textContentType(.none)
                    TextField("Nazwa firmy", text: $name)
                    TextField("Adres (do plików bankowych)", text: $address, axis: .vertical)
                } header: {
                    Text("Twoja firma")
                } footer: {
                    if !nip.isEmpty && !nipValid {
                        Text("Nieprawidłowy NIP — sprawdź 10 cyfr.").foregroundStyle(.red)
                    }
                }

                Section {
                    Picker("Środowisko KSeF", selection: $environment) {
                        ForEach(KSeFEnvironment.allCases, id: \.self) { env in
                            Text(env.label).tag(env)
                        }
                    }
                } footer: {
                    Text("Środowisko testowe służy do prób i ma osobne dane oraz tokeny. Do pracy na prawdziwych fakturach wybierz produkcyjne.")
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }

                Section {
                    Button("Dalej") { save() }
                        .disabled(!nipValid || name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .frame(maxWidth: .infinity)
                }

                Section {
                    Button("Wypróbuj na przykładowych danych") {
                        do { try model.startDemo() } catch { self.error = error.userMessage }
                    }
                    .frame(maxWidth: .infinity)
                } footer: {
                    Text("Fikcyjna firma i faktury, bez łączenia z KSeF. Dane demo usuniesz w Ustawieniach.")
                }
            }
            .navigationTitle("Konfiguracja")
            .task { backup = await CloudSync.availableBackup() }
        }
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
