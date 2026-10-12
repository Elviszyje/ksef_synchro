import SwiftUI

/// Przewodnik "jak połączyć aplikację z KSeF" krok po kroku.
struct KSeFGuideView: View {
    struct Step: Identifiable {
        let id: Int
        let title: LocalizedStringResource
        let body: LocalizedStringResource
        let symbol: String
    }

    static let steps: [Step] = [
        Step(id: 1, title: "Czego potrzebujesz",
             body: "NIP firmy i możliwość zalogowania się do KSeF: Profil Zaufany, e-dowód, podpis kwalifikowany albo pieczęć firmy. W spółkach osoba logująca się musi mieć nadane uprawnienia w KSeF, np. przez zawiadomienie ZAW-FA złożone w urzędzie skarbowym.",
             symbol: "checklist"),
        Step(id: 2, title: "Zaloguj się do Aplikacji Podatnika KSeF",
             body: "Na komputerze lub w przeglądarce telefonu wejdź na stronę ksef.podatki.gov.pl, otwórz Aplikację Podatnika KSeF i zaloguj się w kontekście NIP swojej firmy.",
             symbol: "person.badge.key"),
        Step(id: 3, title: "Wygeneruj token",
             body: "W sekcji tokenów utwórz nowy token. Zaznacz uprawnienie do przeglądania (odczytu) faktur. Jeśli chcesz wystawiać w aplikacji faktury sprzedażowe, zaznacz też uprawnienie do wystawiania faktur. Nadaj tokenowi opis, np. „KS-eFektywnie iPhone”.",
             symbol: "key"),
        Step(id: 4, title: "Skopiuj token od razu",
             body: "KSeF pokazuje token tylko raz. Skopiuj go do schowka. Jeśli go zgubisz, unieważnij stary token i wygeneruj nowy.",
             symbol: "doc.on.clipboard"),
        Step(id: 5, title: "Wklej token w aplikacji",
             body: "Otwórz Ustawienia → Połączenie z KSeF. Wybierz środowisko Produkcyjne, sprawdź NIP, wklej token, naciśnij „Zapisz token”, a potem „Testuj połączenie”. Token zostaje tylko w pęku kluczy tego iPhone'a.",
             symbol: "iphone"),
        Step(id: 6, title: "Pierwsza synchronizacja",
             body: "Naciśnij „Synchronizuj teraz” albo przeciągnij listę faktur w dół. Aplikacja najpierw pobierze listę faktur z ostatnich 30 dni, a potem ich treść. KSeF pozwala pobrać około 64 faktur na godzinę, więc przy dużej liczbie faktur treść będzie uzupełniana przy kolejnych synchronizacjach.",
             symbol: "arrow.triangle.2.circlepath"),
    ]

    static let problems: [(LocalizedStringResource, LocalizedStringResource)] = [
        ("Błąd 401", "Token jest nieprawidłowy, wygasł albo został wygenerowany dla innego NIP. Wygeneruj nowy token."),
        ("Błąd 403", "Token nie ma potrzebnych uprawnień. Wygeneruj token z uprawnieniem do przeglądania faktur."),
        ("Limit zapytań", "KSeF czasowo ogranicza liczbę zapytań. Aplikacja poda, kiedy można spróbować ponownie."),
        ("Środowisko testowe", "Środowisko testowe ma osobne dane i osobne tokeny. Token z produkcji nie działa na teście i odwrotnie."),
        ("Nowy telefon", "Token nie jest przenoszony na inne urządzenia. Na nowym iPhonie wklej token ponownie albo wygeneruj nowy."),
    ]

    var body: some View {
        List {
            Section {
                ForEach(Self.steps) { step in
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle().fill(.tint.opacity(0.15)).frame(width: 36, height: 36)
                            Text("\(step.id)").font(.headline).foregroundStyle(.tint)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Label { Text(step.title).font(.headline) } icon: { Image(systemName: step.symbol) }
                            Text(step.body).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section("Gdy coś nie działa") {
                ForEach(Array(Self.problems.enumerated()), id: \.offset) { _, problem in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(problem.0).font(.subheadline.bold())
                        Text(problem.1).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Link(destination: URL(string: "https://ksef.podatki.gov.pl")!) {
                    Label("ksef.podatki.gov.pl", systemImage: "safari")
                }
            } footer: {
                Text("KS-eFektywnie nie jest aplikacją Ministerstwa Finansów.")
            }
        }
        .navigationTitle("Połączenie z KSeF")
    }
}
