import SwiftUI
import UIKit

// Wygląd „Grafit”: grafit i mięta, kroje Space Grotesk i JetBrains Mono (oba na licencji OFL,
// pliki w Resources/Fonts). W trybie jasnym para jest odwrócona: mięta jest czytelna tylko
// na graficie, więc przyciski są grafitowe z miętowym napisem, a tekst akcentu ciemnozielony.

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    /// Tło ekranu.
    static let appBackground = Color(light: 0xF2F5F3, dark: 0x0F1211)
    /// Karta na tle ekranu.
    static let appSurface = Color(light: 0xFFFFFF, dark: 0x181D1B)
    /// Element na karcie (awatar, pigułka, przycisk pomocniczy).
    static let appSurfaceRaised = Color(light: 0xE3E9E5, dark: 0x232A27)
    static let appLine = Color(light: 0xDCE2DE, dark: 0x2C3431)
    static let appInk = Color(light: 0x0F1211, dark: 0xECF1EE)
    static let appMuted = Color(light: 0x5A6660, dark: 0x9BA8A1)
    /// Tekst i ikony akcentu (to samo co globalny `AccentColor`).
    static let appAccent = Color(light: 0x0B7A4B, dark: 0x6EF0B2)

    static let appMint = Color(uiColor: UIColor(hex: 0x6EF0B2))
    static let appGraphite = Color(uiColor: UIColor(hex: 0x0F1211))
    /// Jasny tekst na grafitowej karcie (taki sam w obu trybach).
    static let appOnGraphite = Color(uiColor: UIColor(hex: 0xECF1EE))
    static let appOnGraphiteMuted = Color(uiColor: UIColor(hex: 0x9BA8A1))

    /// Główny przycisk: grafit w trybie jasnym, mięta w ciemnym.
    static let appPrimaryFill = Color(light: 0x0F1211, dark: 0x6EF0B2)
    static let appOnPrimary = Color(light: 0x6EF0B2, dark: 0x0F1211)
    /// Ciemna karta wyróżniona („Do zapłaty”): grafit w trybie jasnym, zwykła karta w ciemnym.
    static let appFeatureCard = Color(light: 0x0F1211, dark: 0x181D1B)

    static let appWarning = Color(light: 0x7A4F00, dark: 0xFFB547)
    static let appWarningFill = Color(light: 0xFFEFCC, dark: 0x2B2414)
    static let appDanger = Color(light: 0xB42318, dark: 0xFF8A73)
    static let appSuccess = Color(light: 0x0B5D3A, dark: 0x6EF0B2)
    static let appSuccessFill = Color(light: 0xD6F5E5, dark: 0x173326)

    /// Tła akcji przesunięcia wiersza — pod białą ikoną, więc takie same w obu trybach.
    static let appSwipeApprove = Color(uiColor: UIColor(hex: 0x0B7A4B))
    static let appSwipeDispute = Color(uiColor: UIColor(hex: 0xB42318))
}

enum Grotesk: String {
    case regular = "SpaceGrotesk-Regular"
    case medium = "SpaceGrotesk-Medium"
    case bold = "SpaceGrotesk-Bold"
}

extension Font {
    /// Space Grotesk w podanym rozmiarze, skalowany z Dynamic Type jak wskazany styl systemowy.
    static func grotesk(_ size: CGFloat, _ weight: Grotesk = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight.rawValue, size: size, relativeTo: style)
    }

    /// JetBrains Mono — numery faktur, rachunki, NIP.
    static func mono(_ size: CGFloat, medium: Bool = false, relativeTo style: Font.TextStyle = .footnote) -> Font {
        .custom(medium ? "JetBrainsMono-Medium" : "JetBrainsMono-Regular", size: size, relativeTo: style)
    }

    // Odpowiedniki stylów systemowych — używane w całej aplikacji zamiast `.headline`, `.caption` itd.
    static let appLargeTitle = grotesk(30, .bold, relativeTo: .largeTitle)
    static let appTitle = grotesk(26, .bold, relativeTo: .title)
    static let appTitle2 = grotesk(22, .bold, relativeTo: .title2)
    static let appTitle3 = grotesk(19, .medium, relativeTo: .title3)
    static let appHeadline = grotesk(16, .medium, relativeTo: .headline)
    static let appBody = grotesk(16, relativeTo: .body)
    static let appSubheadline = grotesk(15, relativeTo: .subheadline)
    static let appFootnote = grotesk(13, relativeTo: .footnote)
    static let appCaption = grotesk(12.5, relativeTo: .caption)
    static let appCaption2 = grotesk(11.5, relativeTo: .caption2)
}

enum Theme {
    /// Tytuły pasków nawigacji w kroju aplikacji (UIKit nie dziedziczy czcionki ze SwiftUI).
    static func applyNavigationAppearance() {
        let bar = UINavigationBar.appearance()
        if let large = UIFont(name: Grotesk.bold.rawValue, size: 32) {
            bar.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large)]
        }
        if let inline = UIFont(name: Grotesk.medium.rawValue, size: 17) {
            bar.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: inline)]
        }
    }
}

// MARK: - Wspólne komponenty

extension View {
    /// Tło ekranu aplikacji pod listą lub formularzem (zamiast systemowego szarego/czarnego).
    func appScreenBackground() -> some View {
        scrollContentBackground(.hidden).background(Color.appBackground.ignoresSafeArea())
    }

