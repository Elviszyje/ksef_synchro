import Foundation

public enum KSeFError: Error, Equatable, LocalizedError {
    /// Limit zapytań KSeF; `retryAfter` w sekundach.
    case rateLimited(retryAfter: Int)
    case authentication(String)
    case api(status: Int, message: String)
    case invalidResponse(String)
    case missingToken

    public var errorDescription: String? {
        switch self {
        case .rateLimited(let s):
            let minutes = max(1, s / 60)
            return "KSeF ograniczył liczbę zapytań. Spróbuj ponownie za ok. \(minutes) min."
        case .authentication(let m):
            return "Błąd uwierzytelnienia w KSeF: \(m)"
        case .api(let status, let m):
            switch status {
            case 401: return "KSeF odrzucił token (401). Sprawdź, czy token jest aktualny i wygenerowany dla tego NIP."
            case 403: return "Token nie ma wymaganych uprawnień (403). Wygeneruj token z uprawnieniem do przeglądania faktur."
            default: return "KSeF zwrócił błąd \(status): \(m)"
            }
        case .invalidResponse(let m):
            return "Nieoczekiwana odpowiedź KSeF: \(m)"
        case .missingToken:
            return "Brak tokena KSeF. Uzupełnij go w Ustawieniach."
        }
    }

    /// Czas oczekiwania z komunikatu 429 (polskie "X godzin / Y minut / Z sekund"),
    /// nagłówka `Retry-After`, a domyślnie godzina — jak w Django.
    static func retryAfter(body: Data, header: String?) -> Int {
        if let header, let seconds = Int(header.trimmingCharacters(in: .whitespaces)) { return seconds }
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let status = json["status"] as? [String: Any],
              let details = status["details"] as? [String] else { return 3600 }
        for detail in details {
            var total = 0
            for (unit, factor) in [("godzin", 3600), ("minut", 60), ("sekund", 1)] {
                let regex = try! NSRegularExpression(pattern: #"(\d+)\s+"# + unit)
                let ns = detail as NSString
                for m in regex.matches(in: detail, range: NSRange(location: 0, length: ns.length)) {
                    total += Int(ns.substring(with: m.range(at: 1)))! * factor
                }
            }
            if total > 0 { return total + 5 }
        }
        return 3600
    }
}
