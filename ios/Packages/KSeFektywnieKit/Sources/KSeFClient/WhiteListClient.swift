import Foundation
import Domain

/// Wyszukiwanie w Wykazie podatników VAT („Biała Lista” MF). Bez klucza API;
/// limit MF to 100 wyszukiwań dziennie z jednego adresu IP.
public struct WhiteListClient: Sendable {
    public static let productionURL = URL(string: "https://wl-api.mf.gov.pl")!

    let baseURL: URL
    let session: URLSession

    public init(session: URLSession = .shared) {
        self.init(baseURL: Self.productionURL, session: session)
    }

    init(baseURL: URL, session: URLSession) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Dane podmiotu na wskazany dzień; nil, gdy NIP-u nie ma w wykazie.
    public func lookup(nip: String, on date: LocalDate = .today()) async throws -> RegisteredTaxpayer? {
        let digits = nip.filter(\.isNumber)
        guard Validation.isValidNIP(digits) else { throw WhiteListError.invalidNIP }
        var request = URLRequest(url: baseURL.appending(path: "api/search/nip/\(digits)")
            .appending(queryItems: [URLQueryItem(name: "date", value: date.iso)]))
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw WhiteListError.network
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200:
            do { return try RegisteredTaxpayer.parse(data) } catch { throw WhiteListError.unavailable(status) }
        case 429:
            throw WhiteListError.rateLimited
        default:
            // MF zwraca 400 z kodem WL-1xx także po przekroczeniu dziennego limitu.
            if let body = String(data: data, encoding: .utf8), body.contains("WL-19") { throw WhiteListError.rateLimited }
            throw WhiteListError.unavailable(status)
        }
    }
}

public enum WhiteListError: Error, Equatable, LocalizedError {
    case invalidNIP
    case rateLimited
    case network
    case unavailable(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidNIP: "Nieprawidłowy NIP."
        case .rateLimited: "Wyczerpano dzienny limit zapytań do Białej Listy."
        case .network: "Brak połączenia z Białą Listą."
        case .unavailable(let status): "Biała Lista nie odpowiada (\(status))."
        }
    }
}
