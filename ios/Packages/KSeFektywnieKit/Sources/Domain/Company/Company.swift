import Foundation

public enum KSeFEnvironment: String, CaseIterable, Codable, Sendable {
    case test
    case production = "prod"

    public var baseURL: URL {
        switch self {
        case .test: URL(string: "https://api-test.ksef.mf.gov.pl")!
        case .production: URL(string: "https://api.ksef.mf.gov.pl")!
        }
    }
}

/// Profil firmy. W v1 aplikacja ma jedną firmę, ale cały model danych jest
/// kluczowany `companyID`, więc profile wielu firm to zmiana tylko w UI.
public struct Company: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var nip: String
    public var name: String
    /// Adres do plików bankowych (Elixir obcina nazwę i adres do 35 znaków).
    public var address: String
    public var ksefEnvironment: KSeFEnvironment
    public var syncIntervalHours: Int
    public var lastSyncAt: Date?
    /// Wzór numeracji faktur sprzedażowych, np. `FV/{rok}/{nnnn}`.
    public var invoiceNumberPattern: String
    public var defaultPaymentDays: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedByDevice: String

    public init(id: UUID = UUID(), nip: String, name: String, address: String = "",
                ksefEnvironment: KSeFEnvironment = .test, syncIntervalHours: Int = 6, lastSyncAt: Date? = nil,
                invoiceNumberPattern: String = "FV/{rok}/{nnnn}", defaultPaymentDays: Int = 14,
                createdAt: Date = Date(), updatedAt: Date = Date(), updatedByDevice: String = "") {
        self.id = id
        self.nip = nip
        self.name = name
        self.address = address
        self.ksefEnvironment = ksefEnvironment
        self.syncIntervalHours = syncIntervalHours
        self.lastSyncAt = lastSyncAt
        self.invoiceNumberPattern = invoiceNumberPattern
        self.defaultPaymentDays = defaultPaymentDays
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.updatedByDevice = updatedByDevice
    }
}

/// Rachunek firmowy (obciążany przy przelewach, podawany na fakturach sprzedażowych).
public struct CompanyBankAccount: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var companyID: UUID
    public var accountNumber: String
    public var label: String
    public var isDefault: Bool

    public init(id: UUID = UUID(), companyID: UUID, accountNumber: String, label: String = "", isDefault: Bool = false) {
        self.id = id
        self.companyID = companyID
        self.accountNumber = accountNumber.replacingOccurrences(of: " ", with: "")
        self.label = label
        self.isDefault = isDefault
    }

    public var bankKey: String { BankDetection.bankKey(for: accountNumber) }
}

/// Walidacja identyfikatorów.
public enum Validation {
    /// NIP: 10 cyfr, suma kontrolna z wagami 6,5,7,2,3,4,5,6,7.
    public static func isValidNIP(_ raw: String) -> Bool {
        let digits = raw.filter(\.isASCIIDigit).compactMap { Int(String($0)) }
        guard digits.count == 10, raw.filter({ $0 != "-" && $0 != " " }).count == 10 else { return false }
        let weights = [6, 5, 7, 2, 3, 4, 5, 6, 7]
        let sum = zip(digits, weights).map(*).reduce(0, +)
        return sum % 11 == digits[9] && sum % 11 != 10
    }

    /// NRB: 26 cyfr, kontrola IBAN mod 97 z prefiksem PL.
    public static func isValidNRB(_ raw: String) -> Bool {
        var s = raw.replacingOccurrences(of: " ", with: "").uppercased()
        if s.hasPrefix("PL") { s.removeFirst(2) }
        guard s.count == 26, s.allSatisfy(\.isASCIIDigit) else { return false }
        // PL = 25 21; IBAN: BBAN + "PL" + cyfry kontrolne
        let rearranged = String(s.dropFirst(2)) + "2521" + String(s.prefix(2))
        var remainder = 0
        for ch in rearranged { remainder = (remainder * 10 + Int(String(ch))!) % 97 }
        return remainder == 1
    }
}
