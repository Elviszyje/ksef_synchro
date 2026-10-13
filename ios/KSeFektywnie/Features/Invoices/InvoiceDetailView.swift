import SwiftUI
import Domain
import Persistence

struct InvoiceDetailView: View {
    let invoiceID: UUID
    @Environment(AppModel.self) private var model
    @Environment(PaymentsFlight.self) private var flight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var statusButtonFrame: CGRect = .zero
    @State private var invoice: Invoice?
    @State private var log: [InvoiceStatusLogEntry] = []
    @State private var notes = ""
    @State private var error: String?

    var body: some View {
        Form {
            if let invoice {
                // Jeden zwarty wiersz. `LabeledContent` z `Label` w formularzu iOS 26 dostawał
                // błędnie wyliczoną, zmienną wysokość (puste miejsce pod statusem).
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: invoice.status.symbol)
                            .font(.title2)
                            .foregroundStyle(invoice.status.color)
                            .frame(width: 32)
                            .contentTransition(.symbolEffect(.replace))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Status").font(.caption).foregroundStyle(.secondary)
                            Text(invoice.status.label).font(.headline).foregroundStyle(invoice.status.color)
                        }
                        Spacer(minLength: 8)
                        if !invoice.statusActions.isEmpty {
                            Menu {
                                ForEach(invoice.statusActions, id: \.target) { action in
                                    Button { change(to: action.target) } label: {
                                        Label {
                                            Text(action.title)
                                            if let subtitle = action.subtitle { Text(subtitle) }
                                        } icon: { Image(systemName: action.symbol) }
                                    }
                                }
                            } label: {
                                Text("Zmień status")
                            }
                            .buttonStyle(.bordered)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { statusButtonFrame = $0 }
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .contain)
                    Text(invoice.status.explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Kwoty") {
                    LabeledContent("Netto", value: invoice.amountNet.money(invoice.currency))
                    LabeledContent("VAT", value: invoice.amountVAT.money(invoice.currency))
                    LabeledContent("Brutto") { Text(invoice.amountGross.money(invoice.currency)).bold() }
                    if invoice.isSplitPayment { Label("Mechanizm podzielonej płatności", systemImage: "arrow.triangle.branch") }
                }

                Section("Sprzedawca") {
                    LabeledContent("Nazwa", value: invoice.sellerName)
                    LabeledContent("NIP", value: invoice.sellerNIP)
                    if !invoice.sellerAddress.isEmpty { LabeledContent("Adres", value: invoice.sellerAddress) }
                }

                Section("Płatność") {
                    LabeledContent("Data wystawienia", value: invoice.issueDate.formatted)
                    if let due = invoice.paymentDueDate { LabeledContent("Termin płatności", value: due.formatted) }
                    if !invoice.paymentForm.isEmpty { LabeledContent("Forma płatności", value: invoice.paymentForm) }
                    if invoice.bankAccountNumber.isEmpty {
                        Label("Brak numeru rachunku — faktury nie można dodać do przelewu.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } else {
                        LabeledContent("Rachunek", value: invoice.bankAccountNumber)
                            .textSelection(.enabled)
                    }
                }

                let items = FAParser.lineItems(rawXML: invoice.rawXML)
                if !items.isEmpty {
                    Section("Pozycje") {
                        ForEach(items, id: \.self) { item in
                            VStack(alignment: .leading) {
                                Text(item.name)
                                Text("\(item.qty) \(item.unit) × \(item.unitPrice) · VAT \(item.vatRate)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else if invoice.rawXML.isEmpty {
                    Section {
                        Label("Treść faktury zostanie pobrana z KSeF przy kolejnej synchronizacji.", systemImage: "clock")
                            .foregroundStyle(.secondary)
                    }
                }

                if invoice.status != .paid {
                    ReminderSection(target: .invoice(invoice.id), makeDraft: { ReminderDrafts.invoice(invoice) },
                                    dueDate: invoice.paymentDueDate)
                }

                Section("Notatki") {
                    TextField("Dodaj notatkę", text: $notes, axis: .vertical)
                        .onSubmit(saveNotes)
                    if notes != invoice.notes { Button("Zapisz notatkę", action: saveNotes) }
                }

                if !log.isEmpty {
                    Section("Historia") {
                        ForEach(Array(log.enumerated()), id: \.offset) { _, entry in
                            VStack(alignment: .leading) {
                                Text("\(Text(entry.change.from.label)) → \(Text(entry.change.to.label))")
                                Text(entry.change.at.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                if !entry.change.note.isEmpty { Text(entry.change.note).font(.caption) }
                            }
                        }
                    }
                }

                Section {
                    LabeledContent("Numer KSeF", value: invoice.ksefReferenceNumber).font(.caption).textSelection(.enabled)
                    if !invoice.rawXML.isEmpty {
                        ShareLink(item: invoice.rawXML, preview: SharePreview("\(invoice.invoiceNumber).xml")) {
                            Label("Udostępnij XML", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle(invoice?.invoiceNumber ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            load()
            if DebugLaunch.autoApprove, invoice?.allowedTransitions.contains(.accepted) == true {
                try? await Task.sleep(for: .seconds(2))
                change(to: .accepted)
            }
        }
    }

    private func load() {
        guard let repo = model.invoices else { return }
        invoice = try? repo.find(invoiceID)
        log = (try? repo.statusLog(invoiceID)) ?? []
        notes = invoice?.notes ?? ""
    }

    private func change(to status: InvoiceStatus) {
        do {
            let flies = status == .accepted && invoice?.movesToPaymentsWhenAccepted == true
            try model.invoices?.changeStatus(invoiceID, to: status)
            if flies && !reduceMotion && statusButtonFrame != .zero {
                flight.launch(from: CGPoint(x: statusButtonFrame.midX, y: statusButtonFrame.midY))
            }
            withAnimation(.snappy) { load() }
        } catch {
            self.error = error.userMessage
        }
    }

    private func saveNotes() {
        try? model.invoices?.updateNotes(invoiceID, notes: notes)
        load()
    }
}
