import PDFKit
import SwiftUI
import Domain
import Persistence

/// Podgląd wizualizacji faktury w PDF z udostępnianiem. Przy kilku szablonach (faktury sprzedażowe)
/// pasek narzędzi pozwala wybrać szablon; domyślny jest pierwszy na liście.
struct InvoicePDFPreview: View {
    let source: Result<PreparedInvoiceDocument, Error>
    let templates: [InvoiceTemplate]
    var isCostInvoice = false
    @State private var templateID: UUID
    @State private var pdf: Data?

    init(source: Result<PreparedInvoiceDocument, Error>, templates: [InvoiceTemplate], isCostInvoice: Bool = false) {
        self.source = source
        self.templates = templates
        self.isCostInvoice = isCostInvoice
        _templateID = State(initialValue: templates.first?.id ?? UUID())
    }

    private var template: InvoiceTemplate? { templates.first { $0.id == templateID } ?? templates.first }

    var body: some View {
        Group {
            switch source {
            case .failure(let error):
                ContentUnavailableView("Nie można przygotować wizualizacji", systemImage: "exclamationmark.triangle",
                                       description: Text(error.userMessage))
            case .success(let prepared):
                if let template {
                    let renderer = InvoiceVisualizationPDF(prepared: prepared, template: template, isCostInvoice: isCostInvoice)
                    content
                        .toolbar {
                            if templates.count > 1 {
                                ToolbarItem(placement: .primaryAction) {
                                    Menu {
                                        Picker("Szablon", selection: $templateID) {
                                            ForEach(templates) { Text($0.displayName).tag($0.id) }
                                        }
                                    } label: {
                                        Label("Szablon", systemImage: "paintpalette")
                                    }
                                    .accessibilityIdentifier("template-menu")
                                }
                            }
                            ToolbarItem(placement: .primaryAction) {
                                let file = InvoiceVisualizationFile(pdf: renderer)
                                ShareLink(item: file, preview: SharePreview(file.fileName, image: Image(systemName: "doc.richtext"))) {
                                    Label("Udostępnij PDF", systemImage: "square.and.arrow.up")
                                }
                                .accessibilityIdentifier("share-pdf")
                            }
                        }
                        .task(id: template) {
                            pdf = await Task.detached(priority: .userInitiated) { renderer.render() }.value
                        }
                }
            }
        }
        .navigationTitle("Wizualizacja PDF")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var content: some View {
        if let pdf {
            PDFKitView(data: pdf)
                .ignoresSafeArea(edges: .bottom)
                .accessibilityIdentifier("invoice-pdf")
        } else {
            ProgressView()
        }
    }
}

/// `PDFView` z PDFKit: przewijanie stron, powiększanie gestem.
struct PDFKitView: UIViewRepresentable {
    let data: Data

    final class Coordinator { var data: Data? }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.pageShadowsEnabled = true
        view.backgroundColor = .secondarySystemBackground
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        guard context.coordinator.data != data else { return }
        context.coordinator.data = data
        view.document = PDFDocument(data: data)
        view.autoScales = true
    }
}

extension InvoiceTemplate {
    /// Nazwa do wyświetlenia; wbudowany szablon ma nazwę w języku interfejsu.
    var displayName: String {
        id == InvoiceTemplate.standard(companyID: companyID).id ? String(localized: "Standardowy") : name.nonEmptyOr(String(localized: "Bez nazwy"))
    }

    var isBuiltIn: Bool { id == InvoiceTemplate.standard(companyID: companyID).id }
}

extension AppModel {
    var invoiceTemplates: InvoiceTemplateRepository? {
        company.map { InvoiceTemplateRepository(db: database, companyID: $0.id, device: deviceID) }
    }

    /// Szablony do wyboru przy fakturze sprzedażowej (domyślny pierwszy).
    var salesTemplates: [InvoiceTemplate] {
        (try? invoiceTemplates?.templates()) ?? company.map { [.standard(companyID: $0.id)] } ?? []
    }

    /// Faktury kosztowe po polsku; przy innym języku interfejsu — etykiety dwujęzyczne.
    var costTemplate: InvoiceTemplate {
        .costInvoice(language: Bundle.main.preferredLocalizations.first == "pl" ? .pl : .plEn)
    }

    func costVisualization(_ invoice: Invoice) -> Result<PreparedInvoiceDocument, Error> {
        Result {
            var prepared = try InvoiceVisualization.cost(invoice, environment: company?.ksefEnvironment ?? .production)
            // Nabywcą jesteśmy my; XML z KSeF często ma tylko NIP nabywcy.
            if let company, prepared.document.buyer.nip == company.nip, prepared.document.buyer.name.isEmpty {
                prepared.document.buyer.name = company.name
                if prepared.document.buyer.addressLines.isEmpty {
                    prepared.document.buyer.addressLines = company.address.components(separatedBy: .newlines).filter { !$0.isEmpty }
                }
            }
            return prepared
        }
    }

    func salesVisualization(_ invoice: OutgoingInvoice) -> Result<PreparedInvoiceDocument, Error> {
        Result {
            guard let seller = fa3Seller else { throw InvoiceVisualizationError.unreadableXML }
            return try InvoiceVisualization.sales(invoice, seller: seller)
        }
    }

    /// Faktura do podglądu szablonu: ostatnia sprzedażowa albo przykładowa, zawsze z kodem QR
    /// i bez znaku „projekt”, żeby było widać wszystkie elementy szablonu.
    func templateSample(today: LocalDate = .today()) -> PreparedInvoiceDocument? {
        let latest = (try? sales?.invoices())?.max { $0.issueDate < $1.issueDate }
        let invoice = latest ?? OutgoingInvoice(
            companyID: company?.id ?? UUID(), invoiceNumber: "FV/\(today.year)/0001", issueDate: today, deliveryDate: today,
            paymentDueDate: LocalDate(Calendar.current.date(byAdding: .day, value: 14, to: today.date())!),
            bankAccountNumber: defaultBankAccount?.accountNumber ?? "61109010140000071219812874",
            buyerNIP: "6260181591", buyerName: "Przykładowy Nabywca Sp. z o.o.", buyerAddress: "ul. Przykładowa 1\n00-001 Warszawa",
            items: [OutgoingInvoiceItem(name: String(localized: "Usługi doradcze"), unit: "h", quantity: 12, unitPriceNet: 180),
                    OutgoingInvoiceItem(name: String(localized: "Licencja oprogramowania — 12 miesięcy"), unit: "szt.", quantity: 1,
                                        unitPriceNet: 1200)])
        guard case .success(var prepared) = salesVisualization(invoice) else { return nil }
        prepared.isDraft = false
        if prepared.document.verificationURL == nil, let issue = prepared.document.issueDate {
            let number = "\(prepared.document.seller.nip)-\(issue.compact)-0A1B2C3D4E5F-6A"
            prepared.document.attachKSeF(number: number, environment: .test, xml: prepared.document.number)
        }
        return prepared
    }
}
