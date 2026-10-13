import SwiftUI
import GRDB
import Domain
import Persistence

/// Przelewy: faktury „Do zapłaty” → plik dla banku → historia paczek.
struct PaymentsView: View {
    @Environment(AppModel.self) private var model
    @State private var payable: [Invoice] = []
    @State private var files: [PaymentFile] = []
    @State private var selection = Set<UUID>()
    @State private var accountNumber = ""
    @State private var generated: PaymentFile?
    @State private var error: String?

    private var account: CompanyBankAccount? {
        model.bankAccounts.first { $0.accountNumber == accountNumber } ?? model.defaultBankAccount
    }

    private var selectedInvoices: [Invoice] { payable.filter { selection.contains($0.id) } }
    private var selectedTotal: Decimal { selectedInvoices.reduce(0) { $0 + $1.amountGross } }

    var body: some View {
        NavigationStack {
            List {
                if model.bankAccounts.isEmpty {
                    Section {
                        NavigationLink { BankAccountsView() } label: {
                            Label("Dodaj rachunek firmowy, z którego wychodzą przelewy", systemImage: "building.columns")
                        }
                    }
                }

                Section {
                    if payable.isEmpty {
                        Text("Brak faktur do zapłaty. Zatwierdź fakturę do zapłaty w zakładce Faktury — pojawi się tutaj.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(payable) { invoice in
                        Button { toggle(invoice.id) } label: {
                            PayableRow(invoice: invoice, selected: selection.contains(invoice.id))
                        }
                        .tint(.primary)
                    }
                } header: {
                    HStack {
                        Text("Do zapłaty")
                        Spacer()
                        if !payable.isEmpty {
                            Button(selection.count == payable.count ? "Odznacz" : "Zaznacz wszystkie") {
                                selection = selection.count == payable.count ? [] : Set(payable.map(\.id))
                            }
                            .font(.caption)
                        }
                    }
                }

                if !selection.isEmpty, let account {
                    Section {
                        if model.bankAccounts.count > 1 {
                            Picker("Rachunek obciążany", selection: $accountNumber) {
                                ForEach(model.bankAccounts) { a in
                                    Text(a.accountNumber.groupedNRB).font(.caption.monospaced()).tag(a.accountNumber)
                                }
                            }
                        }
                        LabeledContent("Format pliku", value: PaymentFileFormat.forBank(account.bankKey).label)
                        LabeledContent("Faktur", value: "\(selection.count)")
                        LabeledContent("Suma") { Text(selectedTotal.money()).bold() }
                        Button(action: generate) {
                            Label("Generuj plik przelewów", systemImage: "doc.badge.arrow.up")
                        }
                        .buttonStyle(.glassProminent)
                        .frame(maxWidth: .infinity)
                    } footer: {
                        Text("Faktury zmienią status na „Przelew przygotowany”. Plik zaimportuj w bankowości internetowej.")
                    }
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }

                if !files.isEmpty {
                    Section("Historia plików") {
                        ForEach(files) { file in
                            NavigationLink { PaymentFileDetailView(file: file) } label: { PaymentFileRow(file: file) }
                        }
                    }
                }
            }
            .navigationTitle("Przelewy")
            .sheet(item: $generated) { file in PaymentFileShareSheet(file: file) }
            .task { await observePayable() }
            .task { await observeFiles() }
            .onAppear { if accountNumber.isEmpty { accountNumber = model.defaultBankAccount?.accountNumber ?? "" } }
        }
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func generate() {
        guard let payments = model.payments, let account, let company = model.company else { return }
        do {
            let payer = PaymentPayer(debitAccount: account.accountNumber, name: company.name, address: company.address)
            generated = try payments.generate(invoiceIDs: selectedInvoices.map(\.id), debitAccount: account, payer: payer)
            selection = []
            error = nil
        } catch {
            self.error = error.userMessage
        }
    }

    private func observePayable() async {
        guard let payments = model.payments else { return }
        do {
            for try await value in payments.observePayable().values(in: model.database.reader) {
                payable = value
                selection.formIntersection(value.map(\.id))
            }
        } catch {}
    }

    private func observeFiles() async {
        guard let payments = model.payments else { return }
        do {
            for try await value in payments.observeFiles().values(in: model.database.reader) { files = value }
        } catch {}
    }
}

struct PayableRow: View {
    let invoice: Invoice
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(selected ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(invoice.sellerName).lineLimit(1)
                Text(invoice.invoiceNumber).font(.caption).foregroundStyle(.secondary)
                if let due = invoice.paymentDueDate {
                    Text("Termin: \(due.formatted)").font(.caption)
                        .foregroundStyle(invoice.isOverdue(today: .today()) ? .red : .secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(invoice.amountGross.money(invoice.currency)).font(.subheadline.monospacedDigit())
                if invoice.isSplitPayment {
                    Text("MPP").font(.caption2.bold()).padding(.horizontal, 5).background(.orange.opacity(0.2), in: .capsule)
                }
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct PaymentFileRow: View {
    let file: PaymentFile

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(file.fileName).font(.subheadline)
            Text("\(file.invoiceCount) faktur · \(file.totalAmount.money())")
                .font(.caption).foregroundStyle(.secondary)
            Text(file.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct PaymentFileDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let file: PaymentFile
    @State private var invoices: [Invoice] = []
    @State private var confirmReset = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                LabeledContent("Format", value: file.format.label)
                LabeledContent("Rachunek obciążany", value: file.debitAccount.groupedNRB)
                LabeledContent("Suma") { Text(file.totalAmount.money()).bold() }
                if let url = try? PaymentFileExport.temporaryURL(for: file) {
                    ShareLink(item: url) { Label("Udostępnij plik", systemImage: "square.and.arrow.up") }
                }
            }
            Section("Faktury w pliku") {
                ForEach(invoices) { invoice in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(invoice.sellerName).lineLimit(1)
                            Text(invoice.invoiceNumber).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(invoice.amountGross.money(invoice.currency)).font(.subheadline.monospacedDigit())
                            Text(invoice.status.label).font(.caption2).foregroundStyle(invoice.status.color)
                        }
                    }
                }
            }
            Section {
                Button("Resetuj paczkę", role: .destructive) { confirmReset = true }
            } footer: {
                Text("Reset przywraca faktury do statusu „Do zapłaty” i usuwa plik z historii. Niedostępny, gdy któraś faktura jest już opłacona.")
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle(file.fileName)
        .navigationBarTitleDisplayMode(.inline)
        .task { invoices = (try? model.payments?.invoices(in: file.id)) ?? [] }
        .confirmationDialog("Zresetować paczkę?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Resetuj", role: .destructive) {
                do {
                    try model.payments?.reset(file.id)
                    dismiss()
                } catch {
                    self.error = error.userMessage
                }
            }
        }
    }
}

/// Arkusz po wygenerowaniu: udostępnienie pliku (Pliki, AirDrop, Mail).
struct PaymentFileShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let file: PaymentFile

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(.green)
                Text("Plik gotowy").font(.title2.bold())
                Text(file.fileName).font(.subheadline.monospaced())
                Text("\(file.invoiceCount) faktur · \(file.totalAmount.money())").foregroundStyle(.secondary)
                if let url = try? PaymentFileExport.temporaryURL(for: file) {
                    ShareLink(item: url) {
                        Label("Udostępnij plik", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                }
                Text("Zapisz plik w aplikacji Pliki albo wyślij go na komputer (AirDrop, poczta), a potem zaimportuj w bankowości internetowej jako paczkę przelewów.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Gotowe") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

enum PaymentFileExport {
    /// Plik w katalogu tymczasowym pod właściwą nazwą (rozszerzenie .txt/.pli ważne dla banku).
    static func temporaryURL(for file: PaymentFile) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "payments", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: file.fileName)
        try file.content.write(to: url, options: .atomic)
        return url
    }
}
