import Foundation

/// Dokument gotowy do wydruku wraz z informacją, czy to projekt (faktury nie ma w KSeF).
public struct PreparedInvoiceDocument: Hashable, Sendable {
    public var document: InvoiceDocument
    public var isDraft: Bool

    public init(document: InvoiceDocument, isDraft: Bool) {
        self.document = document
        self.isDraft = isDraft
    }
}

public enum InvoiceVisualizationError: Error, Equatable, LocalizedError {
    case missingXML
    case unreadableXML

    public var errorDescription: String? {
        switch self {
        case .missingXML: "Treść faktury nie została jeszcze pobrana z KSeF."
        case .unreadableXML: "Nie udało się odczytać XML faktury."
        }
    }
}

public enum InvoiceVisualization {
    /// Faktura kosztowa: treść z XML pobranego z KSeF, kod QR z numerem KSeF.
    public static func cost(_ invoice: Invoice, environment: KSeFEnvironment) throws -> PreparedInvoiceDocument {
        guard !invoice.rawXML.isEmpty else { throw InvoiceVisualizationError.missingXML }
        guard var document = InvoiceDocument.parse(xml: invoice.rawXML) else { throw InvoiceVisualizationError.unreadableXML }
        document.attachKSeF(number: invoice.ksefReferenceNumber, environment: environment, xml: invoice.rawXML)
        return PreparedInvoiceDocument(document: document, isDraft: false)
    }

    /// Faktura sprzedażowa: XML wysłany do KSeF, a dla szkicu — wygenerowany teraz (bez zapisu).
    /// Kod QR tylko dla faktury przyjętej przez KSeF.
    /// Faktura zaimportowana z KSeF ma wyłącznie oryginalny XML (nie generujemy go od nowa).
    public static func sales(_ invoice: OutgoingInvoice, seller: FA3Seller, now: Date = Date()) throws -> PreparedInvoiceDocument {
        let inKSeF = [.accepted, .sending, .queued, .imported].contains(invoice.status)
        if invoice.status == .imported && invoice.generatedXML.isEmpty { throw InvoiceVisualizationError.missingXML }
        let xml = inKSeF && !invoice.generatedXML.isEmpty ? invoice.generatedXML : try FA3Generator.generate(invoice, seller: seller, now: now)
        guard var document = InvoiceDocument.parse(xml: xml) else { throw InvoiceVisualizationError.unreadableXML }
        if invoice.status == .accepted || invoice.status == .imported {
            document.attachKSeF(number: invoice.ksefNumber, environment: invoice.environment, xml: xml)
        }
        return PreparedInvoiceDocument(document: document, isDraft: !inKSeF)
    }
}
