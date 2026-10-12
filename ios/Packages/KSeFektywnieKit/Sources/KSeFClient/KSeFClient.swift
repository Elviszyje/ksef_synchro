import Foundation
import Domain

/// Klient API KSeF 2.0 — port `apps/ksef/client.py`.
///
/// Autoryzacja tokenem:
/// 1. `POST auth/challenge`
/// 2. szyfrowanie `token|timestampMs` kluczem publicznym KSeF (RSA-OAEP SHA-256)
/// 3. `POST auth/ksef-token` → token uwierzytelniający
/// 4. odpytywanie `GET auth/{ref}` aż status ≠ 100
/// 5. `POST auth/token/redeem` → access token (ok. 15 min)
public actor KSeFClient {
    public struct AccessToken: Sendable, Equatable {
        public let token: String
        public let validUntil: Date?

        public init(token: String, validUntil: Date?) {
            self.token = token
            self.validUntil = validUntil
        }
    }

    public let baseURL: URL
    public let nip: String
    private let apiToken: String
    private let session: URLSession
    private let sleep: @Sendable (Duration) async throws -> Void
    private var accessToken: AccessToken?

    /// Maksymalny zakres jednego zapytania (limit API: 3 miesiące).
    static let maxChunk: TimeInterval = 89 * 24 * 3600

    public init(environment: KSeFEnvironment, nip: String, apiToken: String, session: URLSession = .shared) {
        self.init(baseURL: environment.baseURL, nip: nip, apiToken: apiToken, session: session)
    }

    init(baseURL: URL, nip: String, apiToken: String, session: URLSession,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.baseURL = baseURL
        self.nip = nip
        self.apiToken = apiToken
        self.session = session
        self.sleep = sleep
    }

    // MARK: - Autoryzacja

    @discardableResult
    public func authenticate() async throws -> AccessToken {
        guard !apiToken.isEmpty else { throw KSeFError.missingToken }

        let challenge = try await json(try await send("auth/challenge", method: "POST"))
        guard let challengeValue = challenge["challenge"] as? String,
              let timestampMs = (challenge["timestampMs"] as? NSNumber)?.int64Value else {
            throw KSeFError.authentication("Brak challenge/timestampMs w odpowiedzi.")
        }

        let encrypted = try TokenEncryption.encrypt(token: apiToken, timestampMs: timestampMs,
                                                    certificateDER: try await tokenEncryptionCertificate())
        let initResponse = try await json(try await send("auth/ksef-token", method: "POST", body: [
            "challenge": challengeValue,
            "contextIdentifier": ["type": "Nip", "value": nip],
            "encryptedToken": encrypted,
        ]))
        guard let authToken = Self.token(initResponse["authenticationToken"]) else {
            throw KSeFError.authentication("Brak authenticationToken w odpowiedzi.")
        }
        if let reference = initResponse["referenceNumber"] as? String {
            try await waitForAuthentication(reference: reference, authToken: authToken)
        }

        let redeem = try await json(try await send("auth/token/redeem", method: "POST", bearer: authToken))
        guard let token = Self.token(redeem["accessToken"]) else {
            throw KSeFError.authentication("Brak accessToken w odpowiedzi.")
        }
        // Gdy KSeF nie poda ważności, zakładamy 10 minut (token żyje ok. 15 min).
        let validUntil = ((redeem["accessToken"] as? [String: Any])?["validUntil"] as? String).flatMap(Self.parseDate)
            ?? Date().addingTimeInterval(600)
        let access = AccessToken(token: token, validUntil: validUntil)
        accessToken = access
        return access
    }

    /// Certyfikat klucza publicznego MF o danym przeznaczeniu (`KsefTokenEncryption`
    /// albo `SymmetricKeyEncryption`); gdy KSeF nie poda przeznaczenia — pierwszy (jak Django).
    func certificate(usage: String) async throws -> (der: Data, publicKeyId: String?) {
        let data = try await send("security/public-key-certificates", method: "GET")
        let decoded = try JSONSerialization.jsonObject(with: data)
        let entries: [[String: Any]] = (decoded as? [[String: Any]]) ?? [(decoded as? [String: Any]) ?? [:]]
        let entry = entries.first { (($0["usage"] as? [String]) ?? []).contains(usage) } ?? entries.first
        guard let base64 = entry?["certificate"] as? String, let der = Data(base64Encoded: base64) else {
            throw KSeFError.authentication("Brak certyfikatu klucza publicznego KSeF.")
        }
        return (der, entry?["publicKeyId"] as? String)
    }

    func tokenEncryptionCertificate() async throws -> Data {
        try await certificate(usage: "KsefTokenEncryption").der
    }

    func waitForAuthentication(reference: String, authToken: String, maxAttempts: Int = 30) async throws {
        for _ in 0..<maxAttempts {
            let status = try await json(try await send("auth/\(reference)", method: "GET", bearer: authToken))
            let statusObject = status["status"] ?? status["processingCode"] ?? status["authenticationStatus"]
            let code = ((statusObject as? [String: Any])?["code"] as? NSNumber)?.intValue ?? (statusObject as? NSNumber)?.intValue
            if code != 100 {
                if code == 200 { return }
                let description = ((statusObject as? [String: Any])?["description"] as? String) ?? "status \(code.map(String.init) ?? "?")"
                throw KSeFError.authentication(description)
            }
            try await sleep(.seconds(1))
        }
        throw KSeFError.authentication("Przekroczono czas oczekiwania na autoryzację (ref: \(reference)).")
    }

    func validToken() async throws -> String {
        if let accessToken, let validUntil = accessToken.validUntil, validUntil > Date().addingTimeInterval(60) {
            return accessToken.token
        }
        return try await authenticate().token
    }

    // MARK: - Faktury zakupowe

    /// Metadane faktur, w których firma jest nabywcą (`Subject2`).
    /// Zakresy dłuższe niż 89 dni są dzielone, strony pobierane do `hasMore == false`.
    public func purchaseInvoiceMetadata(from: Date, to: Date, pageSize: Int = 250) async throws -> [JSONValue] {
        var all: [JSONValue] = []
        var chunkStart = from
        while chunkStart < to {
            let chunkEnd = min(chunkStart.addingTimeInterval(Self.maxChunk), to)
            var offset = 0
            while true {
                let body: [String: Any] = [
                    "subjectType": "Subject2",
                    "dateRange": [
                        "dateType": "PermanentStorage",
                        "from": ISO8601DateFormatter.ksefQuery.string(from: chunkStart),
                        "to": ISO8601DateFormatter.ksefQuery.string(from: chunkEnd),
                    ],
                    "pageSize": pageSize,
                    "pageOffset": offset,
                ]
                let data = try await send("invoices/query/metadata", method: "POST", body: body, bearer: try await validToken())
                let page = try JSONDecoder().decode(JSONValue.self, from: data)
                guard case .array(let invoices) = page["invoices"] else { break }
                all += invoices
                guard page["hasMore"] == .bool(true), !invoices.isEmpty else { break }
                offset += pageSize
            }
            chunkStart = chunkEnd
        }
        return all
    }

    /// Surowy XML faktury; nil, gdy KSeF zwraca 404 (brak dostępu do treści).
    public func invoiceXML(ksefNumber: String) async throws -> Data? {
        do {
            return try await send("invoices/ksef/\(ksefNumber)", method: "GET", bearer: try await validToken(),
                                  accept: "application/octet-stream")
        } catch KSeFError.api(status: 404, _) {
            return nil
        }
    }

    // MARK: - HTTP

    func send(_ path: String, method: String, body: [String: Any]? = nil, bearer: String? = nil,
              accept: String = "application/json") async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: "v2/\(path)"))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw KSeFError.invalidResponse("brak odpowiedzi HTTP") }
        if http.statusCode == 429 {
            throw KSeFError.rateLimited(retryAfter: KSeFError.retryAfter(body: data, header: http.value(forHTTPHeaderField: "Retry-After")))
        }
        guard http.statusCode < 400 else { throw KSeFError.api(status: http.statusCode, message: Self.errorMessage(data)) }
        return data
    }

    func json(_ data: Data) async throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KSeFError.invalidResponse(String(decoding: data.prefix(200), as: UTF8.self))
        }
        return object
    }

    /// Token bywa obiektem `{token, validUntil}` albo samym napisem.
    static func token(_ value: Any?) -> String? {
        if let s = value as? String, !s.isEmpty { return s }
        if let o = value as? [String: Any], let s = o["token"] as? String, !s.isEmpty { return s }
        return nil
    }

    /// Daty KSeF mają do 7 cyfr ułamka sekundy (`2025-07-11T12:23:56.0154302+00:00`),
    /// a `ISO8601DateFormatter` czyta najwyżej 3 — przycinamy ułamek.
    static func parseDate(_ text: String) -> Date? {
        let trimmed = text.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        return ISO8601DateFormatter.ksef.date(from: trimmed) ?? ISO8601DateFormatter.ksefQuery.date(from: trimmed)
    }

    static func errorMessage(_ data: Data) -> String {
        let fallback = String(decoding: data.prefix(500), as: UTF8.self)
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return fallback }
        if let s = (o["detail"] ?? o["message"] ?? o["title"]) as? String { return s }
        if let ex = o["exception"] as? [String: Any], let list = ex["exceptionDetailList"] as? [[String: Any]],
           let s = list.first?["exceptionDescription"] as? String { return s }
        return fallback
    }
}

extension ISO8601DateFormatter {
    nonisolated(unsafe) static let ksef: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// `%Y-%m-%dT%H:%M:%SZ` jak w zapytaniu Django.
    nonisolated(unsafe) static let ksefQuery: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}
