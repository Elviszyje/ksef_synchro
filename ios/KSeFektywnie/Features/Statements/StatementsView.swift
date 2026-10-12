import SwiftUI
import UniformTypeIdentifiers
import GRDB
import Domain
import Persistence

/// Wyciągi: import pliku z banku → przegląd dopasowań → zatwierdzenie (faktury „opłacone”).
struct StatementsView: View {
    @Environment(AppModel.self) private var model
    @State private var summaries: [StatementSummary] = []
    @State private var importing = false
    @State private var error: String?
    @State private var path: [UUID] = []
    @State private var openedFromLaunch = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
                ForEach(summaries) { summary in
                    NavigationLink(value: summary.statement.id) { StatementRow(summary: summary) }
                }
                .onDelete { offsets in offsets.map { summaries[$0].id }.forEach { try? model.statements?.delete($0) } }
            }
            .overlay {
                if summaries.isEmpty {
                    ContentUnavailableView {
                        Label("Brak wyciągów", systemImage: "tray.and.arrow.down")
                    } description: {
                        Text("Pobierz wyciąg z bankowości (MT940, CSV Erste lub VeloBank) i zaimportuj go, aby rozliczyć przekazane do opłacenia faktury.")
                    } actions: {
                        Button("Importuj wyciąg") { importing = true }.buttonStyle(.glassProminent)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { importing = true } label: { Label("Importuj wyciąg", systemImage: "square.and.arrow.down") }
                }
            }
            .navigationTitle("Wyciągi")
            .navigationDestination(for: UUID.self) { StatementReviewView(statementID: $0) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .commaSeparatedText, .text, .data]) { result in
                importFile(result)
            }
            .task { await observe() }
        }
    }

    private func importFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard let statements = model.statements else { return }
            let statement = try statements.importStatement(fileName: url.lastPathComponent, data: data,
                                                           preferredBankKeys: model.preferredBankKeys)
            error = nil
            path = [statement.id]
        } catch {
            self.error = error.userMessage
        }
    }

    private func observe() async {
        guard let statements = model.statements else { return }
        do {
            for try await value in statements.observeSummaries().values(in: model.database.reader) {
                summaries = value
                if DebugLaunch.openFirstStatement, path.isEmpty, !openedFromLaunch, let first = value.first {
                    openedFromLaunch = true
                    path = [first.id]
                }
            }
        } catch {}
    }
}

struct StatementRow: View {
    let summary: StatementSummary

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.statement.fileName).lineLimit(1)
                Text("Obciążeń: \(summary.debitCount) · dopasowanych: \(summary.matchCount)")
                    .font(.caption).foregroundStyle(.secondary)
                if let date = summary.statement.statementDate {
                    Text(date.formatted).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if summary.statement.status == .confirmed {
                Label("Zatwierdzony", systemImage: "checkmark.seal.fill").labelStyle(.iconOnly).foregroundStyle(.green)
            }
        }
    }
}

struct StatementReviewView: View {
    let statementID: UUID
    @Environment(AppModel.self) private var model
    @State private var statement: BankStatement?
    @State private var rows: [ReviewedTransaction] = []
    @State private var showCredits = false
    @State private var assigning: BankTransaction?
    @State private var confirmAll = false
    @State private var message: String?

    private var debits: [ReviewedTransaction] { rows.filter(\.transaction.isDebit) }
    private var credits: [ReviewedTransaction] { rows.filter { !$0.transaction.isDebit } }
    private var confirmedCount: Int { rows.flatMap(\.matches).filter(\.match.isConfirmed).count }
    private var isConfirmed: Bool { statement?.status == .confirmed }

