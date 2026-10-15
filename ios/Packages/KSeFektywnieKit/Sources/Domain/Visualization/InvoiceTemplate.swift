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

/// Sekcja strony faktury pod nagłówkiem. Kolejność ustawia użytkownik w szablonie (przeciąganie);
/// nagłówek jest zawsze na górze.
public enum InvoiceSection: String, CaseIterable, Codable, Sendable {
    /// Sprzedawca i nabywca (z danymi korekty, gdy faktura jest korektą).
    case parties
    case items
    /// Tabela stawek VAT.
    case summary
    /// Kwota do zapłaty i kwota słownie.
    case totals
    /// Płatność i kod QR KSeF.
    case payment
    /// Adnotacje, uwagi i dopisek.
    case notes
    case signatures

    public static let defaultOrder = allCases

    /// Każda sekcja dokładnie raz: powtórzone pomijane, brakujące dopisane na końcu
    /// w kolejności domyślnej (odporność na starsze zapisy i nowe sekcje).
    public static func normalized(_ order: [InvoiceSection]) -> [InvoiceSection] {
        var seen = Set<InvoiceSection>()
        let result = order.filter { seen.insert($0).inserted }
        return result + defaultOrder.filter { !seen.contains($0) }
    }

    /// Zapis w bazie: identyfikatory oddzielone przecinkami.
    public static func encode(_ order: [InvoiceSection]) -> String { order.map(\.rawValue).joined(separator: ",") }

    public static func decode(_ raw: String) -> [InvoiceSection] {
        normalized(raw.split(separator: ",").compactMap { InvoiceSection(rawValue: String($0)) })
    }
}

/// Strona strony (lewa/prawa) dla elementów przesuwanych w poziomie: logo, kod QR.
public enum InvoiceSide: String, CaseIterable, Codable, Sendable {
    case leading
    case trailing
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
    /// Kolejność sekcji pod nagłówkiem (zawsze pełna, bez powtórzeń).
    public var sectionOrder: [InvoiceSection] { didSet { sectionOrder = InvoiceSection.normalized(sectionOrder) } }
    /// Strona logo w nagłówku; nil — domyślna dla układu (nowoczesny: prawa, pozostałe: lewa).
    public var logoSide: InvoiceSide?
    public var qrSide: InvoiceSide
    public var isDefault: Bool
    public var updatedAt: Date
    public var updatedByDevice: String

    public init(id: UUID = UUID(), companyID: UUID, name: String, layout: InvoiceLayout = .classic,
                accentColor: String = InvoiceTemplate.accentPresets[0], language: InvoiceLanguage = .pl, logoPNG: Data? = nil,
                showQRCode: Bool = true, showAmountInWords: Bool = true, showSignatureFields: Bool = false,
                footerText: String = "", closingNote: String = "", sectionOrder: [InvoiceSection] = InvoiceSection.defaultOrder,
                logoSide: InvoiceSide? = nil, qrSide: InvoiceSide = .trailing, isDefault: Bool = false,
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
        self.sectionOrder = InvoiceSection.normalized(sectionOrder)
        self.logoSide = logoSide
        self.qrSide = qrSide
        self.isDefault = isDefault
        self.updatedAt = updatedAt
        self.updatedByDevice = updatedByDevice
    }

    public var resolvedLogoSide: InvoiceSide { logoSide ?? (layout == .modern ? .trailing : .leading) }

    /// Czy układ strony różni się od domyślnego (przycisk „Przywróć”).
    public var hasCustomArrangement: Bool {
        sectionOrder != InvoiceSection.defaultOrder || logoSide != nil || qrSide != .trailing
    }

    public mutating func resetArrangement() {
        sectionOrder = InvoiceSection.defaultOrder
        logoSide = nil
        qrSide = .trailing
    }

    /// Przeniesienie sekcji na miejsce innej (przeciąganie w edytorze układu).
    public mutating func move(_ section: InvoiceSection, to target: InvoiceSection) {
        guard section != target, let from = sectionOrder.firstIndex(of: section),
              let to = sectionOrder.firstIndex(of: target) else { return }
        var order = sectionOrder
        order.remove(at: from)
        order.insert(section, at: to)
        sectionOrder = order
    }

    public mutating func move(_ section: InvoiceSection, by offset: Int) {
        guard let from = sectionOrder.firstIndex(of: section) else { return }
        let to = from + offset
        guard sectionOrder.indices.contains(to) else { return }
        move(section, to: sectionOrder[to])
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
