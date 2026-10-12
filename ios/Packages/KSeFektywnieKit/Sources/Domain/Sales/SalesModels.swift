import Foundation

/// Stawka VAT pozycji faktury sprzedażowej. Wartości surowe jak w Django (`InvoiceItem.VAT_RATE_CHOICES`).
public enum VATRate: String, CaseIterable, Codable, Sendable {
    case standard = "23"
    case reduced8 = "8"
    case reduced5 = "5"
    case zero = "0"
    case exempt = "zw"
    case notSubject = "np"

    public var percent: Decimal? {
        switch self {
        case .standard: 23
        case .reduced8: 8
        case .reduced5: 5
        case .zero, .exempt, .notSubject: nil
        }
    }

    /// Etykieta jak w formularzu Django (`23%`, `ZW`, `NP`).
    public var shortLabel: String {
        switch self {
        case .exempt: "ZW"
        case .notSubject: "NP"
        default: "\(rawValue)%"
        }
    }
}

/// Rodzaj podstawy zwolnienia → pole FA(3) P_19A/B/C.
public enum VATExemptionType: String, CaseIterable, Codable, Sendable {
    case act = "ustawa"        // P_19A: przepis ustawy albo aktu wydanego na jej podstawie
    case directive = "dyrektywa"  // P_19B: przepis dyrektywy 2006/112/WE
    case other = "inna"        // P_19C: inna podstawa prawna
}

public enum PaymentForm: String, CaseIterable, Codable, Sendable {
    case transfer = "przelew"
    case cash = "gotowka"
}

public enum OutgoingInvoiceStatus: String, CaseIterable, Codable, Sendable {
    case draft, queued, sending, accepted, rejected
}

/// Pozycja faktury sprzedażowej — kwoty liczone jak `InvoiceItem.calculate_amounts`.
public struct OutgoingInvoiceItem: Hashable, Sendable, Identifiable {
    public var id = UUID()
    public var name: String
    public var unit: String
    public var quantity: Decimal
    public var unitPriceNet: Decimal
    public var vatRate: VATRate

    public init(id: UUID = UUID(), name: String, unit: String = "szt.", quantity: Decimal = 1,
                unitPriceNet: Decimal = 0, vatRate: VATRate = .standard) {
        self.id = id
        self.name = name
        self.unit = unit
        self.quantity = quantity
        self.unitPriceNet = unitPriceNet
        self.vatRate = vatRate
    }

    /// Netto = ilość × cena, zaokrąglone ROUND_HALF_UP do groszy.
    public var amountNet: Decimal { (quantity * unitPriceNet).rounded(scale: 2, mode: .plain) }

    public var amountVAT: Decimal {
        guard let percent = vatRate.percent else { return 0 }
        return (amountNet * percent / 100).rounded(scale: 2, mode: .plain)
    }

    public var amountGross: Decimal { amountNet + amountVAT }
}

/// Faktura sprzedażowa (port `apps.outgoing.models.OutgoingInvoice`).
public struct OutgoingInvoice: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var companyID: UUID
    public var buyerID: UUID?
    public var invoiceNumber: String
    public var issueDate: LocalDate
    public var deliveryDate: LocalDate?
    public var paymentDueDate: LocalDate
    public var paymentForm: PaymentForm
    public var currency: String
    /// Rachunek firmy podawany na fakturze (przelew).
    public var bankAccountNumber: String
    public var buyerNIP: String
    public var buyerName: String
    public var buyerAddress: String
    public var notes: String
    public var exemptionType: VATExemptionType
    public var exemptionBasis: String
    public var status: OutgoingInvoiceStatus
    public var environment: KSeFEnvironment
    public var items: [OutgoingInvoiceItem]
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedByDevice: String

    public init(id: UUID = UUID(), companyID: UUID, buyerID: UUID? = nil, invoiceNumber: String,
                issueDate: LocalDate, deliveryDate: LocalDate? = nil, paymentDueDate: LocalDate,
                paymentForm: PaymentForm = .transfer, currency: String = "PLN", bankAccountNumber: String = "",
                buyerNIP: String = "", buyerName: String = "", buyerAddress: String = "", notes: String = "",
                exemptionType: VATExemptionType = .act, exemptionBasis: String = "",
                status: OutgoingInvoiceStatus = .draft, environment: KSeFEnvironment = .test,
                items: [OutgoingInvoiceItem] = [], createdAt: Date = Date(), updatedAt: Date = Date(), updatedByDevice: String = "") {
        self.id = id
        self.companyID = companyID
        self.buyerID = buyerID
        self.invoiceNumber = invoiceNumber
        self.issueDate = issueDate
        self.deliveryDate = deliveryDate
        self.paymentDueDate = paymentDueDate
        self.paymentForm = paymentForm
        self.currency = currency
        self.bankAccountNumber = bankAccountNumber
        self.buyerNIP = buyerNIP
        self.buyerName = buyerName
        self.buyerAddress = buyerAddress
        self.notes = notes
        self.exemptionType = exemptionType
        self.exemptionBasis = exemptionBasis
        self.status = status
        self.environment = environment
        self.items = items
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.updatedByDevice = updatedByDevice
    }

    public var amountNet: Decimal { items.reduce(0) { $0 + $1.amountNet } }
    public var amountVAT: Decimal { items.reduce(0) { $0 + $1.amountVAT } }
    public var amountGross: Decimal { items.reduce(0) { $0 + $1.amountGross } }
    public var hasExemptItems: Bool { items.contains { $0.vatRate == .exempt } }
    public var canBeEdited: Bool { status == .draft }

    /// Problemy blokujące zapis (komunikaty po polsku; UI tłumaczy je przez klucze).
    public var validationIssues: [SalesValidationIssue] {
        var issues: [SalesValidationIssue] = []
        if invoiceNumber.trimmingCharacters(in: .whitespaces).isEmpty { issues.append(.missingNumber) }
        if !Validation.isValidNIP(buyerNIP) { issues.append(.invalidBuyerNIP) }
        if buyerName.trimmingCharacters(in: .whitespaces).isEmpty { issues.append(.missingBuyerName) }
        if items.isEmpty { issues.append(.noItems) }
        if items.contains(where: { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }) { issues.append(.itemWithoutName) }
        if paymentForm == .transfer && bankAccountNumber.isEmpty { issues.append(.missingBankAccount) }
        if hasExemptItems && exemptionBasis.trimmingCharacters(in: .whitespaces).isEmpty { issues.append(.missingExemptionBasis) }
        return issues
    }
}

