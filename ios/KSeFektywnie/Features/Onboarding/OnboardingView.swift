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
                        do { try model.startDemo() } catch { self.error = error.localizedDescription }
                    }
                    .frame(maxWidth: .infinity)
                } footer: {
                    Text("Fikcyjna firma i faktury, bez łączenia z KSeF. Dane demo usuniesz w Ustawieniach.")
                }
            }
            .navigationTitle("Konfiguracja")
        }
    }

    private func save() {
        do {
            try model.createCompany(nip: nip.filter(\.isNumber), name: name.trimmingCharacters(in: .whitespaces),
                                    address: address.trimmingCharacters(in: .whitespacesAndNewlines), environment: environment)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
