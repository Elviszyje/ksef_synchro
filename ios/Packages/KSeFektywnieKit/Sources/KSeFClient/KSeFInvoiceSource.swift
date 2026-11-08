import Foundation
import Domain

/// Źródło faktur z KSeF — abstrakcja nad `KSeFClient` dla testów synchronizacji.
public protocol KSeFInvoiceSource: Sendable {
    func authenticate() async throws -> KSeFClient.AccessToken
    func purchaseInvoiceMetadata(from: Date, to: Date, pageSize: Int) async throws -> [JSONValue]
    func salesInvoiceMetadata(from: Date, to: Date, pageSize: Int) async throws -> [JSONValue]
    func invoiceXML(ksefNumber: String) async throws -> Data?
}

extension KSeFInvoiceSource {
    /// Źródła bez faktur sprzedażowych (np. atrapy w testach zakupów).
    public func salesInvoiceMetadata(from: Date, to: Date, pageSize: Int) async throws -> [JSONValue] { [] }
}

extension KSeFClient: KSeFInvoiceSource {}
