import Foundation

/// Rozpoznawanie banku po numerze NRB — port `apps/payments/bank_detection.py`.
/// Cyfry 3–6 NRB to początek numeru rozliczeniowego (kod banku wg NBP/KIR).
public enum BankDetection {
    static let codes: [String: String] = [
        "1010": "nbp", "1020": "pko_bp", "1030": "bnp_paribas", "1050": "ing", "1060": "bph",
        "1090": "erste", "1130": "citi_handlowy", "1140": "mbank", "1160": "millennium", "1190": "deutsche",
        "1240": "pekao", "1320": "bank_pocztowy", "1440": "erste", "1540": "bos", "1590": "credit_agricole",
        "1680": "velobank", "1750": "raiffeisen", "1870": "nest", "2030": "bnp_paribas", "2130": "toyota",
        "2490": "alior", "2530": "hsbc", "2690": "bank_pocztowy",
    ]

    public static let labels: [String: String] = [
        "erste": "Erste Bank", "mbank": "mBank", "pko_bp": "PKO BP", "bnp_paribas": "BNP Paribas",
        "ing": "ING", "bph": "BPH", "citi_handlowy": "Citi Handlowy", "millennium": "Millennium",
        "deutsche": "Deutsche Bank", "pekao": "Pekao", "bank_pocztowy": "Bank Pocztowy", "bos": "BOŚ",
        "credit_agricole": "Credit Agricole", "velobank": "VeloBank", "raiffeisen": "Raiffeisen",
        "nest": "Nest Bank", "nbp": "NBP", "toyota": "Toyota Bank", "alior": "Alior Bank", "hsbc": "HSBC",
        "other": "",
    ]

    static let fileSuffixes: [String: String] = [
        "erste": "Erste_Bank", "mbank": "mBank", "pko_bp": "PKO_BP", "bnp_paribas": "BNP_Paribas",
        "ing": "ING", "millennium": "Millennium", "pekao": "Pekao", "alior": "Alior",
        "credit_agricole": "Credit_Agricole", "velobank": "VeloBank", "other": "Przelew",
    ]

    /// Klucz banku albo `other`. Ignoruje spacje i myślniki.
    public static func bankKey(for account: String) -> String {
        let digits = account.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        guard digits.count == 26, PyText.isDigits(digits) else { return "other" }
        let code = String(digits.dropFirst(2).prefix(4))
        return codes[code] ?? "other"
    }

    public static func label(for bankKey: String) -> String { labels[bankKey] ?? "" }

    public static func fileSuffix(for bankKey: String) -> String { fileSuffixes[bankKey] ?? "Przelew" }
}
