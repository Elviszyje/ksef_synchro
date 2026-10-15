import SwiftUI
import Domain

/// Pasek okresu nad listą: cały okres, ten miesiąc, poprzedni miesiąc albo własny zakres dat.
struct DatePeriodBar: View {
    @Binding var period: DatePeriod
    @State private var editingRange = false
    private static let customID = "custom"

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    chip("Wszystkie", selected: period == .all) { period = .all }
                    chip("Ten miesiąc", selected: period == .thisMonth) { period = .thisMonth }
                    chip("Poprzedni miesiąc", selected: period == .previousMonth) { period = .previousMonth }
                    chip(customLabel, systemImage: "calendar", selected: period.isCustom) { editingRange = true }
                        .accessibilityIdentifier("period-custom")
                        .id(Self.customID)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
        }
        .scrollClipDisabled()
        // Wybrany zakres dat (najdłuższa etykieta, ostatnia w rzędzie) ma być widoczny.
        .onChange(of: period, initial: true) { _, period in
            if period.isCustom { withAnimation(.snappy) { proxy.scrollTo(Self.customID, anchor: .trailing) } }
        }
        }
        .sensoryFeedback(.selection, trigger: period)
        .sheet(isPresented: $editingRange) {
            DateRangeSheet(initial: period.bounds() ?? DatePeriod.thisMonth.bounds()!) { range in
                period = .custom(from: range.lowerBound, to: range.upperBound)
            }
        }
    }

    private var customLabel: LocalizedStringResource {
        guard case .custom(let from, let to) = period else { return "Zakres dat" }
        return "\(from.short) – \(to.short)"
    }

    @ViewBuilder
    private func chip(_ title: LocalizedStringResource, systemImage: String? = nil, selected: Bool,
                      action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            if let systemImage {
                Label { Text(title) } icon: { Image(systemName: systemImage) }
            } else {
                Text(title)
            }
        }
        .font(.subheadline.weight(selected ? .semibold : .regular))
        .controlSize(.small)
        .accessibilityAddTraits(selected ? .isSelected : [])
        if selected {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass)
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
