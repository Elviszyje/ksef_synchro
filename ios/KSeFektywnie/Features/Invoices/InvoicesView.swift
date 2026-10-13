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
    @State private var undo: UndoStatus?
    @State private var swipeFeedback = 0
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
                        .accessibilityIdentifier("invoice-\(invoice.id.uuidString)")
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rowFrames[invoice.id] = $0 }
                        // W prawo: zatwierdź do zapłaty. W lewo: sporna. Po każdym geście pasek „Cofnij”.
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if invoice.allowedTransitions.contains(.accepted) {
                                Button { swipe(invoice, to: .accepted) } label: {
                                    Label(invoice.isCorrection ? "Zatwierdź korektę" : "Do zapłaty", systemImage: "banknote")
                                }
                                .tint(.orange)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if invoice.allowedTransitions.contains(.disputed) {
                                Button { swipe(invoice, to: .disputed) } label: {
                                    Label("Sporna", systemImage: "exclamationmark.bubble")
                                }
                                .tint(.red)
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
                ToolbarItem(placement: .topBarLeading) {
                    Button { showDashboard = true } label: { Label("Podsumowanie kosztów", systemImage: "chart.bar") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !invoices.isEmpty { exportMenu }
                }
                ToolbarItem(placement: .topBarTrailing) { filterMenu }
            }
            .navigationTitle("Faktury")
            .navigationDestination(for: UUID.self) { InvoiceDetailView(invoiceID: $0) }
            .navigationDestination(isPresented: $showDashboard) { CostDashboardView() }
            .task(id: filter) { await observe() }
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
            Label("Filtry", systemImage: filter == InvoiceFilter(search: filter.search)
                  ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
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
                Text(item.invoiceNumber).font(.caption).foregroundStyle(.secondary)
                Text(item.current.label).font(.subheadline.weight(.semibold))
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
