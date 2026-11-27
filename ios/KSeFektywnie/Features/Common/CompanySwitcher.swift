import SwiftUI
import Domain

/// Przełącznik firmy w pasku nawigacji zakładek Faktury, Przelewy i Wyciągi (przy co najmniej dwóch firmach):
/// awatar i nazwa aktywnej firmy z menu wyboru — jak na Pulpicie. Bez `navigationSubtitle`, bo w iOS 26
/// podtytuł przy dużym tytule spłaszcza pole wyszukiwania (`searchable`) w Fakturach. Wybór aktywuje firmę
/// w całej aplikacji — zakładki odtwarzają się dla nowej firmy (`.id(model.company?.id)` w `RootView`).
/// Widok „Wszystkie firmy” zostaje tylko na Pulpicie, bo pozostałe zakładki pracują na jednej firmie.
struct CompanySwitcherModifier: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        if model.companies.count > 1, let company = model.company {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { menu(active: company) }
                }
        } else {
            content
        }
    }

    private func menu(active: Company) -> some View {
        Menu {
            Picker("Firma", selection: Binding(
                get: { active.id },
                set: { model.activate($0) })) {
                ForEach(model.companies) { company in
                    Text(company.name).tag(company.id)
                }
            }
        } label: {
            HStack(spacing: 8) {
                InitialsAvatar(name: active.name, size: 28, prominent: true)
                Text(active.name)
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
        .accessibilityLabel(Text("Firma: \(active.name)"))
        .accessibilityHint(Text("Zmień firmę"))
        .accessibilityIdentifier("company-switcher-toolbar")
    }
}

extension View {
    /// Przełącznik firmy w pasku nawigacji (widoczny przy co najmniej dwóch firmach).
    func companySwitcher() -> some View { modifier(CompanySwitcherModifier()) }
}
