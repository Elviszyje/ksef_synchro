import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
import GRDB
import Domain
import Persistence

struct InvoicesView: View {
    @Binding var kind: InvoiceKind
    @Environment(AppModel.self) private var model
    @State private var invoices: [Invoice] = []
    @State private var filter = InvoiceFilter()
    @State private var period: DatePeriod = .all
    @State private var loadError: String?
    @State private var path: [UUID] = []
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var undo: UndoStatus?
    @State private var swipeFeedback = 0
    @Environment(PaymentsFlight.self) private var flight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack(path: $path) {
            List {
                InvoiceKindSection(kind: $kind)
                if model.isDemo && !DebugLaunch.storeShots {
                    BannerRow(text: Text("Tryb demo — dane przykładowe"), systemImage: "theatermasks")
                }
                if let message = model.syncBanner {
                    BannerRow(text: Text(message), systemImage: "arrow.triangle.2.circlepath")
                }
                if !invoices.isEmpty || isNarrowed {
                    DatePeriodSection(period: $period)
                    QuickFilterSection(filter: $filter)
                }
                if invoices.isEmpty && isNarrowed {
                    NoResultsSection { clearFilters() }
                }
                ForEach(InvoiceDayGroup.make(invoices)) { group in
                    Section {
                        ForEach(group.invoices) { invoice in
                            NavigationLink(value: invoice.id) { InvoiceRow(invoice: invoice) }
                                .accessibilityIdentifier("invoice-\(invoice.id.uuidString)")
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rowFrames[invoice.id] = $0 }
                                // W prawo: zatwierdź do zapłaty. W lewo: sporna. Po każdym geście pasek „Cofnij”.
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    if invoice.allowedTransitions.contains(.accepted) {
                                        Button { swipe(invoice, to: .accepted) } label: {
                                            Label(invoice.isCorrection ? "Zatwierdź korektę" : "Do zapłaty", systemImage: "banknote")
                                        }
                                        .tint(Color.appSwipeApprove)
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    if invoice.allowedTransitions.contains(.disputed) {
                                        Button { swipe(invoice, to: .disputed) } label: {
                                            Label("Sporna", systemImage: "exclamationmark.bubble")
                                        }
                                        .tint(Color.appSwipeDispute)
                                    }
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparatorTint(Color.appLine)
                        }
                    } header: {
                        InvoiceDayHeader(group: group)
                    }
                }
            }
            .listStyle(.plain)
            .appScreenBackground()
            .overlay {
                if invoices.isEmpty && !isNarrowed {
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
            .safeAreaInset(edge: .bottom) {
                if let undo {
                    UndoBanner(item: undo) { performUndo(undo) }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: undo.id) {
                            try? await Task.sleep(for: .seconds(5))
                            withAnimation(.snappy) { if self.undo?.id == undo.id { self.undo = nil } }
                        }
                }
            }
            .sensoryFeedback(.selection, trigger: swipeFeedback)
            .searchable(text: $filter.search, prompt: Text("Numer, sprzedawca, NIP"))
            .refreshable { await model.sync() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !invoices.isEmpty { exportMenu }
                }
                ToolbarItem(placement: .topBarTrailing) { filterMenu }
            }
            .navigationTitle("Faktury")
            .animation(.snappy, value: model.syncBanner)
            .navigationDestination(for: UUID.self) { InvoiceDetailView(invoiceID: $0) }
            .task(id: filter) { await observe() }
            .onChange(of: period, initial: true) { _, period in
                let bounds = period.bounds()
                filter.issuedFrom = bounds?.lowerBound
                filter.issuedTo = bounds?.upperBound
            }
            .onChange(of: model.openTarget, initial: true) { _, target in
                if case .invoice(let id)? = target {
                    path = [id]
                    model.openTarget = nil
                }
            }
            .task(id: invoices.count) {
                guard DebugLaunch.dumpExports, !invoices.isEmpty else { return }
                let export = InvoiceExport(invoices: invoices, companyName: model.company?.name ?? "",
                                           companyNIP: model.company?.nip ?? "", today: .today())
                let dir = URL.documentsDirectory.appending(path: "exports")
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try? export.xlsx().write(to: dir.appending(path: "faktury.xlsx"))
                try? InvoicePDF(export: export).render().write(to: dir.appending(path: "faktury.pdf"))
            }
            .task {
                guard let raw = DebugLaunch.autoSwipe, let status = InvoiceStatus(rawValue: raw == "accepted" ? "zaakceptowana" : "sporna") else { return }
                try? await Task.sleep(for: .seconds(2))
                if let first = invoices.first(where: { $0.allowedTransitions.contains(status) }) { swipe(first, to: status) }
            }
        }
    }

    private var exportMenu: some View {
        let export = InvoiceExport(invoices: invoices, companyName: model.company?.name ?? "",
                                   companyNIP: model.company?.nip ?? "", today: .today())
        return Menu {
            ShareLink(item: InvoiceXLSXFile(export: export),
                      preview: SharePreview("\(export.baseName).xlsx", image: Image(systemName: "tablecells"))) {
                Label("Excel (.xlsx)", systemImage: "tablecells")
            }
            ShareLink(item: InvoicePDFFile(export: export),
                      preview: SharePreview("\(export.baseName).pdf", image: Image(systemName: "doc.richtext"))) {
                Label("PDF", systemImage: "doc.richtext")
            }
        } label: {
            Label("Eksportuj", systemImage: "square.and.arrow.up")
        }
        .accessibilityIdentifier("export-menu")
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
            Label("Filtry", systemImage: hasMenuFilters
                  ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }

    /// Filtry z menu (bez wyszukiwania i okresu — te są widoczne osobno).
    private var hasMenuFilters: Bool {
        !filter.statuses.isEmpty || filter.overdueOnly || filter.splitPaymentOnly
    }

    /// Lista zawężona okresem lub filtrami z menu (pusta lista to wtedy „brak wyników”).
    private var isNarrowed: Bool { period != .all || hasMenuFilters }

    private func clearFilters() {
        period = .all
        filter = InvoiceFilter(search: filter.search)
    }

    /// Zmiana statusu gestem na liście. Zatwierdzona faktura „wpada” do zakładki Przelewy.
    private func swipe(_ invoice: Invoice, to status: InvoiceStatus) {
        let note: String = status == .accepted ? "Zatwierdzona do zapłaty z listy faktur." : "Oznaczona jako sporna z listy faktur."
        do {
            try model.invoices?.changeStatus(invoice.id, to: status, note: note)
            let after = (try? model.invoices?.find(invoice.id))??.status ?? status
            if status == .accepted, invoice.movesToPaymentsWhenAccepted, !reduceMotion, let frame = rowFrames[invoice.id] {
                flight.launch(from: CGPoint(x: frame.minX + 60, y: frame.midY))
            }
            withAnimation(.snappy) {
                undo = UndoStatus(invoiceID: invoice.id, invoiceNumber: invoice.invoiceNumber, previous: invoice.status, current: after)
            }
            swipeFeedback += 1
        } catch {
            loadError = error.userMessage
        }
    }

    private func performUndo(_ item: UndoStatus) {
        _ = try? model.invoices?.revertStatus(item.invoiceID, from: item.current, to: item.previous)
        withAnimation(.snappy) { undo = nil }
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

/// Faktury z jednego dnia wystawienia (lista jest posortowana od najnowszych).
struct InvoiceDayGroup: Identifiable {
    let date: LocalDate
    var invoices: [Invoice]
    var id: LocalDate { date }

    var newCount: Int { invoices.filter { $0.status == .new }.count }
    /// Suma brutto faktur w PLN; nil, gdy w grupie są tylko inne waluty.
    var totalPLN: Decimal? {
        let pln = invoices.filter { $0.currency == "PLN" }
        return pln.isEmpty ? nil : pln.reduce(0) { $0 + $1.amountGross }
    }

    static func make(_ invoices: [Invoice]) -> [InvoiceDayGroup] {
        var groups: [InvoiceDayGroup] = []
        for invoice in invoices {
            if groups.last?.date == invoice.issueDate {
                groups[groups.count - 1].invoices.append(invoice)
            } else {
                groups.append(InvoiceDayGroup(date: invoice.issueDate, invoices: [invoice]))
            }
        }
        return groups
    }
}

/// Nagłówek dnia: „Dziś, 26 listopada” i liczba nowych faktur albo suma dnia.
struct InvoiceDayHeader: View {
    let group: InvoiceDayGroup
    var today: LocalDate = .today()

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            if group.newCount > 0 {
                Text("\(group.newCount) nowych").foregroundStyle(Color.appAccent)
            } else if let total = group.totalPLN, group.invoices.count > 1 {
                Text(total.money()).monospacedDigit()
            }
        }
        .font(.grotesk(13, .medium, relativeTo: .footnote))
        .foregroundStyle(Color.appMuted)
        .textCase(nil)
    }

    private var title: String {
        let date = group.date.date()
        let includeYear = group.date.year != today.year
        let dayMonth = date.formatted(includeYear ? .dateTime.day().month(.wide).year() : .dateTime.day().month(.wide))
        switch DueSummary.days(from: group.date, to: today) {
        case 0: return String(localized: "Dziś, \(dayMonth)")
        case 1: return String(localized: "Wczoraj, \(dayMonth)")
        default:
            let weekday = date.formatted(.dateTime.weekday(.wide))
            return "\(weekday.prefix(1).uppercased() + weekday.dropFirst()), \(dayMonth)"
        }
    }
}

