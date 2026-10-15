import Foundation
import Testing
@testable import Domain
@testable import KSeFClient

/// Odpowiedzi w formacie `wl-api.mf.gov.pl` (dane fikcyjne). Zagnieżdżone w zestawie KSeF,
/// bo oba korzystają ze wspólnej atrapy `StubProtocol` i muszą biec po kolei.
extension KSeFClientTests {
    @Suite("Biała Lista MF")
    struct WhiteListClientTests {
        static let found = json([
            "result": [
                "subject": [
                    "name": "PRZYKŁADOWA FIRMA SPÓŁKA Z OGRANICZONĄ ODPOWIEDZIALNOŚCIĄ",
                    "nip": "1132854320",
                    "statusVat": "Czynny",
                    "regon": "012345678",
                    "workingAddress": "UL. MARSZAŁKOWSKA 1/2, 00-001 WARSZAWA",
                    "residenceAddress": NSNull(),
                    "accountNumbers": ["61109010140000071219812874"],
                ],
                "requestId": "abc",
            ],
        ])

        let session: URLSession

        init() {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [StubProtocol.self]
            session = URLSession(configuration: config)
            StubProtocol.requests.withLock { $0 = [] }
        }

        func client() -> WhiteListClient { WhiteListClient(baseURL: URL(string: "https://wl.test")!, session: session) }

        @Test("Podmiot czynny: nazwa, adres w dwóch liniach, rachunki; zapytanie z NIP i datą")
        func found() async throws {
            StubProtocol.handler.withLock { $0 = { _, _ in .init(body: Self.found) } }
            let taxpayer = try #require(try await client().lookup(nip: "113-285-43-20", on: LocalDate(iso: "2026-10-15")!))
            #expect(taxpayer.name.hasPrefix("PRZYKŁADOWA FIRMA"))
            #expect(taxpayer.address == "UL. MARSZAŁKOWSKA 1/2\n00-001 WARSZAWA")
            #expect(taxpayer.isActiveVATPayer && taxpayer.accountNumbers.count == 1)
            let url = try #require(StubProtocol.requests.withLock { $0.first?.0.url })
            #expect(url.absoluteString == "https://wl.test/api/search/nip/1132854320?date=2026-10-15")
        }

        @Test("NIP spoza wykazu, limit, błąd serwera, nieprawidłowy NIP bez zapytania")
        func errors() async throws {
            StubProtocol.handler.withLock { $0 = { _, _ in .init(body: json(["result": ["subject": NSNull(), "requestId": "x"]])) } }
            #expect(try await client().lookup(nip: "1132854320") == nil)

            StubProtocol.handler.withLock { $0 = { _, _ in .init(status: 429) } }
            await #expect(throws: WhiteListError.rateLimited) { try await client().lookup(nip: "1132854320") }

            StubProtocol.handler.withLock { $0 = { _, _ in .init(status: 400, body: Data(#"{"code":"WL-190","message":"limit"}"#.utf8)) } }
            await #expect(throws: WhiteListError.rateLimited) { try await client().lookup(nip: "1132854320") }

            StubProtocol.handler.withLock { $0 = { _, _ in .init(status: 503) } }
            await #expect(throws: WhiteListError.unavailable(503)) { try await client().lookup(nip: "1132854320") }

            StubProtocol.requests.withLock { $0 = [] }
            await #expect(throws: WhiteListError.invalidNIP) { try await client().lookup(nip: "1234567890") }
            #expect(StubProtocol.requests.withLock { $0.isEmpty })
        }

        @Test("Adres: podział przed kodem pocztowym, adres bez kodu bez zmian")
        func address() {
            #expect(RegisteredTaxpayer.addressLines("UL. DŁUGA 5, LOK. 3, 80-001 GDAŃSK") == "UL. DŁUGA 5, LOK. 3\n80-001 GDAŃSK")
            #expect(RegisteredTaxpayer.addressLines("WIEŚ 12 64-300 NOWY TOMYŚL") == "WIEŚ 12 64-300 NOWY TOMYŚL")
            #expect(RegisteredTaxpayer.addressLines("") == "")
        }
    }
}
