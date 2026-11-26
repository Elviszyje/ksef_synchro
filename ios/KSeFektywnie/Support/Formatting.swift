import Foundation
import SwiftUI
import Domain

/// Formatery kwot. Polskie ustawienia regionalne nie grupują liczb czterocyfrowych („4305,00 zł”
/// obok „24 600,00 zł”) — w zestawieniach kwot wygląda to jak błąd, więc grupujemy zawsze.
enum MoneyFormat {
    private static var currencyFormatters: [String: NumberFormatter] = [:]

    static func currency(_ code: String) -> NumberFormatter {
        let key = "\(code)|\(Locale.current.identifier)"
        if let cached = currencyFormatters[key] { return cached }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = .current
        formatter.minimumGroupingDigits = 1
        currencyFormatters[key] = formatter
        return formatter
    }

    /// Sama liczba z dwoma miejscami po przecinku, bez symbolu waluty.
    static func plain() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.minimumGroupingDigits = 1
        return formatter
    }
}

extension Decimal {
    /// Kwota z kodem waluty w formacie bieżącego języka (np. „1 446,00 zł”, „PLN 1,446.00”).
    func money(_ currency: String = "PLN") -> String {
        let code = currency.isEmpty ? "PLN" : currency
        return MoneyFormat.currency(code).string(from: self as NSDecimalNumber)
            ?? formatted(.currency(code: code))
    }

    /// Kwota bez symbolu waluty (np. „1 446,00”).
    var plainAmount: String {
        MoneyFormat.plain().string(from: self as NSDecimalNumber) ?? formatted()
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
        case .new: .appAccent
        case .disputed: .appDanger
        case .accepted: .appWarning
        case .sentForPayment: .appMuted
        case .paid: .appSuccess
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
