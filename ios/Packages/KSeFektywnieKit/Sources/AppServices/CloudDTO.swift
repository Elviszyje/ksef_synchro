import Foundation
import Domain
import Persistence

// Format plików w katalogu iCloud. Nazwy pól jak w API Django (snake_case),
// kwoty jako tekst ("1234.56"), daty ISO 8601 — katalog można zaimportować
// do aplikacji webowej jednym skryptem.

enum CloudFormat {
    static let schemaVersion = 1

    static func amount(_ d: Decimal) -> String { FA3Amount.fixed(d) }
    static func amount(_ s: String) -> Decimal { DecimalText.parse(s) ?? 0 }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(CloudDate.format(date))
        }
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let text = try c.decode(String.self)
            guard let date = CloudDate.parse(text) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Nieprawidłowa data: \(text)")
            }
            return date
        }
        return d
    }
}

/// Daty ISO 8601 z milisekundami (UTC), zapisywane deterministycznie.
///
/// GRDB przechowuje daty z dokładnością do milisekund (obcinając), a `Date` z `Date()`
/// ma ułamki poniżej milisekundy. Zaokrąglenie do pełnych milisekund przy zapisie
/// i drobny zapas przy odczycie sprawiają, że cykl baza → JSON → baza → JSON daje
/// za każdym razem ten sam tekst — inaczej lustro nadpisywałoby pliki bez zmian.
enum CloudDate {
    static func format(_ date: Date) -> String {
        let ms = Int64((date.timeIntervalSince1970 * 1000).rounded())
        let fraction = ((ms % 1000) + 1000) % 1000
        let seconds = Date(timeIntervalSince1970: TimeInterval((ms - fraction) / 1000))
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        let base = f.string(from: seconds)
        return String(base.dropLast()) + String(format: ".%03lldZ", fraction)
    }

    static func parse(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        guard let dot = text.firstIndex(of: "."), text.hasSuffix("Z") else { return f.date(from: text) }
        let digits = text[text.index(after: dot)..<text.index(before: text.endIndex)]
        guard let base = f.date(from: String(text[..<dot]) + "Z"), let value = Int(digits.prefix(3).padding(toLength: 3, withPad: "0", startingAt: 0)) else {
            return nil
        }
        return base.addingTimeInterval(Double(value) / 1000 + 0.000_000_5)
    }
}

/// Kwota z dwoma miejscami po przecinku (z kropką).
enum FA3Amount {
    static func fixed(_ value: Decimal) -> String {
        let n = NSDecimalNumber(decimal: value.rounded(scale: 2, mode: .plain))
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = false
        return f.string(from: n) ?? "0.00"
    }
}

struct ManifestDTO: Codable, Equatable {
    var schema_version: Int
    var app: String
    var device_id: String
    var written_at: Date
    var companies: [ManifestCompany]

    struct ManifestCompany: Codable, Equatable {
        var id: UUID
        var nip: String
        var name: String
        var folder: String
    }
}

struct CompanyDTO: Codable {
    var schema_version: Int
    var id: UUID
    var nip: String
    var name: String
    var address: String
    var ksef_environment: String
    var sync_interval_hours: Int
    var last_sync_at: Date?
    var invoice_number_pattern: String
    var default_payment_days: Int
    var created_at: Date
    var updated_at: Date
    var updated_by_device: String
    var bank_accounts: [BankAccountDTO]

    struct BankAccountDTO: Codable {
        var id: UUID
        var account_number: String
        var label: String
        var is_default: Bool
    }

    init(_ s: CompanySnapshot) {
        let c = s.company
        schema_version = CloudFormat.schemaVersion
        id = c.id; nip = c.nip; name = c.name; address = c.address
        ksef_environment = c.ksefEnvironment.rawValue; sync_interval_hours = c.syncIntervalHours
        last_sync_at = c.lastSyncAt; invoice_number_pattern = c.invoiceNumberPattern
        default_payment_days = c.defaultPaymentDays; created_at = c.createdAt; updated_at = c.updatedAt
        updated_by_device = c.updatedByDevice
        bank_accounts = s.bankAccounts.map { .init(id: $0.id, account_number: $0.accountNumber, label: $0.label, is_default: $0.isDefault) }
    }

