import Foundation
import Security

/// Token KSeF w pęku kluczy: tylko to urządzenie, dostępny po odblokowaniu,
/// nie trafia do kopii zapasowej ani do katalogu iCloud. Klucz per firma.
enum Keychain {
    static let service = "pl.ksefektywnie.ksef-token"

    static func ksefToken(for companyID: UUID) -> String? {
        var query = baseQuery(companyID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setKSeFToken(_ token: String?, for companyID: UUID) {
        SecItemDelete(baseQuery(companyID) as CFDictionary)
        guard let token, !token.isEmpty else { return }
        var query = baseQuery(companyID)
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func baseQuery(_ companyID: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: companyID.uuidString]
    }
}
