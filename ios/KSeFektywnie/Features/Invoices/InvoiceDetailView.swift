import SwiftUI
import Domain
import Persistence

struct InvoiceDetailView: View {
    let invoiceID: UUID
    @Environment(AppModel.self) private var model
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Status").font(.caption).foregroundStyle(.secondary)
                            Text(invoice.status.label).font(.headline).foregroundStyle(invoice.status.color)
                        }
                        Spacer(minLength: 8)
                        if !invoice.allowedTransitions.isEmpty {
                            Menu {
                                ForEach(invoice.allowedTransitions, id: \.self) { status in
                                    Button { change(to: status) } label: { Text(status.label) }
                                }
                            } label: {
                                Text("Zmień status")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .contain)
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
        .task { load() }
    }

    private func load() {
        guard let repo = model.invoices else { return }
        invoice = try? repo.find(invoiceID)
        log = (try? repo.statusLog(invoiceID)) ?? []
        notes = invoice?.notes ?? ""
    }

    private func change(to status: InvoiceStatus) {
        do {
            try model.invoices?.changeStatus(invoiceID, to: status)
            load()
        } catch {
            self.error = error.userMessage
        }
    }

    private func saveNotes() {
        try? model.invoices?.updateNotes(invoiceID, notes: notes)
        load()
    }
}
