import Foundation

/// Dekodowanie i autodetekcja formatu wyciągu — port `detect.py` + widoku uploadu.
public enum StatementImporter {
    /// UTF-8, a gdy się nie uda — Windows-1250.
    ///
    /// Django próbuje UTF-8 → ISO-8859-1 → Windows-1250. ISO-8859-1 dekoduje każdy
    /// ciąg bajtów, więc Windows-1250 nigdy nie jest używane, a polskie znaki
    /// z plików CP1250 zamieniają się w krzaki. Tu kolejność jest poprawiona.
    public static func decode(_ data: Data) throws -> String {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let cp1250 = CP1250.decode(data) { return cp1250 }
        throw StatementError.unreadableEncoding
    }

    /// Parsery CSV w kolejności rejestru z Django.
    enum CSVFormat: String, CaseIterable {
        case velobank, erste

        func detect(_ content: String) -> Bool {
            switch self {
            case .velobank: VeloBankCSVParser.detect(content)
            case .erste: ErsteCSVParser.detect(content)
            }
        }

        func parse(_ content: String) throws -> ParsedStatement {
            switch self {
            case .velobank: try VeloBankCSVParser.parse(content)
            case .erste: try ErsteCSVParser.parse(content)
            }
        }
    }

    /// Parsery banków z rachunków firmy są sprawdzane najpierw, MT940 na końcu
    /// (chyba że firma deklaruje MT940).
    public static func parse(_ content: String, preferredBankKeys: [String] = []) throws -> ParsedStatement {
        if preferredBankKeys.contains(where: { $0 == "mt940" || $0 == "swift" }), MT940Parser.detect(content) {
            return MT940Parser.parse(content)
        }
        var ordered: [CSVFormat] = []
        for key in preferredBankKeys {
            if let format = CSVFormat(rawValue: key), !ordered.contains(format) { ordered.append(format) }
        }
        ordered += CSVFormat.allCases.filter { !ordered.contains($0) }
        for format in ordered where format.detect(content) {
            return try format.parse(content)
        }
        if MT940Parser.detect(content) { return MT940Parser.parse(content) }
        throw StatementError.unrecognizedFormat
    }

    public static func parse(data: Data, preferredBankKeys: [String] = []) throws -> ParsedStatement {
        try parse(decode(data), preferredBankKeys: preferredBankKeys)
    }
}
