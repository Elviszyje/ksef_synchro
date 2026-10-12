import SwiftUI
import GRDB
import Domain
import Persistence

struct SalesListView: View {
    @Environment(AppModel.self) private var model
    @State private var invoices: [OutgoingInvoice] = []
    @State private var editing: OutgoingInvoice?
    @State private var openedFromLaunch = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(invoices) { invoice in
                    Button { editing = invoice } label: { SalesRow(invoice: invoice) }
                        .tint(.primary)
                }
                .onDelete(perform: delete)
            }
            .overlay {
                if invoices.isEmpty {
                    ContentUnavailableView {
                        Label("Brak faktur sprzedażowych", systemImage: "square.and.pencil")
                    } description: {
                        Text("Wystaw pierwszą fakturę. Wpisane pozycje i nabywcy zostaną zapamiętani do kolejnych faktur.")
                    } actions: {
                        Button("Nowa faktura") { editing = model.newSalesDraft() }
                            .buttonStyle(.glassProminent)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = model.newSalesDraft() } label: { Label("Nowa faktura", systemImage: "plus") }
                }
            }
            .navigationTitle("Sprzedaż")
            .sheet(item: $editing) { invoice in
                SalesInvoiceForm(initial: invoice)
            }
            .task { await observe() }
        }
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
        for index in offsets where invoices[index].canBeEdited {
            try? model.sales?.deleteDraft(invoices[index].id)
        }
    }
}

struct SalesRow: View {
    let invoice: OutgoingInvoice

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(invoice.buyerName).font(.headline).lineLimit(1)
                Text(invoice.invoiceNumber).font(.subheadline).foregroundStyle(.secondary)
                Text("Wystawiona: \(invoice.issueDate.formatted)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(invoice.amountGross.money(invoice.currency)).font(.subheadline.monospacedDigit().bold())
                Text(invoice.status.label).font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.secondary.opacity(0.15), in: .capsule)
            }
        }
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
        }
    }
}
