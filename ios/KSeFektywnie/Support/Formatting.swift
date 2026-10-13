import Foundation
import SwiftUI
import Domain

extension Decimal {
    /// Kwota z kodem waluty w formacie bieżącego języka (np. „1 446,00 zł”, „PLN 1,446.00”).
    func money(_ currency: String = "PLN") -> String {
        formatted(.currency(code: currency.isEmpty ? "PLN" : currency))
    }
}

extension LocalDate {
    var formatted: String { date().formatted(date: .abbreviated, time: .omitted) }
}

extension InvoiceStatus {
    /// Nazwy mówią, co dzieje się z płatnością. Wartości surowe (`zaakceptowana`,
    /// `przekazano_do_oplacenia`) zostają bez zmian dla zgodności z Django i katalogiem iCloud.
    nonisolated var label: LocalizedStringResource {
        switch self {
        case .new: "Nowa"
        case .disputed: "Sporna"
        case .accepted: "Do zapłaty"
        case .sentForPayment: "Przelew przygotowany"
        case .paid: "Opłacona"
        }
    }

    /// Co dalej z fakturą w tym statusie (pod statusem w szczegółach).
    var explanation: LocalizedStringResource {
        switch self {
        case .new: "Sprawdź fakturę i zatwierdź ją do zapłaty."
        case .disputed: "Płatność wstrzymana do wyjaśnienia z dostawcą."
        case .accepted: "Czeka w zakładce Przelewy na wygenerowanie pliku dla banku."
        case .sentForPayment: "Jest w pliku przelewów dla banku. Po imporcie wyciągu zostanie oznaczona jako opłacona."
        case .paid: "Rozliczona."
        }
    }

    var color: Color {
        switch self {
        case .new: .blue
        case .disputed: .red
        case .accepted: .orange
        case .sentForPayment: .purple
        case .paid: .green
        }
    }

    var symbol: String {
        switch self {
        case .new: "sparkle"
        case .disputed: "exclamationmark.bubble"
        case .accepted: "banknote"
        case .sentForPayment: "building.columns"
        case .paid: "checkmark.seal.fill"
        }
    }
}

/// Akcja zmiany statusu opisana czynnością, a nie nazwą statusu docelowego.
struct StatusAction {
    let target: InvoiceStatus
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource?
    let symbol: String

    /// Czy akcja przenosi fakturę do zakładki Przelewy (animacja „wpadania”).
    var movesToPayments: Bool { target == .accepted }

    init(target: InvoiceStatus, isCorrection: Bool) {
        self.target = target
        switch target {
        case .accepted where isCorrection:
            title = "Zatwierdź korektę"; subtitle = "Zostanie od razu rozliczona"; symbol = "checkmark.circle"
        case .accepted:
            title = "Zatwierdź do zapłaty"; subtitle = "Trafi do zakładki Przelewy"; symbol = "banknote"
        case .disputed:
            title = "Oznacz jako sporną"; subtitle = "Wstrzymaj płatność"; symbol = "exclamationmark.bubble"
        case .new:
            title = "Przywróć do weryfikacji"; subtitle = nil; symbol = "arrow.uturn.backward"
        case .sentForPayment:
            title = "Oznacz: przelew przygotowany"; subtitle = "Przelew zlecony poza aplikacją"; symbol = "building.columns"
        case .paid:
            title = "Oznacz jako opłaconą"; subtitle = "Zapłacona poza aplikacją"; symbol = "checkmark.seal"
        }
    }
}

extension Invoice {
    var statusActions: [StatusAction] {
        allowedTransitions.map { StatusAction(target: $0, isCorrection: isCorrection) }
    }

    var movesToPaymentsWhenAccepted: Bool { !isCorrection && !bankAccountNumber.isEmpty }
}

extension KSeFEnvironment {
    var label: LocalizedStringResource {
        switch self {
        case .test: "Testowe"
        case .production: "Produkcyjne"
        }
    }
}