    var body: some View {
        List {
            if isConfirmed {
                Section { Label("Wyciąg zatwierdzony — dopasowane faktury są opłacone.", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
            } else {
                Section {
                    Text("Sprawdź propozycje i włącz te, które są właściwe. Dopasowanie „niepewne” oznacza zgodność samej kwoty.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let message { Section { Text(message).foregroundStyle(.red) } }

            Section("Obciążenia") {
                ForEach(debits) { row in
                    TransactionReviewRow(row: row, locked: isConfirmed,
                                         onToggle: { id, on in try? model.statements?.setConfirmed(id, on) },
                                         onAssign: { assigning = row.transaction },
                                         onRemove: { try? model.statements?.removeMatch($0) })
                }
            }

            if !credits.isEmpty {
                Section {
                    DisclosureGroup("Wpływy (\(credits.count))", isExpanded: $showCredits) {
                        ForEach(credits) { row in TransactionHeader(transaction: row.transaction) }
                    }
                }
            }
        }
        .navigationTitle(statement?.fileName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isConfirmed {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zatwierdź") { confirmAll = true }.disabled(confirmedCount == 0)
                }
            }
        }
        .confirmationDialog("Oznaczyć \(confirmedCount) faktur jako opłacone?", isPresented: $confirmAll, titleVisibility: .visible) {
            Button("Zatwierdź wyciąg") {
                do {
                    try model.statements?.confirm(statementID)
                    statement = try model.statements?.statement(statementID)
                } catch {
                    message = error.userMessage
                }
            }
        }
        .sheet(item: $assigning) { tx in
            ManualMatchSheet(transaction: tx) { invoiceID in
                try? model.statements?.assignManually(transactionID: tx.id, invoiceID: invoiceID)
            }
        }
        .task {
            statement = try? model.statements?.statement(statementID)
            guard let statements = model.statements else { return }
            do {
                for try await value in statements.observeReview(statementID).values(in: model.database.reader) { rows = value }
            } catch {}
        }
    }
}

struct TransactionHeader: View {
    let transaction: BankTransaction

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description.isEmpty ? transaction.counterparty : transaction.description)
                    .font(.subheadline).lineLimit(3)
                Text(transaction.transactionDate.formatted).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text((transaction.isDebit ? -transaction.amount : transaction.amount).money(transaction.currency))
                .font(.subheadline.monospacedDigit().bold())
                .foregroundStyle(transaction.isDebit ? Color.primary : Color.green)
        }
    }
}

struct TransactionReviewRow: View {
    let row: ReviewedTransaction
    let locked: Bool
    let onToggle: (UUID, Bool) -> Void
    let onAssign: () -> Void
    let onRemove: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TransactionHeader(transaction: row.transaction)
            ForEach(row.matches, id: \.match.id) { pair in
                HStack(alignment: .top, spacing: 10) {
                    ConfidenceBadge(confidence: pair.match.confidence, manual: pair.match.type == .manual)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(pair.invoice.sellerName).font(.subheadline).lineLimit(1)
                        Text("\(pair.invoice.invoiceNumber) · \(pair.invoice.amountGross.money(pair.invoice.currency))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Potwierdź", isOn: Binding(get: { pair.match.isConfirmed },
                                                      set: { onToggle(pair.match.id, $0) }))
                        .labelsHidden()
                        .disabled(locked)
                }
                .contextMenu {
                    if !locked {
                        Button("Usuń dopasowanie", role: .destructive) { onRemove(pair.match.id) }
                    }
                }
            }
            if row.matches.isEmpty && !locked {
                Button(action: onAssign) { Label("Przypisz fakturę", systemImage: "link.badge.plus") }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ConfidenceBadge: View {
    let confidence: MatchConfidence
    let manual: Bool

    var body: some View {
        Text(manual ? LocalizedStringResource("ręcznie") : label)
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
    }

    private var label: LocalizedStringResource {
        switch confidence {
        case .high: "pewne"
        case .medium: "możliwe"
        case .low: "niepewne"
        }
    }

    private var color: Color {
        if manual { return .blue }
        switch confidence {
        case .high: return .green
        case .medium: return .orange
        case .low: return .red
        }
    }
}

struct ManualMatchSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let transaction: BankTransaction
    let onPick: (UUID) -> Void
    @State private var candidates: [Invoice] = []

    var body: some View {
        NavigationStack {
            List {
                Section { TransactionHeader(transaction: transaction) }
                Section("Faktury do zapłaty") {
                    ForEach(candidates) { invoice in
                        Button {
                            onPick(invoice.id)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(invoice.sellerName).lineLimit(1)
                                    Text(invoice.invoiceNumber).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(invoice.amountGross.money(invoice.currency)).font(.subheadline.monospacedDigit())
                                    .foregroundStyle(invoice.amountGross == transaction.amount ? Color.green : Color.primary)
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
            .overlay {
                if candidates.isEmpty {
                    ContentUnavailableView("Brak faktur do przypisania", systemImage: "doc.text.magnifyingglass",
                                           description: Text("Przypisać można faktury zaakceptowane lub przekazane do opłacenia."))
                }
            }
            .navigationTitle("Przypisz fakturę")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } } }
            .task { candidates = (try? model.statements?.manualCandidates(for: transaction)) ?? [] }
        }
    }
}