    func company() -> Company {
        Company(id: id, nip: nip, name: name, address: address, ksefEnvironment: KSeFEnvironment(rawValue: ksef_environment) ?? .test,
                syncIntervalHours: sync_interval_hours, lastSyncAt: last_sync_at, invoiceNumberPattern: invoice_number_pattern,
                defaultPaymentDays: default_payment_days, createdAt: created_at, updatedAt: updated_at, updatedByDevice: updated_by_device)
    }

    func accounts() -> [CompanyBankAccount] {
        bank_accounts.map { CompanyBankAccount(id: $0.id, companyID: id, accountNumber: $0.account_number, label: $0.label, isDefault: $0.is_default) }
    }
}

struct StatusChangeDTO: Codable {
    var old_status: String
    var new_status: String
    var changed_at: Date
    var note: String
    var device: String
}

struct InvoiceDTO: Codable {
    var schema_version: Int
    var id: UUID
    var ksef_reference_number: String
    var invoice_number: String
    var seller_name: String
    var seller_nip: String
    var seller_address: String
    var buyer_nip: String
    var amount_net: String
    var amount_vat: String
    var amount_gross: String
    var currency: String
    var is_split_payment: Bool
    var vat_amount_split: String?
    var issue_date: LocalDate
    var payment_due_date: LocalDate?
    var bank_account_number: String
    var payment_title: String
    var payment_date: LocalDate?
    var payment_form: String
    var status: String
    var notes: String
    var invoice_type: String
    var description: String
    var xml_file: String?
    var synced_at: Date
    var updated_at: Date
    var updated_by_device: String
    var status_history: [StatusChangeDTO]

    init(_ i: Invoice, history: [InvoiceStatusLogEntry], xmlFile: String?) {
        schema_version = CloudFormat.schemaVersion
        id = i.id; ksef_reference_number = i.ksefReferenceNumber; invoice_number = i.invoiceNumber
        seller_name = i.sellerName; seller_nip = i.sellerNIP; seller_address = i.sellerAddress; buyer_nip = i.buyerNIP
        amount_net = CloudFormat.amount(i.amountNet); amount_vat = CloudFormat.amount(i.amountVAT)
        amount_gross = CloudFormat.amount(i.amountGross); currency = i.currency; is_split_payment = i.isSplitPayment
        vat_amount_split = i.vatAmountSplit.map(CloudFormat.amount); issue_date = i.issueDate; payment_due_date = i.paymentDueDate
        bank_account_number = i.bankAccountNumber; payment_title = i.paymentTitle; payment_date = i.paymentDate
        payment_form = i.paymentForm; status = i.status.rawValue; notes = i.notes; invoice_type = i.invoiceType
        description = i.description; xml_file = xmlFile; synced_at = i.syncedAt; updated_at = i.updatedAt
        updated_by_device = i.updatedByDevice
        status_history = history.map { .init(old_status: $0.change.from.rawValue, new_status: $0.change.to.rawValue,
                                             changed_at: $0.change.at, note: $0.change.note, device: $0.device) }
    }

    func invoice(companyID: UUID, rawXML: String) -> Invoice {
        Invoice(id: id, companyID: companyID, ksefReferenceNumber: ksef_reference_number, invoiceNumber: invoice_number,
                sellerName: seller_name, sellerNIP: seller_nip, sellerAddress: seller_address, buyerNIP: buyer_nip,
                amountNet: CloudFormat.amount(amount_net), amountVAT: CloudFormat.amount(amount_vat),
                amountGross: CloudFormat.amount(amount_gross), currency: currency, isSplitPayment: is_split_payment,
                vatAmountSplit: vat_amount_split.map(CloudFormat.amount), issueDate: issue_date, paymentDueDate: payment_due_date,
                bankAccountNumber: bank_account_number, paymentTitle: payment_title, paymentDate: payment_date,
                paymentForm: payment_form, status: InvoiceStatus(rawValue: status) ?? .new, notes: notes,
                invoiceType: invoice_type, description: description, rawXML: rawXML,
                syncedAt: synced_at, updatedAt: updated_at, updatedByDevice: updated_by_device)
    }