    /// Karta: biała w trybie jasnym, grafitowa w ciemnym.
    func appCard(padding: CGFloat = 18, radius: CGFloat = 22) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appSurface, in: .rect(cornerRadius: radius))
    }
}

/// Główny przycisk ekranu (pełna szerokość, pigułka).
struct AppPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.grotesk(compact ? 15 : 16, .bold, relativeTo: .headline))
            .foregroundStyle(isEnabled ? Color.appOnPrimary : Color.appMuted)
            .padding(.horizontal, compact ? 18 : 22)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? 46 : 54)
            .background(isEnabled ? Color.appPrimaryFill : Color.appSurfaceRaised, in: .capsule)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Przycisk na grafitowej karcie: zawsze miętowy z grafitowym napisem.
struct AppMintButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.grotesk(15, .bold, relativeTo: .headline))
            .foregroundStyle(Color.appGraphite)
            .padding(.horizontal, 18)
            .frame(minHeight: 46)
            .background(Color.appMint, in: .capsule)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Przycisk pomocniczy obok głównego (obrys).
struct AppSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.grotesk(16, .medium, relativeTo: .headline))
            .foregroundStyle(Color.appInk)
            .padding(.horizontal, 22)
            .frame(minHeight: 54)
            .background(Color.appSurface, in: .capsule)
            .overlay(Capsule().strokeBorder(Color.appLine))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == AppPrimaryButtonStyle {
    static var appPrimary: AppPrimaryButtonStyle { AppPrimaryButtonStyle() }
    static var appPrimaryCompact: AppPrimaryButtonStyle { AppPrimaryButtonStyle(compact: true) }
}

extension ButtonStyle where Self == AppMintButtonStyle {
    static var appMint: AppMintButtonStyle { AppMintButtonStyle() }
}

extension ButtonStyle where Self == AppSecondaryButtonStyle {
    static var appSecondary: AppSecondaryButtonStyle { AppSecondaryButtonStyle() }
}

/// Okrągły awatar z inicjałami kontrahenta.
struct InitialsAvatar: View {
    let name: String
    var size: CGFloat = 38
    /// Wyróżniony (firma użytkownika, nagłówek faktury): grafit z miętą w trybie jasnym, mięta w ciemnym.
    var prominent = false

    var body: some View {
        Text(Self.initials(name))
            .font(.grotesk(size * 0.34, .medium, relativeTo: .footnote))
            .foregroundStyle(prominent ? Color.appOnPrimary : Color.appInk)
            .frame(width: size, height: size)
            .background(prominent ? Color.appPrimaryFill : Color.appSurfaceRaised, in: .circle)
            .accessibilityHidden(true)
    }

    /// Pierwsze litery dwóch pierwszych słów nazwy; spójniki i formy prawne („i”, „sp.”) są pomijane.
    static func initials(_ name: String) -> String {
        let skipped: Set<String> = ["i", "a", "w", "z", "sp", "sp.", "s.a.", "sa", "o.o.", "zoo"]
        let words = name.split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .map(String.init)
            .filter { !skipped.contains($0.lowercased()) && $0.first?.isLetter == true }
        let letters = words.prefix(2).compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }
}

/// Mała pigułka z etykietą (termin, MPP, pewność dopasowania).
struct AppPill: View {
    enum Tone { case neutral, warning, danger, success, outline }
    let text: Text
    var tone: Tone = .neutral

    var body: some View {
        text
            .font(.grotesk(12.5, .medium, relativeTo: .caption))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(background, in: .capsule)
            .overlay { if tone == .outline { Capsule().strokeBorder(Color.appLine) } }
    }

    private var foreground: Color {
        switch tone {
        case .neutral, .outline: .appInk
        case .warning: .appWarning
        case .danger: .appDanger
        case .success: .appSuccess
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: .appSurfaceRaised
        case .outline: .clear
        case .warning: .appWarningFill
        case .danger: Color.appDanger.opacity(0.14)
        case .success: .appSuccessFill
        }
    }
}

/// Kwota z mniejszym, wyszarzonym symbolem waluty (duże liczby na pulpicie i w nagłówku faktury).
struct HeroAmount: View {
    let amount: Decimal
    var currency = "PLN"
    var size: CGFloat = 42
    var onGraphite = false

    var body: some View {
        let parts = Self.split(amount, currency: currency)
        HStack(alignment: .firstTextBaseline, spacing: size * 0.18) {
            Text(parts.number)
                .font(.grotesk(size, .medium, relativeTo: .largeTitle))
                .tracking(-size * 0.03)
                .foregroundStyle(onGraphite ? Color.appOnGraphite : Color.appInk)
            Text(parts.symbol)
                .font(.grotesk(size * 0.48, .medium, relativeTo: .title3))
                .foregroundStyle(onGraphite ? Color.appOnGraphiteMuted : Color.appMuted)
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(amount.money(currency)))
    }

    /// Rozdziela sformatowaną kwotę na liczbę i symbol waluty (kolejność zależy od języka,
    /// ale symbol zawsze trafia na koniec — to element dekoracyjny, pełna kwota jest w etykiecie).
    static func split(_ amount: Decimal, currency: String) -> (number: String, symbol: String) {
        let code = currency.isEmpty ? "PLN" : currency
        let symbol = MoneyFormat.currency(code).currencySymbol ?? code
        return (amount.plainAmount, symbol.isEmpty ? code : symbol)
    }
}
