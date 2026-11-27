import SwiftUI
import Domain

/// Przełącznik firmy — ten sam przycisk w lewym górnym rogu paska nawigacji Pulpitu, Faktur, Przelewów
/// i Wyciągów: awatar i nazwa aktywnej firmy, w menu wybór firmy i „Dodaj firmę”. Wybór aktywuje firmę
/// w całej aplikacji — zakładki odtwarzają się dla nowej firmy (`.id(model.company?.id)` w `RootView`).
/// Tylko Pulpit podaje `allCompanies` i ma opcję „Wszystkie firmy” (pozostałe zakładki pracują na jednej firmie).
///
/// Bez `navigationSubtitle`: w iOS 26 podtytuł przy dużym tytule spłaszcza pole wyszukiwania w Fakturach.
struct CompanySwitcherMenu: View {
    @Environment(AppModel.self) private var model
    /// Widok łączny Pulpitu; `nil` w pozostałych zakładkach.
    var allCompanies: Binding<Bool>?
    var accessibilityID = "company-switcher-toolbar"
    @State private var addingCompany = false

    private var showsAll: Bool { (allCompanies?.wrappedValue ?? false) && model.companies.count > 1 }

    var body: some View {
        let title = showsAll ? String(localized: "Wszystkie firmy") : (model.company?.name ?? "")
        Menu {
            Picker("Firma", selection: Binding(
                get: { showsAll ? nil : model.company?.id },
                set: { id in
                    allCompanies?.wrappedValue = id == nil
                    if let id { model.activate(id) }
                })) {
                ForEach(model.companies) { company in
                    Text(company.name).tag(UUID?.some(company.id))
                }
                if allCompanies != nil && model.companies.count > 1 {
                    Label("Wszystkie firmy", systemImage: "square.stack.3d.up").tag(UUID?.none)
                }
            }
            if model.canAddCompany {
                Button { addingCompany = true } label: { Label("Dodaj firmę", systemImage: "plus") }
            }
        } label: {
            HStack(spacing: 8) {
                if showsAll {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.appOnPrimary)
                        .frame(width: 28, height: 28)
                        .background(Color.appPrimaryFill, in: .circle)
                } else {
                    InitialsAvatar(name: title, size: 28, prominent: true)
                }
                Text(title)
                    .font(.grotesk(14, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Color.appInk)
                    .lineLimit(1)
                    .frame(maxWidth: 150, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.appMuted)
            }
            .padding(.trailing, 4)
        }
        .accessibilityLabel(Text("Firma: \(title)"))
        .accessibilityHint(Text("Zmień firmę"))
        .accessibilityIdentifier(accessibilityID)
        .sheet(isPresented: $addingCompany) { AddCompanyView() }
    }
}

struct CompanySwitcherModifier: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.toolbar {
            if model.company != nil {
                ToolbarItem(placement: .topBarLeading) { CompanySwitcherMenu() }
            }
        }
    }
}

extension View {
    /// Przełącznik firmy w lewym górnym rogu paska nawigacji.
    func companySwitcher() -> some View { modifier(CompanySwitcherModifier()) }
}