    func history() -> [InvoiceStatusLogEntry] {
        status_history.map {
            InvoiceStatusLogEntry(invoiceID: id, change: InvoiceStatusChange(
                from: InvoiceStatus(rawValue: $0.old_status) ?? .new, to: InvoiceStatus(rawValue: $0.new_status) ?? .new,
                at: $0.changed_at, note: $0.note), device: $0.device)
        }
    }
}

struct SalesDTO: Codable {
    var schema_version: Int
    var id: UUID
    var buyer_id: UUID?
    var invoice_number: String
    var issue_date: LocalDate
    var delivery_date: LocalDate?
    var payment_due_date: LocalDate
    var payment_form: String
    var currency: String
    var bank_account_number: String
    var buyer_nip: String
    var buyer_name: String
    var buyer_address: String
    var notes: String
    var vat_exemption_type: String
    var vat_exemption_basis: String
    var status: String
    var environment: String
    var ksef_session_reference: String
    var ksef_invoice_reference: String
    var ksef_reference_number: String
    var error_message: String
    var xml_file: String?
    var upo_file: String?
    var amount_net: String
    var amount_vat: String
    var amount_gross: String
    var items: [ItemDTO]
    var created_at: Date
    var updated_at: Date
    var updated_by_device: String

    struct ItemDTO: Codable {
        var lp: Int
        var name: String
        var unit: String
        var quantity: String
        var unit_price_net: String
        var vat_rate: String
        var amount_net: String
        var amount_vat: String
        var amount_gross: String
    }

    init(_ s: OutgoingInvoice, xmlFile: String?, upoFile: String?) {
        schema_version = CloudFormat.schemaVersion
        id = s.id; buyer_id = s.buyerID; invoice_number = s.invoiceNumber; issue_date = s.issueDate
        delivery_date = s.deliveryDate; payment_due_date = s.paymentDueDate; payment_form = s.paymentForm.rawValue
        currency = s.currency; bank_account_number = s.bankAccountNumber; buyer_nip = s.buyerNIP; buyer_name = s.buyerName
        buyer_address = s.buyerAddress; notes = s.notes; vat_exemption_type = s.exemptionType.rawValue
        vat_exemption_basis = s.exemptionBasis; status = s.status.rawValue; environment = s.environment.rawValue
        ksef_session_reference = s.ksefSessionReference; ksef_invoice_reference = s.ksefInvoiceReference
        ksef_reference_number = s.ksefNumber; error_message = s.errorMessage; xml_file = xmlFile; upo_file = upoFile
        amount_net = CloudFormat.amount(s.amountNet); amount_vat = CloudFormat.amount(s.amountVAT)
        amount_gross = CloudFormat.amount(s.amountGross)
        items = s.items.enumerated().map { index, item in
            ItemDTO(lp: index + 1, name: item.name, unit: item.unit, quantity: DecimalText.string(item.quantity),
                    unit_price_net: CloudFormat.amount(item.unitPriceNet), vat_rate: item.vatRate.rawValue,
                    amount_net: CloudFormat.amount(item.amountNet), amount_vat: CloudFormat.amount(item.amountVAT),
                    amount_gross: CloudFormat.amount(item.amountGross))
        }
        created_at = s.createdAt; updated_at = s.updatedAt; updated_by_device = s.updatedByDevice
    }