/// Szybkie filtry pod paskiem okresu. Zmieniają ten sam filtr co menu „Filtry”.
struct QuickFilterSection: View {
    @Binding var filter: InvoiceFilter

    var body: some View {
        Section {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    chip("Nowe", isOn: filter.statuses == [.new]) {
                        filter.statuses = filter.statuses == [.new] ? [] : [.new]
                    }
                    chip("Zatwierdzone", isOn: filter.statuses == [.accepted]) {
                        filter.statuses = filter.statuses == [.accepted] ? [] : [.accepted]
                    }
                    chip("Po terminie", isOn: filter.overdueOnly) { filter.overdueOnly.toggle() }
                    chip("MPP", isOn: filter.splitPaymentOnly) { filter.splitPaymentOnly.toggle() }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listSectionSeparator(.hidden)
    }

    private func chip(_ title: LocalizedStringKey, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.grotesk(13, .medium, relativeTo: .footnote))
                .foregroundStyle(isOn ? Color.appOnPrimary : Color.appInk)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(isOn ? Color.appPrimaryFill : Color.appSurface, in: .capsule)
                .overlay { if !isOn { Capsule().strokeBorder(Color.appLine) } }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Ostatnia zmiana statusu gestem — do cofnięcia.
struct UndoStatus: Identifiable, Equatable {
    let id = UUID()
    let invoiceID: UUID
    let invoiceNumber: String
    let previous: InvoiceStatus
    let current: InvoiceStatus
}

struct UndoBanner: View {
    let item: UndoStatus
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.current.symbol).foregroundStyle(item.current.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.invoiceNumber).font(.appCaption).foregroundStyle(.secondary)
                Text(item.current.label).font(.appSubheadline.weight(.semibold))
            }
            Spacer()
            Button("Cofnij", action: onUndo)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
        .glassEffect(in: .rect(cornerRadius: 18))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text("Cofnij"), onUndo)
    }
}
