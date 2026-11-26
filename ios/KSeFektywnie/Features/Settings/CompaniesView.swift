import SwiftUI
import Domain

/// Pola firmy wspólne dla pierwszego uruchomienia i dodawania kolejnej firmy:
/// NIP z podpowiedzią z Białej Listy, nazwa i adres.
struct CompanyFieldsSection: View {
    @Binding var nip: String
    @Binding var name: String
    @Binding var address: String

    var body: some View {
        Section {
            TextField("NIP", text: $nip)
                .keyboardType(.numberPad)
                .textContentType(.none)
            WhiteListLookup(nip: nip, autoLookup: name.isEmpty && address.isEmpty) { taxpayer in
                name = taxpayer.name
                address = taxpayer.address
            }
            TextField("Nazwa firmy", text: $name)
            TextField("Adres (do plików bankowych)", text: $address, axis: .vertical)
        } header: {
            Text("Twoja firma")
        } footer: {
            if !nip.isEmpty && !Validation.isValidNIP(nip) {
                Text("Nieprawidłowy NIP — sprawdź 10 cyfr.").foregroundStyle(Color.appDanger)
            }
        }
    }
}

/// Wybór środowiska KSeF z wyjaśnieniem różnicy.
struct KSeFEnvironmentSection: View {
    @Binding var environment: KSeFEnvironment

    var body: some View {
        Section {
            Picker("Środowisko KSeF", selection: $environment) {
                ForEach(KSeFEnvironment.allCases, id: \.self) { env in
                    Text(env.label).tag(env)
                }
            }
        } footer: {
            Text("Środowisko testowe służy do prób i ma osobne dane oraz tokeny. Do pracy na prawdziwych fakturach wybierz produkcyjne.")
        }
    }
}

/// Dodanie kolejnej firmy: NIP, dane i (opcjonalnie od razu) token KSeF. Nowa firma staje się aktywna.
struct AddCompanyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var nip = ""
    @State private var name = ""
    @State private var address = ""
    @State private var environment = KSeFEnvironment.production
    @State private var token = ""
    @State private var error: String?

    private var canSave: Bool {
        Validation.isValidNIP(nip) && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                CompanyFieldsSection(nip: $nip, name: $name, address: $address)
                KSeFEnvironmentSection(environment: $environment)
                Section {
                    SecureField("Wklej token KSeF", text: $token)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                } header: {
                    Text("Token")
                } footer: {
                    Text("Każda firma ma własny token. Możesz go też wkleić później w Ustawieniach → Połączenie z KSeF. Token jest przechowywany wyłącznie w pęku kluczy tego iPhone'a.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(Color.appDanger) }
                }
            }
            .appScreenBackground()
            .navigationTitle("Nowa firma")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Dodaj", action: save).disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        do {
            try model.createCompany(nip: nip.filter(\.isNumber), name: name.trimmingCharacters(in: .whitespaces),
                                    address: address.trimmingCharacters(in: .whitespacesAndNewlines),
                                    environment: environment, token: token)
            dismiss()
        } catch {
            self.error = error.userMessage
        }
    }
}

/// Lista firm w Ustawieniach: wybór aktywnej i dodanie kolejnej (do limitu).
struct CompaniesSection: View {
    @Environment(AppModel.self) private var model
    @Binding var adding: Bool

    var body: some View {
        Section {
            ForEach(model.companies) { company in
                let active = company.id == model.company?.id
                Button { model.activate(company.id) } label: {
                    HStack(spacing: 12) {
                        InitialsAvatar(name: company.name, size: 36, prominent: active)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(company.name).font(.appHeadline).lineLimit(1)
                            Text("NIP \(company.nip)").font(.mono(12)).foregroundStyle(Color.appMuted)
                            if !model.hasToken(company) {
                                Text("Brak tokenu KSeF").font(.appCaption).foregroundStyle(Color.appWarning)
                            }
                        }
                        Spacer(minLength: 8)
                        if active {
                            Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.appAccent)
                        }
                    }
                }
                .tint(.primary)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
            if model.canAddCompany {
                Button { adding = true } label: { Label("Dodaj firmę", systemImage: "plus") }
                    .accessibilityIdentifier("add-company")
            }
        } header: {
            Text("Firmy")
        } footer: {
            Text("Zakładki pokazują dane zaznaczonej firmy. Każda firma ma własny token KSeF, rachunki i szablony. Można dodać najwyżej \(AppModel.maxCompanies) firmy.")
        }
    }
}
