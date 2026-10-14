import Foundation

/// Układ graficzny wizualizacji faktury.
public enum InvoiceLayout: String, CaseIterable, Codable, Sendable {
    /// Ramki i szare nagłówki tabel, akcent w tytule.
    case classic
    /// Pas w kolorze akcentu u góry, karty stron z tłem.
    case modern
    /// Bez wypełnień, cienkie linie, więcej światła.
    case minimal
}

/// Język etykiet na wydruku (niezależny od języka aplikacji).
public enum InvoiceLanguage: String, CaseIterable, Codable, Sendable {
    case pl
    case en
    /// Dwujęzyczne etykiety „Sprzedawca / Seller” — dla kontrahentów zagranicznych.
    case plEn = "pl-en"
}

/// Szablon wizualizacji faktur sprzedażowych. Faktury kosztowe mają stały, neutralny wygląd.
public struct InvoiceTemplate: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var companyID: UUID
    public var name: String
    public var layout: InvoiceLayout
    /// Kolor akcentu `#RRGGBB`.
    public var accentColor: String
    public var language: InvoiceLanguage
    /// Logo w PNG (przeskalowane przy wyborze, żeby nie puchła baza i kopia w iCloud).
    public var logoPNG: Data?
    public var showQRCode: Bool
    public var showAmountInWords: Bool
    public var showSignatureFields: Bool
    /// Stopka, np. KRS, kapitał zakładowy, kontakt.
    public var footerText: String
    /// Dopisek pod sumami, np. „Dziękujemy za współpracę”.
    public var closingNote: String
    public var isDefault: Bool
    public var updatedAt: Date
    public var updatedByDevice: String

    public init(id: UUID = UUID(), companyID: UUID, name: String, layout: InvoiceLayout = .classic,
                accentColor: String = InvoiceTemplate.accentPresets[0], language: InvoiceLanguage = .pl, logoPNG: Data? = nil,
                showQRCode: Bool = true, showAmountInWords: Bool = true, showSignatureFields: Bool = false,
                footerText: String = "", closingNote: String = "", isDefault: Bool = false,
                updatedAt: Date = Date(), updatedByDevice: String = "") {
        self.id = id
        self.companyID = companyID
        self.name = name
        self.layout = layout
        self.accentColor = accentColor
        self.language = language
        self.logoPNG = logoPNG
        self.showQRCode = showQRCode
        self.showAmountInWords = showAmountInWords
        self.showSignatureFields = showSignatureFields
        self.footerText = footerText
        self.closingNote = closingNote
        self.isDefault = isDefault
        self.updatedAt = updatedAt
        self.updatedByDevice = updatedByDevice
    }

    public static let accentPresets = ["#1A56DB", "#0F766E", "#B91C1C", "#7C3AED", "#C2410C", "#111827"]

    /// Szablon wbudowany — używany, dopóki użytkownik nie zapisze własnego.
    public static func standard(companyID: UUID) -> InvoiceTemplate {
        InvoiceTemplate(id: UUID(uuidString: "00000000-0000-0000-0000-00000000F001")!, companyID: companyID,
                        name: "Standardowy", isDefault: true, updatedAt: Date(timeIntervalSince1970: 0))
    }

    /// Wygląd faktur kosztowych: klasyczny, neutralny, bez elementów sprzedawcy.
    public static func costInvoice(language: InvoiceLanguage) -> InvoiceTemplate {
        InvoiceTemplate(companyID: UUID(), name: "", layout: .classic, accentColor: "#374151", language: language,
                        showQRCode: true, showAmountInWords: true)
    }

    /// Składowe koloru akcentu 0…1; niepoprawny zapis daje kolor domyślny.
    public var accentRGB: (red: Double, green: Double, blue: Double) {
        Self.rgb(accentColor) ?? Self.rgb(Self.accentPresets[0])!
    }

    public static func rgb(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    public static func hex(red: Double, green: Double, blue: Double) -> String {
        func c(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(red), c(green), c(blue))
    }
}

/// Szablony firmy: zapisane albo wbudowany, domyślny pierwszy.
public enum InvoiceTemplates {
    public static func effective(_ saved: [InvoiceTemplate], companyID: UUID) -> [InvoiceTemplate] {
        guard !saved.isEmpty else { return [.standard(companyID: companyID)] }
        return saved.sorted { ($0.isDefault ? 0 : 1, $0.name.lowercased()) < ($1.isDefault ? 0 : 1, $1.name.lowercased()) }
    }
}
