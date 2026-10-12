import SwiftUI
import GRDB
import Domain
import Persistence

struct InvoicesView: View {
    @Environment(AppModel.self) private var model
    @State private var invoices: [Invoice] = []
    @State private var filter = InvoiceFilter()
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            List {
                if model.isDemo {
                    Section { Label("Tryb demo — dane przykładowe", systemImage: "theatermasks").font(.footnote) }
                }
                if let message = model.syncMessage {
                    Section { Label(message, systemImage: "arrow.triangle.2.circlepath").font(.footnote) }
                }
                ForEach(invoices) { invoice in
                    NavigationLink(value: invoice.id) { InvoiceRow(invoice: invoice) }
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
                ToolbarItem(placement: .topBarTrailing) { filterMenu }
            }
            .navigationTitle("Faktury")
            .navigationDestination(for: UUID.self) { InvoiceDetailView(invoiceID: $0) }
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

    private func observe() async {
        guard let repo = model.invoices else { return }
        do {
            for try await value in repo.observe(filter).values(in: model.database.reader) {
                invoices = value
            }
        } catch {
            loadError = error.localizedDescription
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
