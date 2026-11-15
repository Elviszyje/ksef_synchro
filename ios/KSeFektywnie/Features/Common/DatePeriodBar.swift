import SwiftUI
import Domain

/// Pasek okresu nad listą: cały okres, ten miesiąc, poprzedni miesiąc albo własny zakres dat.
/// Kontrolka segmentowa na całą szerokość — segmenty dzielą się miejscem po równo, więc pasek
/// mieści się na każdym ekranie i w każdym języku (wcześniejsze „pigułki” wychodziły poza ekran).
struct DatePeriodBar: View {
    @Binding var period: DatePeriod
    @State private var editingRange = false

    private enum Segment: Hashable { case all, thisMonth, previousMonth, custom }

    /// Segment z kalendarzem nie wybiera okresu od razu, tylko otwiera arkusz zakresu dat.
    private var segment: Binding<Segment> {
        Binding {
            switch period {
            case .all: .all
            case .thisMonth: .thisMonth
            case .previousMonth: .previousMonth
            case .custom: .custom
            }
        } set: { segment in
            switch segment {
            case .all: period = .all
            case .thisMonth: period = .thisMonth
            case .previousMonth: period = .previousMonth
            case .custom: editingRange = true
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Okres", selection: segment) {
                Text("Wszystkie").tag(Segment.all)
                Text("Ten miesiąc").tag(Segment.thisMonth)
                Text("Poprzedni").tag(Segment.previousMonth)
                Image(systemName: "calendar").accessibilityLabel(Text("Zakres dat")).tag(Segment.custom)
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .labelsHidden()

            // Wybrany zakres dat pod paskiem; dotknięcie pozwala go zmienić
            // (ponowne dotknięcie zaznaczonego segmentu nic nie zgłasza).
            if case .custom(let from, let to) = period {
                Button { editingRange = true } label: {
                    Label("\(from.short) – \(to.short)", systemImage: "calendar")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .accessibilityIdentifier("period-custom")
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .animation(.snappy, value: period.isCustom)
        .sensoryFeedback(.selection, trigger: period)
        .sheet(isPresented: $editingRange) {
            DateRangeSheet(initial: period.bounds() ?? DatePeriod.thisMonth.bounds()!) { range in
                period = .custom(from: range.lowerBound, to: range.upperBound)
            }
        }
    }
}

/// Wybór własnego zakresu dat (oba końce włącznie).
private struct DateRangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var from: Date
    @State private var to: Date
    let onApply: (ClosedRange<LocalDate>) -> Void

    init(initial: ClosedRange<LocalDate>, onApply: @escaping (ClosedRange<LocalDate>) -> Void) {
        _from = State(initialValue: initial.lowerBound.date())
        _to = State(initialValue: initial.upperBound.date())
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Od", selection: $from, displayedComponents: .date)
                DatePicker("Do", selection: $to, in: from..., displayedComponents: .date)
            }
            .onChange(of: from) { _, value in if to < value { to = value } }
            .navigationTitle("Zakres dat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zastosuj", role: .confirm) {
                        onApply(LocalDate(from)...LocalDate(to))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Pasek okresu jako pierwszy wiersz listy (przewija się razem z nią, pod tytułem).
struct DatePeriodSection: View {
    @Binding var period: DatePeriod

    var body: some View {
        Section {
            DatePeriodBar(period: $period)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listSectionMargins(.horizontal, 0)
        .listSectionSeparator(.hidden)
        .listSectionSpacing(.compact)
    }
}

/// Komunikat dla listy pustej przez wybrany okres lub filtry (w liście, żeby nie zasłaniał paska okresu).
struct NoResultsSection: View {
    let onClear: () -> Void

    var body: some View {
        Section {
            ContentUnavailableView {
                Label("Brak wyników", systemImage: "calendar.badge.exclamationmark")
            } description: {
                Text("Nic nie pasuje do wybranego okresu i filtrów.")
            } actions: {
                Button("Pokaż wszystkie", action: onClear)
            }
            .listRowBackground(Color.clear)
        }
    }
}

extension LocalDate {
    /// Krótka data do etykiet (np. „1 wrz 2026”).
    var short: String { date().formatted(.dateTime.day().month(.abbreviated).year()) }
}
