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
    nonisolated var label: LocalizedStringResource {
        switch self {
        case .new: "Nowa"
        case .disputed: "Sporna"
        case .accepted: "Zaakceptowana"
        case .sentForPayment: "Przekazano do opłacenia"
        case .paid: "Opłacona"
        }
    }

    var color: Color {
        switch self {
        case .new: .blue
        case .disputed: .red
        case .accepted: .green
        case .sentForPayment: .orange
        case .paid: .secondary
        }
    }

    var symbol: String {
        switch self {
        case .new: "sparkle"
        case .disputed: "exclamationmark.bubble"
        case .accepted: "checkmark.circle"
        case .sentForPayment: "arrow.up.forward.circle"
        case .paid: "checkmark.seal.fill"
        }
    }
}

extension KSeFEnvironment {
    var label: LocalizedStringResource {
        switch self {
        case .test: "Testowe"
        case .production: "Produkcyjne"
        }
    }
}
