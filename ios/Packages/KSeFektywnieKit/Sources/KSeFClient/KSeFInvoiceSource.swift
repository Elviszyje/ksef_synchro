import Foundation
import Domain

/// Źródło faktur zakupowych — abstrakcja nad `KSeFClient` dla testów synchronizacji.
public protocol KSeFInvoiceSource: Sendable {
    func authenticate() async throws -> KSeFClient.AccessToken
    func purchaseInvoiceMetadata(from: Date, to: Date, pageSize: Int) async throws -> [JSONValue]
    func invoiceXML(ksefNumber: String) async throws -> Data?
}

extension KSeFClient: KSeFInvoiceSource {}
