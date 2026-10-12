import SwiftUI
import Charts
import Domain

/// Podsumowanie kosztów: 12 miesięcy, średnia, do zapłaty, top sprzedawcy w bieżącym miesiącu.
struct CostDashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var summary: CostSummary?

    var body: some View {
        List {
            if let summary {
                Section {
                    HStack(spacing: 12) {
                        StatTile(title: "12 miesięcy", value: summary.totalGross.money())
                        StatTile(title: "Średnio / mies.", value: summary.averageGross.money())
                    }
                    HStack(spacing: 12) {
                        StatTile(title: "Do zapłaty", value: summary.unpaidGross.money())
                        StatTile(title: "Po terminie", value: "\(summary.overdueCount)",
                                 tint: summary.overdueCount > 0 ? .red : .primary)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Section("Koszty brutto miesięcznie") {
                    Chart(summary.months) { month in
                        BarMark(x: .value("Miesiąc", monthLabel(month)),
                                y: .value("Brutto", NSDecimalNumber(decimal: month.gross).doubleValue))
                            .foregroundStyle(.tint)
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let v = value.as(Double.self) { Text(v, format: .number.notation(.compactName)) }
                            }
                        }
                    }
                    .frame(height: 200)
                    .accessibilityLabel(Text("Wykres kosztów brutto z ostatnich 12 miesięcy"))
                    if summary.otherCurrencyCount > 0 {
                        Text("Faktury w innych walutach (\(summary.otherCurrencyCount)) nie są wliczane do sum.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Najwięksi dostawcy w tym miesiącu") {
                    if summary.topSellers.isEmpty {
                        Text("Brak faktur w tym miesiącu.").foregroundStyle(.secondary)
                    }
                    ForEach(summary.topSellers) { seller in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(seller.name).lineLimit(1)
                                Text("NIP \(seller.nip) · \(seller.count) fakt.").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(seller.gross.money()).font(.subheadline.monospacedDigit())
                        }
                    }
                }
            }
        }
        .navigationTitle("Podsumowanie kosztów")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let invoices = (try? model.invoices?.fetch()) ?? []
            summary = CostSummary.make(invoices, today: .today())
        }
    }

    private func monthLabel(_ m: CostSummary.Month) -> String {
        LocalDate(year: m.year, month: m.month, day: 1)!.date().formatted(.dateTime.month(.abbreviated))
    }
}

struct StatTile: View {
    let title: LocalizedStringKey
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16))
    }
}
