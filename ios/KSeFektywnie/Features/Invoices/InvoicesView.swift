import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
import GRDB
import Domain
import Persistence

struct InvoicesView: View {
    @Environment(AppModel.self) private var model
    @State private var invoices: [Invoice] = []
    @State private var filter = InvoiceFilter()
    @State private var loadError: String?
    @State private var showDashboard = DebugLaunch.openDashboard
    @State private var path: [UUID] = []
    @State private var rowFrames: [UUID: CGRect] = [:]
    @Environment(PaymentsFlight.self) private var flight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if model.isDemo {
                    Section { Label("Tryb demo — dane przykładowe", systemImage: "theatermasks").font(.footnote) }
                }
                if let message = model.syncMessage {
                    Section { Label(message, systemImage: "arrow.triangle.2.circlepath").font(.footnote) }
                }
                ForEach(invoices) { invoice in
                    NavigationLink(value: invoice.id) { InvoiceRow(invoice: invoice) }
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rowFrames[invoice.id] = $0 }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if invoice.allowedTransitions.contains(.accepted) {
                                Button { approve(invoice) } label: {
                                    Label(invoice.isCorrection ? "Zatwierdź korektę" : "Do zapłaty", systemImage: "banknote")
                                }
                                .tint(.orange)
                            }
                        }
                }
            }
            .overlay {
                if invoices.isEmpty {
                    ContentUnavailableView {
                        Label("Brak faktur", systemImage: "doc.text.magnifyingglass")
                    } description: {
                        if model.ksefToken == nil {
                            Text("Połącz aplikację z KSeF w Ustawieniach, aby pobrać faktury kosztowe.")
                        } else {
                            Text("Przeciągnij w dół, aby zsynchronizować z KSeF.")
                        }
                    }
                }
            }
            .searchable(text: $filter.search, prompt: Text("Numer, sprzedawca, NIP"))
            .refreshable { await model.sync() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showDashboard = true } label: { Label("Podsumowanie kosztów", systemImage: "chart.bar") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !invoices.isEmpty {
                        ShareLink(item: InvoiceCSVExport(invoices: invoices),
                                  preview: SharePreview(InvoiceCSVExport.fileName)) {
                            Label("Eksport CSV", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { filterMenu }
            }
            .navigationTitle("Faktury")
            .navigationDestination(for: UUID.self) { InvoiceDetailView(invoiceID: $0) }
            .navigationDestination(isPresented: $showDashboard) { CostDashboardView() }
            .task(id: filter) { await observe() }
        }
    }

    private var filterMenu: some View {
        Menu {
            Section("Status") {
                ForEach(InvoiceStatus.allCases, id: \.self) { status in
                    Toggle(isOn: Binding(
                        get: { filter.statuses.contains(status) },
                        set: { on in if on { filter.statuses.insert(status) } else { filter.statuses.remove(status) } })) {
                        Text(status.label)
                    }
                }
            }
            Toggle("Tylko przeterminowane", isOn: $filter.overdueOnly)
            Toggle("Tylko podzielona płatność", isOn: $filter.splitPaymentOnly)
        } label: {
            Label("Filtry", systemImage: filter == InvoiceFilter(search: filter.search)
                  ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
    }

    /// Zatwierdzenie z listy: faktura „wpada” do zakładki Przelewy.
    private func approve(_ invoice: Invoice) {
        do {
            try model.invoices?.changeStatus(invoice.id, to: .accepted, note: "Zatwierdzona do zapłaty z listy faktur.")
            if invoice.movesToPaymentsWhenAccepted, !reduceMotion, let frame = rowFrames[invoice.id] {
                flight.launch(from: CGPoint(x: frame.minX + 60, y: frame.midY))
            }
        } catch {
            loadError = error.userMessage
        }
    }

    private func observe() async {
        guard let repo = model.invoices else { return }
        do {
            for try await value in repo.observe(filter).values(in: model.database.reader) {
                invoices = value
                if path.isEmpty, let number = DebugLaunch.openInvoiceNumber,
                   let match = value.first(where: { $0.invoiceNumber == number }) {
                    path = [match.id]
                }
            }
        } catch {
            loadError = error.userMessage
        }
    }
}

extension InvoiceFilter {
    init(search: String) {
        self.init()
        self.search = search
    }
}

struct InvoiceRow: View {
    let invoice: Invoice

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: invoice.status.symbol)
                .foregroundStyle(invoice.status.color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(invoice.sellerName).font(.headline).lineLimit(1)
                Text(invoice.invoiceNumber).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if let due = invoice.paymentDueDate {
                    Text("Termin: \(due.formatted)")
                        .font(.caption)
                        .foregroundStyle(invoice.isOverdue(today: .today()) ? .red : .secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(invoice.amountGross.money(invoice.currency)).font(.subheadline.monospacedDigit().bold())
                if invoice.isSplitPayment {
                    Text("MPP").font(.caption2.bold()).padding(.horizontal, 5).background(.orange.opacity(0.2), in: .capsule)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// CSV bieżącej listy faktur, generowany dopiero w chwili udostępnienia.
struct InvoiceCSVExport: Transferable {
    let invoices: [Invoice]

    static var fileName: String { "faktury_\(LocalDate.today().iso).csv" }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            let url = FileManager.default.temporaryDirectory.appending(path: fileName)
            try InvoiceCSV.export(export.invoices) { String(localized: $0.label) }.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