public enum SalesValidationIssue: String, CaseIterable, Sendable {
    case missingNumber, invalidBuyerNIP, missingBuyerName, noItems, itemWithoutName, missingBankAccount, missingExemptionBasis
}

/// Zapamiętana pozycja (towar/usługa) do ponownego użycia — odpowiednik `CatalogItem` w Django.
public struct CatalogItem: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var companyID: UUID
    public var name: String
    public var unit: String
    public var unitPriceNet: Decimal
    public var vatRate: VATRate
    public var useCount: Int
    public var lastUsedAt: Date?
    public var updatedAt: Date
    public var updatedByDevice: String

    public init(id: UUID = UUID(), companyID: UUID, name: String, unit: String = "szt.", unitPriceNet: Decimal = 0,
                vatRate: VATRate = .standard, useCount: Int = 0, lastUsedAt: Date? = nil,
                updatedAt: Date = Date(), updatedByDevice: String = "") {
        self.id = id
        self.companyID = companyID
        self.name = name
        self.unit = unit
        self.unitPriceNet = unitPriceNet
        self.vatRate = vatRate
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
        self.updatedAt = updatedAt
        self.updatedByDevice = updatedByDevice
    }

    /// Nowa pozycja faktury na podstawie wpisu katalogu (ilość 1).
    public func makeItem() -> OutgoingInvoiceItem {
        OutgoingInvoiceItem(name: name, unit: unit, quantity: 1, unitPriceNet: unitPriceNet, vatRate: vatRate)
    }
}

/// Nabywca zapisany do ponownego użycia.
public struct Buyer: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var companyID: UUID
    public var nip: String
    public var name: String
    public var address: String
    public var email: String
    public var phone: String
    public var notes: String
    public var updatedAt: Date
    public var updatedByDevice: String

    public init(id: UUID = UUID(), companyID: UUID, nip: String, name: String, address: String = "", email: String = "",
                phone: String = "", notes: String = "", updatedAt: Date = Date(), updatedByDevice: String = "") {
        self.id = id
        self.companyID = companyID
        self.nip = nip
        self.name = name
        self.address = address
        self.email = email
        self.phone = phone
        self.notes = notes
        self.updatedAt = updatedAt
        self.updatedByDevice = updatedByDevice
    }
}

/// Podpowiedzi podstaw zwolnienia (te same co w Django). Użytkownik wybiera świadomie.
public enum VATExemptionSuggestions {
    public static let common = [
        "art. 113 ust. 1 ustawy o VAT",
        "art. 43 ust. 1 pkt 18 ustawy o VAT",
        "art. 43 ust. 1 pkt 29 lit. a ustawy o VAT",
        "art. 43 ust. 1 pkt 37 ustawy o VAT",
        "art. 43 ust. 1 pkt 38 ustawy o VAT",
    ]
}

/// Numeracja faktur według wzoru firmy, np. `FV/{rok}/{nnnn}` (port `generate_number`).
public enum InvoiceNumbering {
    public static func next(pattern: String, year: Int, existing: [String]) -> String {
        let width = pattern.components(separatedBy: "{").compactMap { part -> Int? in
            guard let close = part.firstIndex(of: "}") else { return nil }
            let token = part[..<close]
            return token.allSatisfy { $0 == "n" } && !token.isEmpty ? token.count : nil
        }.first ?? 4
        let counterToken = "{" + String(repeating: "n", count: width) + "}"
        let withYear = pattern.replacingOccurrences(of: "{rok}", with: String(year))
        guard let range = withYear.range(of: counterToken) else {
            return withYear
        }
        let prefix = String(withYear[..<range.lowerBound])
        let suffix = String(withYear[range.upperBound...])
        let used = existing.compactMap { number -> Int? in
            guard number.hasPrefix(prefix), number.hasSuffix(suffix), number.count > prefix.count + suffix.count else { return nil }
            return Int(number.dropFirst(prefix.count).dropLast(suffix.count))
        }
        let next = (used.max() ?? 0) + 1
        return prefix + String(format: "%0\(width)d", next) + suffix
    }
}
