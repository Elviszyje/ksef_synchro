import SwiftUI
import GRDB
import Domain
import Persistence

/// Historia wygenerowanych paczek przelewów z wyszukiwaniem i filtrami.
struct PaymentHistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var summaries: [PaymentFileSummary] = []
    @State private var filter = PaymentFileFilter()

    private var filtered: [PaymentFileSummary] { filter.apply(summaries) }

    /// Paczki pogrupowane po miesiącu utworzenia (najnowsze na górze).
    private var groups: [(title: String, items: [PaymentFileSummary])] {
        var order: [String] = []
        var byMonth: [String: [PaymentFileSummary]] = [:]
        for s in filtered {
            let title = s.file.createdAt.formatted(.dateTime.month(.wide).year())
            if byMonth[title] == nil { order.append(title) }
            byMonth[title, default: []].append(s)
        }
        return order.map { ($0, byMonth[$0]!) }
    }

    /// Banki występujące w historii — tylko te pokazujemy w filtrze.
    private var banks: [String] { Array(Set(summaries.map(\.file.bankKey))).sorted() }

    var body: some View {
        List {
            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items) { summary in
                        NavigationLink { PaymentFileDetailView(file: summary.file) } label: { HistoryRow(summary: summary) }
                    }
                }
            }
        }
        .overlay {
            if summaries.isEmpty {
                ContentUnavailableView("Brak paczek przelewów", systemImage: "clock.arrow.circlepath",
                                       description: Text("Wygenerowane pliki dla banku pojawią się tutaj."))
            } else if filtered.isEmpty {
                ContentUnavailableView {
                    Label("Brak wyników", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Żadna paczka nie pasuje do wyszukiwania i filtrów.")
                } actions: {
                    Button("Wyczyść filtry") { filter = PaymentFileFilter() }
                }
            }
        }
        .searchable(text: $filter.search, prompt: Text("Plik, sprzedawca, numer faktury"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { filterMenu }
        }
        .navigationTitle("Historia przelewów")
        .navigationBarTitleDisplayMode(.inline)
        .task { await observe() }
    }

    private var filterMenu: some View {
        Menu {
            Section("Stan") {
                ForEach(PaymentFileSummary.Settlement.allCases, id: \.self) { settlement in
                    Toggle(isOn: binding(for: settlement)) { Text(settlement.label) }
                }
            }
            Section("Okres") {
                Picker("Okres", selection: $filter.period) {
                    ForEach(PaymentFileFilter.Period.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            if banks.count > 1 {
                Section("Bank") {
                    ForEach(banks, id: \.self) { bank in
                        Toggle(isOn: binding(forBank: bank)) { Text(bankName(bank)) }
                    }
                }
            }
            if filter.isActive {
                Button("Wyczyść filtry", role: .destructive) {
                    let search = filter.search
                    filter = PaymentFileFilter()
                    filter.search = search
                }
            }
        } label: {
            Label("Filtry", systemImage: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }

    private func binding(for settlement: PaymentFileSummary.Settlement) -> Binding<Bool> {
        Binding(get: { filter.settlements.contains(settlement) },
                set: { on in if on { filter.settlements.insert(settlement) } else { filter.settlements.remove(settlement) } })
    }

    private func binding(forBank bank: String) -> Binding<Bool> {
        Binding(get: { filter.bankKeys.contains(bank) },
                set: { on in if on { filter.bankKeys.insert(bank) } else { filter.bankKeys.remove(bank) } })
    }

    private func bankName(_ key: String) -> String {
        BankDetection.label(for: key).nonEmptyOr(PaymentFileFormat.forBank(key).label)
    }

    private func observe() async {
        guard let payments = model.payments else { return }
        do {
            for try await value in payments.observeSummaries().values(in: model.database.reader) { summaries = value }
        } catch {}
    }
}

struct HistoryRow: View {
    let summary: PaymentFileSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: summary.settlement.symbol)
                .foregroundStyle(summary.settlement.color)
                .font(.title3)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(BankDetection.label(for: summary.file.bankKey).nonEmptyOr(summary.file.format.label))
                        .font(.headline)
                    Spacer(minLength: 8)
                    Text(summary.file.totalAmount.money()).font(.subheadline.monospacedDigit().weight(.semibold))
                }
                Text(summary.settlement.label)
                    .font(.caption2.bold())
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(summary.settlement.color.opacity(0.15), in: .capsule)
                    .foregroundStyle(summary.settlement.color)
                Text("\(summary.file.invoiceCount) faktur · \(summary.file.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                Text(summary.file.fileName)
                    .font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension PaymentFileSummary.Settlement {
    var label: LocalizedStringResource {
        switch self {
        case .pending: "Oczekuje na zapłatę"
        case .partial: "Częściowo rozliczona"
        case .settled: "Rozliczona"
        }
    }

    var color: Color {
        switch self {
        case .pending: .purple
        case .partial: .orange
        case .settled: .green
        }
    }

    var symbol: String {
        switch self {
        case .pending: "building.columns"
        case .partial: "circle.lefthalf.filled"
        case .settled: "checkmark.seal.fill"
        }
    }
}

extension PaymentFileFilter.Period {
    var label: LocalizedStringResource {
        switch self {
        case .all: "Cały okres"
        case .last30Days: "Ostatnie 30 dni"
        case .last90Days: "Ostatnie 90 dni"
        case .thisYear: "Ten rok"
        }
    }
}
