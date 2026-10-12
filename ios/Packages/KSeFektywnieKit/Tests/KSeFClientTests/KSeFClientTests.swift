import Foundation
import Security
import Synchronization
import Testing
import Domain
@testable import KSeFClient

/// Atrapa HTTP: odpowiedzi według ścieżki, zapis wszystkich żądań.
final class StubProtocol: URLProtocol {
    struct Reply: Sendable { var status = 200; var body = Data(); var headers: [String: String] = [:] }
    static let handler = Mutex<(@Sendable (URLRequest, Data?) -> Reply)?>(nil)
    static let requests = Mutex<[(URLRequest, Data?)]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: 4096); if n <= 0 { break }; data.append(buffer, count: n) }
            stream.close()
            body = data
        }
        Self.requests.withLock { $0.append((request, body)) }
        let reply = Self.handler.withLock { $0 }!(request, body)
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class Counter: Sendable {
    let value: Mutex<Int>
    init(_ start: Int = 0) { value = Mutex(start) }
    func increment() -> Int { value.withLock { $0 += 1; return $0 } }
    var current: Int { value.withLock { $0 } }
}

func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }

@Suite("Klient KSeF 2.0", .serialized)
struct KSeFClientTests {
    static let certificate = "MIICpjCCAY4CCQDcoQ9pGnPD1jANBgkqhkiG9w0BAQsFADAUMRIwEAYDVQQDDAlLU2VGIHRlc3QwIBcNMjYxMDExMjExOTA1WhgPMjEyNjA5MTcyMTE5MDVaMBQxEjAQBgNVBAMMCUtTZUYgdGVzdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALDrxqXcTkkrSX021Au1fzexOJEQNOR9ODF3s1fTuljIyknTzzG0TKYSbDu8XBVjOF5N9VFhO0xEris/mB5wWShnB2+7NcHtTFo1bmFmLZ+I5qEDHvcXMky4RqlVat7w4TBZqhnSt3wMMAcZ625mCCSy3bllO+P+ll7bURj0nz/rxORihGtmNQZLm9AD3VPBy9Iis4DhVv/X7IB5PGQnwLAXLt0RT4AtM6Q1FgU4cE+lqidaSIkX4LffRUT/7xdQRT7k12Eq6HQg/bSzjCDyauwaqEMMutYtvM3d/xnsqEi1+KVywE1xpovmuzfwwQJVXHv5D044FOZd8t+Rma3+j/cCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEACPGpwZsb/ULrbfzX98Ke8kOWFuo+cfrT3PhsWIS+/ix40epD1fDXy47UBBdcFPHevdWuQK/KulCJ9EDC3KXnNqvBKsOYJq+h7pKmTKC51HVeZhtVCadjSZbDB5brmvZIp8ACakiwQUCiLgKRsbcwVY/DCHKPnWI83HAIYQxqmeXGK8OL2wKpJ2gcfNKBQF/LLwvPes2+tedeml9Ivraorle2sB2JP4i2O0KwiSutTCcx+gEWhcgHrl4wZrvNiIhyAaM3U3rnU0r8y6ikSb6DFTHzQ2/peqEhvigTKuwjSB3BHKbuxpd/y8NxNsmzOnwNFNEEJf7S9vsToDguIc1dsg=="
    static let privateKey = "MIIEowIBAAKCAQEAsOvGpdxOSStJfTbUC7V/N7E4kRA05H04MXezV9O6WMjKSdPPMbRMphJsO7xcFWM4Xk31UWE7TESuKz+YHnBZKGcHb7s1we1MWjVuYWYtn4jmoQMe9xcyTLhGqVVq3vDhMFmqGdK3fAwwBxnrbmYIJLLduWU74/6WXttRGPSfP+vE5GKEa2Y1Bkub0APdU8HL0iKzgOFW/9fsgHk8ZCfAsBcu3RFPgC0zpDUWBThwT6WqJ1pIiRfgt99FRP/vF1BFPuTXYSrodCD9tLOMIPJq7BqoQwy61i28zd3/GeyoSLX4pXLATXGmi+a7N/DBAlVce/kPTjgU5l3y35GZrf6P9wIDAQABAoIBAQCtlvl3Hf0WH8ngeN5/ipqDW3ikJOGw2wg6yTcH0q/Bk2mgHJnsK/sU63iU+BDlz0+sgBNWwO88uxqlRqWMIDHqyYRrZaWuXJYQ4OIn4Oic4udfTj+gs3rf+eMjHLNagcCB/0g+RBlSNmcdYJo23RfaYkHZOXIVF2QVOF2O/d4PCTWVYUTvuVIR2HLyrwSWt5+LsMO1mO8ryi/zPLXQmZQyleAqhSfSK2vpoJuG0r/EqrbbwVZOFHLCY7nPYi9XctM/iFDnfT4cTlLnQGkPW8gmR7QGXmIDL3vS83009Qh14bwiUj6Lt3bjz+bs77pn5YMGMXilj79W8itd+nSGlIpRAoGBANkeDPq6ElBaJGqrK+r2z+zbRnQPMIdBQHn92jMBA0fnhFbv3gCAMj35AjUvH6fl5zcajUUmUdDCoRf4D2ZNO24aPP9tojGKIvw2Id5Ef30qWuUdZMR4i0GgFWUwovFhqwS/A0gMNm5wTv9tqv0G+9HPQdEwr7MvQVJrItJHTrcpAoGBANCa4mnkKn57zc3SVZU0hfkFCjuGdCvoxT1TCCqvNGzSzgxUMg2cuKUwh4hpyNS9tFroC8qxTIS2v7Hpis0TV4ahhKsYsIYNGaqCCAqhfyYbFjIkLW7VSUaEtvvmzYE9q/+LdvBcwcieVqqp8ms1JwZyJKMqMfmlLLmtxiKkGZIfAoGAQIq4XQhXTV+el78OrSh1ovmENhgV2v9AxYL7DFJuwT9Hjfh8TDXPubB+QYUiqeykETNpb3b2t1JERTXOjiDDW/Wc0Gms34Eq6ULGSqaeJ30hzB4yyFz1OKr38T7GEW9xQVXvCcnnnGjycugM/m7HCRXNgPwyHtgbWP7UOSJNehECgYBzK8ArhHxtnr7Ojv0PRpNdHAo9OQt0nqwfInOU1WyVVIHMTsPfvhI3qaZ6iyUFR8OGmSzBeMftUdReTrmCZdZiD1Tm/def+yWbfPUhoW5IxJWpk02+LmWpWGaKhzAY1crbaM1/AUdAEyN4UCH2TL9CEMznhMlYsngR/74vq/guMwKBgB+rBpQYOrA1L4XBKv2BD4dG//fUeEMC1hRR8uO74KHIpgs44SXRg8Lmz+Yu4RY/K/A1U31bSFmJ7fbu9SP1U7yqscaC8zuqnwKvWIfbwhdzEE6WrgZXJoW+gpc6dd4mtIwJKgU03/+GWse1zpDnM1F3YkDnU2ehXW1zemNllpPr"

