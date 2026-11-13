import Foundation
import Security

/// Token KSeF w pęku kluczy: tylko to urządzenie, nie trafia do kopii zapasowej
/// ani do katalogu iCloud. Klucz per firma.
///
/// Dostępność „po pierwszym odblokowaniu”: synchronizacja w tle działa zwykle przy
/// zablokowanym telefonie, a wpis „tylko po odblokowaniu” jest wtedy nieczytelny —
/// aplikacja widziała to jako brak tokenu.
enum Keychain {
    static let service = "pl.ksefektywnie.ksef-token"
    private static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    static func ksefToken(for companyID: UUID) -> String? {
        var query = baseQuery(companyID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Zapisuje token (albo usuwa, gdy pusty). Istniejący wpis jest podmieniany w miejscu,
    /// więc nieudany zapis nie kasuje poprzedniego tokenu. Zwraca `false`, gdy pęk kluczy odmówił.
    @discardableResult
    static func setKSeFToken(_ token: String?, for companyID: UUID) -> Bool {
        let query = baseQuery(companyID)
        guard let token, !token.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
                                         kSecAttrAccessible as String: accessibility]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard updated == errSecItemNotFound else { return updated == errSecSuccess }
        return SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil) == errSecSuccess
    }

    /// Przenosi tokeny zapisane przez starsze wersje („tylko po odblokowaniu”) na bieżącą dostępność.
    /// Udaje się tylko przy odblokowanym telefonie; w innym razie zostanie powtórzone przy kolejnym starcie.
    static func migrateAccessibility() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service]
        SecItemUpdate(query as CFDictionary, [kSecAttrAccessible as String: accessibility] as CFDictionary)
    }

    private static func baseQuery(_ companyID: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: companyID.uuidString]
    }
}