    func invoice(companyID: UUID, xml: String, upo: String) -> OutgoingInvoice {
        var s = OutgoingInvoice(
            id: id, companyID: companyID, buyerID: buyer_id, invoiceNumber: invoice_number, issueDate: issue_date,
            deliveryDate: delivery_date, paymentDueDate: payment_due_date, paymentForm: PaymentForm(rawValue: payment_form) ?? .transfer,
            currency: currency, bankAccountNumber: bank_account_number, buyerNIP: buyer_nip, buyerName: buyer_name,
            buyerAddress: buyer_address, notes: notes, exemptionType: VATExemptionType(rawValue: vat_exemption_type) ?? .act,
            exemptionBasis: vat_exemption_basis, status: OutgoingInvoiceStatus(rawValue: status) ?? .draft,
            environment: KSeFEnvironment(rawValue: environment) ?? .test,
            items: items.sorted { $0.lp < $1.lp }.map {
                OutgoingInvoiceItem(name: $0.name, unit: $0.unit, quantity: DecimalText.parse($0.quantity) ?? 0,
                                    unitPriceNet: CloudFormat.amount($0.unit_price_net), vatRate: VATRate(rawValue: $0.vat_rate) ?? .standard)
            },
            createdAt: created_at, updatedAt: updated_at, updatedByDevice: updated_by_device)
        s.ksefSessionReference = ksef_session_reference
        s.ksefInvoiceReference = ksef_invoice_reference
        s.ksefNumber = ksef_reference_number
        s.errorMessage = error_message
        s.generatedXML = xml
        s.upoXML = upo
        return s
    }
}

struct BuyerDTO: Codable {
    var id: UUID
    var nip: String
    var name: String
    var address: String
    var email: String
    var phone: String
    var notes: String
    var updated_at: Date
    var updated_by_device: String

    init(_ b: Buyer) {
        id = b.id; nip = b.nip; name = b.name; address = b.address; email = b.email; phone = b.phone; notes = b.notes
        updated_at = b.updatedAt; updated_by_device = b.updatedByDevice
    }

    func buyer(companyID: UUID) -> Buyer {
        Buyer(id: id, companyID: companyID, nip: nip, name: name, address: address, email: email, phone: phone, notes: notes,
              updatedAt: updated_at, updatedByDevice: updated_by_device)
    }
}

struct CatalogDTO: Codable {
    var id: UUID
    var name: String
    var unit: String
    var unit_price_net: String
    var vat_rate: String
    var use_count: Int
    var last_used_at: Date?
    var updated_at: Date
    var updated_by_device: String

    init(_ c: CatalogItem) {
        id = c.id; name = c.name; unit = c.unit; unit_price_net = CloudFormat.amount(c.unitPriceNet)
        vat_rate = c.vatRate.rawValue; use_count = c.useCount; last_used_at = c.lastUsedAt
        updated_at = c.updatedAt; updated_by_device = c.updatedByDevice
    }

    func item(companyID: UUID) -> CatalogItem {
        CatalogItem(id: id, companyID: companyID, name: name, unit: unit, unitPriceNet: CloudFormat.amount(unit_price_net),
                    vatRate: VATRate(rawValue: vat_rate) ?? .standard, useCount: use_count, lastUsedAt: last_used_at,
                    updatedAt: updated_at, updatedByDevice: updated_by_device)
    }
}

struct PaymentFileDTO: Codable {
    var schema_version: Int
    var id: UUID
    var file_name: String
    var format: String
    var bank_key: String
    var debit_account: String
    var total_amount: String
    var invoice_count: Int
    var created_at: Date
    var content_file: String
    var items: [Line]

    struct Line: Codable {
        var invoice_id: UUID
        var amount: String
        var line_number: Int
    }

    init(_ f: PaymentFile, lines: [PaymentFileLine], contentFile: String) {
        schema_version = CloudFormat.schemaVersion
        id = f.id; file_name = f.fileName; format = f.format.rawValue; bank_key = f.bankKey; debit_account = f.debitAccount
        total_amount = CloudFormat.amount(f.totalAmount); invoice_count = f.invoiceCount; created_at = f.createdAt
        content_file = contentFile
        items = lines.map { .init(invoice_id: $0.invoiceID, amount: CloudFormat.amount($0.amount), line_number: $0.lineNumber) }
    }

