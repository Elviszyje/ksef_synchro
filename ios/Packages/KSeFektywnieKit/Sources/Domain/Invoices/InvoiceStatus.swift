import Foundation

/// Status faktury kosztowej. Wartości surowe są identyczne z Django,
/// bo trafiają do plików JSON w iCloud i mogą być importowane do aplikacji webowej.
public enum InvoiceStatus: String, CaseIterable, Codable, Sendable {
    case new = "nowa"
    case disputed = "sporna"
    case accepted = "zaakceptowana"
    case sentForPayment = "przekazano_do_oplacenia"
    case paid = "oplacona"
}

/// Reguły przejść z `apps/invoices/views.py` (STATUS_TRANSITIONS*).
public enum InvoiceStatusRules {
    public static let standard: [InvoiceStatus: [InvoiceStatus]] = [
        .new: [.disputed, .accepted, .paid],
        .disputed: [.new, .accepted, .paid],
        .accepted: [.disputed, .sentForPayment, .paid],
        .sentForPayment: [.paid],
        .paid: [],
    ]

    /// Korekta nie trafia do przelewu: zaakceptowana korekta od razu staje się opłacona.
    public static let correction: [InvoiceStatus: [InvoiceStatus]] = [
        .new: [.disputed, .accepted],
        .disputed: [.new, .accepted],
        .accepted: [.disputed],
        .paid: [],
    ]

    public static func allowedTransitions(isCorrection: Bool, from status: InvoiceStatus) -> [InvoiceStatus] {
        (isCorrection ? correction : standard)[status] ?? []
    }
}

public struct InvoiceStatusChange: Hashable, Sendable, Codable {
    public var from: InvoiceStatus
    public var to: InvoiceStatus
    public var at: Date
    public var note: String

    public init(from: InvoiceStatus, to: InvoiceStatus, at: Date, note: String) {
        self.from = from
        self.to = to
        self.at = at
        self.note = note
    }
}

public enum InvoiceStatusError: Error, Equatable {
    case transitionNotAllowed(from: InvoiceStatus, to: InvoiceStatus)
}
