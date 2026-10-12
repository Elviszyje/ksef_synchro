import Foundation

/// Operacje tekstowe w semantyce Pythona, potrzebne do wiernego portu.
/// Python indeksuje napisy po punktach kodowych, Swift po grafemach — tu
/// zawsze pracujemy na `unicodeScalars`.
enum PyText {
    /// `str.isspace()` / `\s` w `re` dla pojedynczego punktu kodowego.
    static func isSpace(_ s: Unicode.Scalar) -> Bool {
        if (0x1C...0x1F).contains(s.value) { return true }
        return s.properties.isWhitespace
    }

    /// `\w` w `re` (Unicode): litery, cyfry/liczby i podkreślnik.
    static func isWord(_ s: Unicode.Scalar) -> Bool {
        if s == "_" { return true }
        switch s.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    /// `text[:n]` w Pythonie.
    static func prefix(_ text: String, _ n: Int) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: text.unicodeScalars.prefix(n))
        return String(view)
    }

    /// `str.strip()` bez argumentów.
    static func strip(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        guard let start = scalars.firstIndex(where: { !isSpace($0) }),
              let end = scalars.lastIndex(where: { !isSpace($0) }) else { return "" }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars[start...end])
        return String(view)
    }

    /// `str.strip(chars)`.
    static func strip(_ text: String, chars: String) -> String {
        let set = Set(chars.unicodeScalars)
        let scalars = Array(text.unicodeScalars)
        guard let start = scalars.firstIndex(where: { !set.contains($0) }),
              let end = scalars.lastIndex(where: { !set.contains($0) }) else { return "" }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars[start...end])
        return String(view)
    }

    /// `str.lstrip(chars)`.
    static func lstrip(_ text: String, chars: String) -> String {
        let set = Set(chars.unicodeScalars)
        var view = String.UnicodeScalarView()
        view.append(contentsOf: text.unicodeScalars.drop(while: { set.contains($0) }))
        return String(view)
    }

    /// `str.isdigit()` dla napisów ASCII (wystarcza dla NRB i numerów faktur).
    static func isDigits(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { $0.properties.numericType == .decimal || $0.properties.numericType == .digit }
    }
}

/// Cienka nakładka na NSRegularExpression operująca na całych napisach.
struct PyRegex: @unchecked Sendable {
    let regex: NSRegularExpression

    init(_ pattern: String, options: NSRegularExpression.Options = []) {
        // Wzorce są stałymi w kodzie — błąd kompilacji wzorca to błąd programisty.
        regex = try! NSRegularExpression(pattern: pattern, options: options)
    }

    /// Grupy pierwszego dopasowania (`re.search`), nil dla grup niedopasowanych.
    func search(_ text: String) -> [String?]? {
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return Self.groups(m, in: ns)
    }

    /// Dopasowanie zakotwiczone na początku (`re.match`).
    func match(_ text: String) -> [String?]? {
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, options: .anchored, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return Self.groups(m, in: ns)
    }

    /// Wszystkie dopasowania (`re.finditer`).
    func all(_ text: String) -> [[String?]] {
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { Self.groups($0, in: ns) }
    }

    private static func groups(_ m: NSTextCheckingResult, in ns: NSString) -> [String?] {
        (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
    }
}