    let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.requests.withLock { $0 = [] }
    }

    func client(token: String = "TOKEN-123") -> KSeFClient {
        KSeFClient(baseURL: URL(string: "https://ksef.test")!, nip: "1132854320", apiToken: token, session: session, sleep: { _ in })
    }

    static func decrypt(_ base64: String) throws -> String {
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeyClass as String: kSecAttrKeyClassPrivate]
        let key = try #require(SecKeyCreateWithData(Data(base64Encoded: privateKey)! as CFData, attributes as CFDictionary, nil))
        let plain = try #require(SecKeyCreateDecryptedData(key, .rsaEncryptionOAEPSHA256, Data(base64Encoded: base64)! as CFData, nil))
        return String(decoding: plain as Data, as: UTF8.self)
    }

    /// Pełny przebieg autoryzacji; status autoryzacji najpierw 100, potem 200.
    static func authFlow(authPolls: Counter) -> @Sendable (URLRequest, Data?) -> StubProtocol.Reply {
        { request, _ in
            switch request.url!.path {
            case "/api/v2/auth/challenge":
                return .init(body: json(["challenge": "CH-1", "timestampMs": 1_760_000_000_123]))
            case "/api/v2/security/public-key-certificates":
                return .init(body: json([
                    ["certificate": "AAAA", "usage": ["SymmetricKeyEncryption"]],
                    ["certificate": certificate, "usage": ["KsefTokenEncryption"]],
                ]))
            case "/api/v2/auth/ksef-token":
                return .init(status: 202, body: json(["referenceNumber": "REF-1", "authenticationToken": ["token": "AUTH-T", "validUntil": "2099-01-01T00:00:00Z"]]))
            case "/api/v2/auth/REF-1":
                let n = authPolls.increment()
                return .init(body: json(["status": ["code": n < 2 ? 100 : 200, "description": "x"]]))
            case "/api/v2/auth/token/redeem":
                return .init(body: json(["accessToken": ["token": "ACCESS-T", "validUntil": "2099-07-11T12:23:56.0154302+00:00"]]))
            default:
                return .init(status: 404)
            }
        }
    }

    @Test("Autoryzacja tokenem: szyfrowanie, odpytywanie statusu, access token")
    func authentication() async throws {
        let polls = Counter()
        StubProtocol.handler.withLock { $0 = Self.authFlow(authPolls: polls) }
        let token = try await client().authenticate()
        #expect(token.token == "ACCESS-T")
        #expect(token.validUntil.map { Calendar(identifier: .gregorian).component(.year, from: $0) } == 2099)
        #expect(polls.current == 2)

        let requests = StubProtocol.requests.withLock { $0 }
        let initBody = try #require(requests.first { $0.0.url!.path.hasSuffix("auth/ksef-token") }?.1)
        let payload = try JSONSerialization.jsonObject(with: initBody) as! [String: Any]
        #expect(payload["challenge"] as? String == "CH-1")
        #expect((payload["contextIdentifier"] as? [String: String]) == ["type": "Nip", "value": "1132854320"])
        #expect(try Self.decrypt(payload["encryptedToken"] as! String) == "TOKEN-123|1760000000123")

        let redeem = try #require(requests.first { $0.0.url!.path.hasSuffix("token/redeem") }?.0)
        #expect(redeem.value(forHTTPHeaderField: "Authorization") == "Bearer AUTH-T")
    }

    @Test("Odrzucona autoryzacja")
    func authenticationRejected() async throws {
        StubProtocol.handler.withLock {
            let base = Self.authFlow(authPolls: Counter())
            $0 = { request, body in
                if request.url!.path == "/api/v2/auth/REF-1" {
                    return .init(body: json(["status": ["code": 450, "description": "Nieprawidłowy token"]]))
                }
                return base(request, body)
            }
        }
        await #expect(throws: KSeFError.authentication("Nieprawidłowy token")) { try await client().authenticate() }
    }

    @Test("Brak tokena")
    func missingToken() async {
        await #expect(throws: KSeFError.missingToken) { try await client(token: "").authenticate() }
    }

    @Test("Zapytanie o metadane: podział na 89 dni i stronicowanie")
    func metadataPaging() async throws {
        let auth = Self.authFlow(authPolls: Counter(1))
        StubProtocol.handler.withLock {
            $0 = { request, body in
                guard request.url!.path == "/api/v2/invoices/query/metadata" else { return auth(request, body) }
                let q = try! JSONSerialization.jsonObject(with: body!) as! [String: Any]
                let offset = q["pageOffset"] as! Int
                let from = (q["dateRange"] as! [String: String])["from"]!
                let hasMore = from.hasPrefix("2026-01-01") && offset == 0
                return .init(body: json(["invoices": [["ksefNumber": "\(from)-\(offset)"]], "hasMore": hasMore]))
            }
        }
        let utc = ISO8601DateFormatter()
        let result = try await client().purchaseInvoiceMetadata(
            from: utc.date(from: "2026-01-01T00:00:00Z")!, to: utc.date(from: "2026-06-01T00:00:00Z")!, pageSize: 1)
        #expect(result.map { $0["ksefNumber"].stringValue } == [
            "2026-01-01T00:00:00Z-0", "2026-01-01T00:00:00Z-1", "2026-03-31T00:00:00Z-0",
        ])
        let queries = StubProtocol.requests.withLock { $0 }.filter { $0.0.url!.path.hasSuffix("query/metadata") }
        #expect(queries.allSatisfy { $0.0.value(forHTTPHeaderField: "Authorization") == "Bearer ACCESS-T" })
        let auths = StubProtocol.requests.withLock { $0 }.filter { $0.0.url!.path.hasSuffix("token/redeem") }
        #expect(auths.count == 1, "access token powinien być użyty ponownie")
    }

    @Test("XML faktury i 404")
    func invoiceXML() async throws {
        let auth = Self.authFlow(authPolls: Counter(1))
        StubProtocol.handler.withLock {
            $0 = { request, body in
                switch request.url!.path {
                case "/api/v2/invoices/ksef/OK": return .init(body: Data("<Faktura/>".utf8))
                case "/api/v2/invoices/ksef/MISSING": return .init(status: 404)
                default: return auth(request, body)
                }
            }
        }
        let c = client()
        #expect(try await c.invoiceXML(ksefNumber: "OK") == Data("<Faktura/>".utf8))
        #expect(try await c.invoiceXML(ksefNumber: "MISSING") == nil)
        let xmlRequest = StubProtocol.requests.withLock { $0 }.first { $0.0.url!.path.hasSuffix("ksef/OK") }!.0
        #expect(xmlRequest.value(forHTTPHeaderField: "Accept") == "application/octet-stream")
    }

    @Test("Limit 429: czas oczekiwania z komunikatu po polsku")
    func rateLimit() async throws {
        StubProtocol.handler.withLock {
            $0 = { _, _ in .init(status: 429, body: json(["status": ["details": ["Spróbuj ponownie za 1 godzin 2 minut 3 sekund."]]])) }
        }
        await #expect(throws: KSeFError.rateLimited(retryAfter: 3600 + 120 + 3 + 5)) { try await client().authenticate() }
        #expect(KSeFError.retryAfter(body: Data(), header: "42") == 42)
        #expect(KSeFError.retryAfter(body: Data("{}".utf8), header: nil) == 3600)
    }

    @Test("Komunikaty błędów API")
    func errors() {
        #expect(KSeFClient.errorMessage(json(["exception": ["exceptionDetailList": [["exceptionDescription": "Brak uprawnień"]]]])) == "Brak uprawnień")
        #expect(KSeFClient.errorMessage(json(["detail": "x"])) == "x")
        #expect(KSeFClient.parseDate("2025-07-11T12:23:56.0154302+00:00") != nil)
    }
}
