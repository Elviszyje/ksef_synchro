import SwiftUI
import GRDB
import Domain
import Persistence

/// Przelewy: faktury „Do zapłaty” → plik dla banku → historia paczek.
struct PaymentsView: View {
    @Environment(AppModel.self) private var model
    @State private var payable: [Invoice] = []
    @State private var showHistory = DebugLaunch.openPaymentHistory
    @State private var linkedFile: PaymentFile?
    @State private var selection = Set<UUID>()
    @State private var accountNumber = ""
    @State private var generated: PaymentFile?
    @State private var error: String?
    /// Faktury do zapłaty, których rachunek różni się od wcześniejszych faktur tego dostawcy.
    @State private var changedAccounts = Set<UUID>()

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
                } else if let account {
                    Section { accountRow(account) }
                }

                Section {
                    if payable.isEmpty {
                        Text("Brak faktur do zapłaty. Zatwierdź fakturę do zapłaty w zakładce Faktury — pojawi się tutaj.")
                            .font(.appSubheadline).foregroundStyle(.secondary)
                    }
                    ForEach(payable) { invoice in
                        Button { toggle(invoice.id) } label: {
                            PayableRow(invoice: invoice, selected: selection.contains(invoice.id),
                                       accountChanged: changedAccounts.contains(invoice.id))
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
                            .font(.appCaption)
                        }
                    }
                } footer: {
                    if !payable.isEmpty {
                        Text("Faktury zmienią status na „Przelew przygotowany”. Plik zaimportuj w bankowości internetowej.")
                    }
                }

                if let error {
                    Section { Text(error).foregroundStyle(Color.appDanger) }
                }

            }
            .appScreenBackground()
            .safeAreaInset(edge: .bottom) {
                if !selection.isEmpty, account != nil { summaryBar }
            }
            .animation(.snappy, value: selection.isEmpty)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { PaymentHistoryView() } label: {
                        Label("Historia przelewów", systemImage: "clock.arrow.circlepath")
                    }
                }
            }
            .navigationDestination(isPresented: $showHistory) { PaymentHistoryView() }
            .navigationDestination(item: $linkedFile) { PaymentFileDetailView(file: $0) }
            .onChange(of: model.openTarget, initial: true) { _, target in
                if case .paymentFile(let id)? = target {
                    linkedFile = try? model.payments?.files().first { $0.id == id }
                    model.openTarget = nil
                }
            }
            .navigationTitle("Przelewy")
            .sheet(item: $generated) { file in PaymentFileShareSheet(file: file) }
            .task { await observePayable() }
            .onAppear {
                if accountNumber.isEmpty { accountNumber = model.defaultBankAccount?.accountNumber ?? "" }
                if DebugLaunch.selectAllPayable { selection = Set(payable.map(\.id)) }
            }
        }
    }

    /// Rachunek obciążany i format pliku wynikający z banku tego rachunku.
    @ViewBuilder
    private func accountRow(_ account: CompanyBankAccount) -> some View {
        let label = HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Z rachunku firmowego").font(.appCaption).foregroundStyle(Color.appMuted)
                Text(account.accountNumber.groupedNRB)
                    .font(.mono(13, medium: true, relativeTo: .subheadline))
                    .foregroundStyle(Color.appInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            AppPill(text: Text(PaymentFileFormat.forBank(account.bankKey).label))
            if model.bankAccounts.count > 1 {
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.appMuted)
            }
        }
        if model.bankAccounts.count > 1 {
            Menu {
                Picker("Rachunek obciążany", selection: $accountNumber) {
                    ForEach(model.bankAccounts) { a in Text(a.accountNumber.groupedNRB).tag(a.accountNumber) }
                }
            } label: { label }
        } else {
            label
        }
    }

    /// Stałe podsumowanie wybranych przelewów z przyciskiem generowania pliku.
    private var summaryBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Wybrano: \(selection.count)")
                    .font(.grotesk(13, .medium, relativeTo: .footnote))
                    .foregroundStyle(Color.appOnGraphiteMuted)
                HeroAmount(amount: selectedTotal, size: 24, onGraphite: true)
            }
            Spacer(minLength: 8)
            Button("Generuj plik", action: generate)
                .buttonStyle(.appMint)
                .accessibilityIdentifier("generate-payment-file")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.appFeatureCard, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.appLine.opacity(0.6)))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
                let history = (try? model.invoices?.fetch()) ?? []
                changedAccounts = SellerAccountCheck.changedAccounts(in: value, history: history)
                if DebugLaunch.selectAllPayable, selection.isEmpty { selection = Set(value.map(\.id)) }
            }
        } catch {}
    }

}

struct PayableRow: View {
    let invoice: Invoice
    let selected: Bool
    var accountChanged = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: selected ? "checkmark" : "circle")
                .font(.system(size: selected ? 12 : 26, weight: selected ? .bold : .light))
                .foregroundStyle(selected ? Color.appOnPrimary : Color.appMuted)
                .frame(width: 26, height: 26)
                .background(selected ? Color.appPrimaryFill : Color.clear, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(invoice.sellerName)
                    .font(.grotesk(15, .medium, relativeTo: .headline))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(invoice.invoiceNumber).font(.mono(12)).lineLimit(1)
                    if invoice.isSplitPayment { Text("· MPP").font(.mono(12)) }
                }
                .foregroundStyle(Color.appMuted)
                if accountChanged {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                        Text("Inny rachunek niż dotąd — sprawdź")
                    }
                    .font(.grotesk(12, .medium, relativeTo: .caption))
                    .foregroundStyle(Color.appWarning)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(invoice.amountGross.money(invoice.currency))
                    .font(.grotesk(15, .medium, relativeTo: .subheadline))
                    .monospacedDigit()
                    .lineLimit(1)
                if let due = DueSummary(invoice, today: .today()) {
                    Text(due.text)
                        .font(.grotesk(12, .medium, relativeTo: .caption))
                        .foregroundStyle(due.color)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct PaymentFileRow: View {
    let file: PaymentFile

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(file.fileName).font(.appSubheadline)
            Text("\(file.invoiceCount) faktur · \(file.totalAmount.money())")
                .font(.appCaption).foregroundStyle(.secondary)
            Text(file.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.appCaption2).foregroundStyle(.secondary)
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
            if invoices.contains(where: { $0.status != .paid }) {
                ReminderSection(target: .paymentFile(file.id), makeDraft: { ReminderDrafts.paymentFile(file, invoices: invoices) })
            }
            Section("Faktury w pliku") {
                ForEach(invoices) { invoice in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(invoice.sellerName).lineLimit(1)
                            Text(invoice.invoiceNumber).font(.appCaption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(invoice.amountGross.money(invoice.currency)).font(.appSubheadline.monospacedDigit())
                            Text(invoice.status.label).font(.appCaption2).foregroundStyle(invoice.status.color)
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
        .appScreenBackground()
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
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color.appOnPrimary)
                    .frame(width: 72, height: 72)
                    .background(Color.appPrimaryFill, in: .circle)
                Text("Plik gotowy").font(.appTitle2.bold())
                Text(file.fileName).font(.appSubheadline.monospaced())
                Text("\(file.invoiceCount) faktur · \(file.totalAmount.money())").foregroundStyle(.secondary)
                if let url = try? PaymentFileExport.temporaryURL(for: file) {
                    ShareLink(item: url) {
                        Label("Udostępnij plik", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.appPrimary)
                }
                Text("Zapisz plik w aplikacji Pliki albo wyślij go na komputer (AirDrop, poczta), a potem zaimportuj w bankowości internetowej jako paczkę przelewów.")
                    .font(.appFootnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