    func file(companyID: UUID, content: Data) -> (PaymentFile, [PaymentFileLine]) {
        (PaymentFile(id: id, companyID: companyID, format: PaymentFileFormat(rawValue: format) ?? .elixir, bankKey: bank_key,
                     debitAccount: debit_account, fileName: file_name, content: content, totalAmount: CloudFormat.amount(total_amount),
                     invoiceCount: invoice_count, createdAt: created_at),
         items.map { PaymentFileLine(invoiceID: $0.invoice_id, amount: CloudFormat.amount($0.amount), lineNumber: $0.line_number) })
    }
}

struct StatementDTO: Codable {
    var schema_version: Int
    var id: UUID
    var file_name: String
    var account_number: String
    var statement_date: LocalDate?
    var status: String
    var file_format: String
    var uploaded_at: Date
    var confirmed_at: Date?
    var content_file: String
    var transactions: [TransactionDTO]

    struct TransactionDTO: Codable {
        var id: UUID
        var transaction_date: LocalDate
        var value_date: LocalDate
        var amount: String
        var currency: String
        var is_debit: Bool
        var description: String
        var counterparty: String
        var reference: String
        var is_matched: Bool
        var matches: [MatchDTO]
    }

    struct MatchDTO: Codable {
        var id: UUID
        var invoice_id: UUID
        var match_type: String
        var confidence: String
        var is_confirmed: Bool
        var confirmed_at: Date?
    }

    init(_ s: BankStatement, transactions: [BankTransaction], matches: [TransactionMatch], contentFile: String) {
        schema_version = CloudFormat.schemaVersion
        id = s.id; file_name = s.fileName; account_number = s.accountNumber; statement_date = s.statementDate
        status = s.status.rawValue; file_format = s.fileFormat; uploaded_at = s.uploadedAt; confirmed_at = s.confirmedAt
        content_file = contentFile
        self.transactions = transactions.map { tx in
            TransactionDTO(id: tx.id, transaction_date: tx.transactionDate, value_date: tx.valueDate,
                           amount: CloudFormat.amount(tx.amount), currency: tx.currency, is_debit: tx.isDebit,
                           description: tx.description, counterparty: tx.counterparty, reference: tx.reference,
                           is_matched: tx.isMatched,
                           matches: matches.filter { $0.transactionID == tx.id }.map {
                               MatchDTO(id: $0.id, invoice_id: $0.invoiceID, match_type: $0.type.rawValue,
                                        confidence: $0.confidence.rawValue, is_confirmed: $0.isConfirmed, confirmed_at: $0.confirmedAt)
                           })
        }
    }

    func statement(companyID: UUID, content: String) -> (BankStatement, [BankTransaction], [TransactionMatch]) {
        let statement = BankStatement(id: id, companyID: companyID, fileName: file_name, accountNumber: account_number,
                                      statementDate: statement_date, status: BankStatementStatus(rawValue: status) ?? .pending,
                                      fileFormat: file_format, rawContent: content, uploadedAt: uploaded_at, confirmedAt: confirmed_at)
        let txs = transactions.map {
            BankTransaction(id: $0.id, statementID: id, transactionDate: $0.transaction_date, valueDate: $0.value_date,
                            amount: CloudFormat.amount($0.amount), currency: $0.currency, isDebit: $0.is_debit,
                            description: $0.description, counterparty: $0.counterparty, reference: $0.reference, isMatched: $0.is_matched)
        }
        let matches = transactions.flatMap { tx in
            tx.matches.map {
                TransactionMatch(id: $0.id, transactionID: tx.id, invoiceID: $0.invoice_id,
                                 type: MatchType(rawValue: $0.match_type) ?? .manual,
                                 confidence: MatchConfidence(rawValue: $0.confidence) ?? .low,
                                 isConfirmed: $0.is_confirmed, confirmedAt: $0.confirmed_at)
            }
        }
        return (statement, txs, matches)
    }
}
