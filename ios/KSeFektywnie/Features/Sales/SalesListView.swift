import SwiftUI
import GRDB
import Domain
import Persistence

struct SalesListView: View {
    @Binding var kind: InvoiceKind
    @Environment(AppModel.self) private var model
    @State private var invoices: [OutgoingInvoice] = []
    @State private var period: DatePeriod = .all
    @State private var editing: OutgoingInvoice?
    @State private var previewing: OutgoingInvoice?
    @State private var openedFromLaunch = false

    var body: some View {
        NavigationStack {
            List {
                InvoiceKindSection(kind: $kind)
                if model.company?.ksefEnvironment == .test {
                    BannerRow(text: Text("Środowisko testowe KSeF — faktury nie mają skutków prawnych."), systemImage: "testtube.2")
                }
                if let message = model.syncBanner {
                    BannerRow(text: Text(message), systemImage: "arrow.triangle.2.circlepath")
                }
                if !invoices.isEmpty {
                    DatePeriodSection(period: $period)
                }
                if visible.isEmpty && !invoices.isEmpty {
                    NoResultsSection { period = .all }
                }
                ForEach(visible) { invoice in
                    Button { editing = invoice } label: { SalesRow(invoice: invoice) }
                        .tint(.primary)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Color.appLine)
                        .swipeActions(edge: .leading) {
                            Button { previewing = invoice } label: { Label("PDF", systemImage: "doc.richtext") }
                                .tint(.indigo)
                        }
                        .contextMenu {
                            Button { previewing = invoice } label: { Label("Podgląd PDF", systemImage: "doc.richtext") }
                            Button { editing = invoice } label: {
                                Label(invoice.canBeEdited ? "Edytuj" : "Szczegóły",
                                      systemImage: invoice.canBeEdited ? "pencil" : "info.circle")
                            }
                        }
                }
                .onDelete(perform: delete)
            }
            .listStyle(.plain)
            .appScreenBackground()
            .overlay {
                if invoices.isEmpty {
                    ContentUnavailableView {
                        Label("Brak faktur sprzedażowych", systemImage: "square.and.pencil")
                    } description: {
                        Text("Wystaw pierwszą fakturę. Wpisane pozycje i nabywcy zostaną zapamiętani do kolejnych faktur. Faktury wystawione w innych programach pojawią się tu po synchronizacji z KSeF.")
                    } actions: {
                        Button("Nowa faktura") { editing = model.newSalesDraft() }
                            .buttonStyle(.appPrimaryCompact)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = model.newSalesDraft() } label: { Label("Nowa faktura", systemImage: "plus") }
                }
            }
            .navigationTitle("Faktury")
            .companySwitcher()
            .animation(.snappy, value: model.syncBanner)
            .sheet(item: $editing) { invoice in
                if invoice.canBeEdited {
                    SalesInvoiceForm(initial: invoice)
                } else {
                    SalesInvoiceDetail(invoiceID: invoice.id)
                }
            }
            .sheet(item: $previewing) { invoice in
                NavigationStack {
                    InvoicePDFPreview(source: model.salesVisualization(invoice), templates: model.salesTemplates)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Zamknij") { previewing = nil } } }
                }
            }
            .refreshable {
                await model.refreshSalesSubmissions()
                // Pobiera też faktury sprzedażowe wystawione poza aplikacją.
                if model.ksefToken != nil { await model.sync() }
            }
            .task { await observe() }
            .task { await model.refreshSalesSubmissions() }
        }
    }

    /// Faktury z wybranego okresu (po dacie wystawienia).
    private var visible: [OutgoingInvoice] {
        guard let bounds = period.bounds() else { return invoices }
        return invoices.filter { bounds.contains($0.issueDate) }
    }

    private func observe() async {
        guard let sales = model.sales else { return }
        do {
            for try await value in sales.observe().values(in: model.database.reader) {
                invoices = value
                if let index = DebugLaunch.openSaleIndex, editing == nil, index <= value.count,
                   !openedFromLaunch {
                    openedFromLaunch = true
                    editing = value.sorted { $0.invoiceNumber < $1.invoiceNumber }[index - 1]
                }
            }
        } catch {}
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets where visible[index].status == .draft {
            try? model.sales?.deleteDraft(visible[index].id)
        }
    }
}

struct SalesRow: View {
    let invoice: OutgoingInvoice

    var body: some View {
        HStack(spacing: 12) {
            InitialsAvatar(name: invoice.buyerName)
            VStack(alignment: .leading, spacing: 2) {
                Text(invoice.buyerName)
                    .font(.grotesk(15, .medium, relativeTo: .headline))
                    .foregroundStyle(Color.appInk)
                    .lineLimit(1)
                Text("\(invoice.invoiceNumber) · \(invoice.issueDate.formatted)")
                    .font(.mono(12)).foregroundStyle(Color.appMuted).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(invoice.amountGross.money(invoice.currency))
                    .font(.grotesk(15, .medium, relativeTo: .subheadline))
                    .monospacedDigit()
                    .foregroundStyle(Color.appInk)
                    .lineLimit(1)
                Text(invoice.status.label)
                    .font(.grotesk(12, .medium, relativeTo: .caption))
                    .foregroundStyle(invoice.status.tone)
                    .lineLimit(1)
            }
            .layoutPriority(1)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

extension OutgoingInvoiceStatus {
    var label: LocalizedStringResource {
        switch self {
        case .draft: "Szkic"
        case .queued: "Oczekuje na wysyłkę"
        case .sending: "Wysyłanie"
        case .accepted: "Przyjęta przez KSeF"
        case .rejected: "Odrzucona przez KSeF"
        case .imported: "Z KSeF"
        }
    }

    var tone: Color {
        switch self {
        case .accepted: .appAccent
        case .rejected: .appDanger
        case .queued, .sending: .appWarning
        case .draft, .imported: .appMuted
        }
    }
}
