import Foundation

/// Podmiot z Wykazu podatników VAT („Biała Lista” MF, `wl-api.mf.gov.pl`).
/// Port `apps/outgoing/nip_lookup.py` z Django.
public struct RegisteredTaxpayer: Equatable, Sendable {
    public var name: String
    public var nip: String
    public var regon: String
    /// „Czynny”, „Zwolniony” albo „Niezarejestrowany”.
    public var vatStatus: String
    /// Adres w dwóch liniach (ulica / kod i miejscowość), jak w formularzu faktury.
    public var address: String
    public var accountNumbers: [String]

    public init(name: String, nip: String, regon: String = "", vatStatus: String = "", address: String = "",
                accountNumbers: [String] = []) {
        self.name = name
        self.nip = nip
        self.regon = regon
        self.vatStatus = vatStatus
        self.address = address
        self.accountNumbers = accountNumbers
    }

    public var isActiveVATPayer: Bool { vatStatus == "Czynny" }

    /// Odpowiedź `api/search/nip/{nip}`; nil, gdy podmiotu nie ma w wykazie (`subject: null`).
    public static func parse(_ data: Data) throws -> RegisteredTaxpayer? {
        struct Response: Decodable {
            struct Result: Decodable { var subject: Subject? }
            struct Subject: Decodable {
                var name: String?
                var nip: String?
                var regon: String?
                var statusVat: String?
                var workingAddress: String?
                var residenceAddress: String?
                var accountNumbers: [String]?
            }
            var result: Result?
        }
        guard let subject = try JSONDecoder().decode(Response.self, from: data).result?.subject else { return nil }
        let rawAddress = [subject.workingAddress, subject.residenceAddress].compactMap { $0 }.first { !$0.isEmpty } ?? ""
        return RegisteredTaxpayer(name: subject.name ?? "", nip: subject.nip ?? "", regon: subject.regon ?? "",
                                  vatStatus: subject.statusVat ?? "", address: addressLines(rawAddress),
                                  accountNumbers: subject.accountNumbers ?? [])
    }

    /// „UL. PRZYKŁADOWA 1, 00-001 WARSZAWA” → dwie linie, podział przed kodem pocztowym.
    static func addressLines(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard let match = text.range(of: #",\s*\d{2}-\d{3}\s"#, options: [.regularExpression, .backwards]) else { return text }
        let street = text[..<match.lowerBound].trimmingCharacters(in: .whitespaces)
        let city = text[match.lowerBound...].dropFirst().trimmingCharacters(in: .whitespaces)
        return street.isEmpty ? city : "\(street)\n\(city)"
    }
}
