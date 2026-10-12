import SwiftUI
import Domain
import Persistence

struct IdentifiedID: Identifiable { let id: UUID }

/// Faktura wysłana do KSeF: status, numer KSeF, XML i UPO.
struct SalesInvoiceDetail: View {
    let invoiceID: UUID
    var onClose: (() -> Void)?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var invoice: OutgoingInvoice?
    @State private var refreshing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let invoice {
                    Section {
                        LabeledContent("Status") {
                            Text(invoice.status.label).foregroundStyle(invoice.status.color).bold()
                        }
                        if !invoice.ksefNumber.isEmpty {
                            LabeledContent("Numer KSeF") {
                                Text(invoice.ksefNumber).font(.caption.monospaced()).textSelection(.enabled)
                            }
                        }
                        if invoice.environment == .test {
                            Label("Środowisko testowe", systemImage: "testtube.2").foregroundStyle(.orange)
                        }
                        if invoice.status == .sending {
                            Text("KSeF przetwarza fakturę. Zwykle trwa to kilka sekund, czasem dłużej.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        if !invoice.errorMessage.isEmpty {
                            Text(invoice.errorMessage).foregroundStyle(.red)
                        }
                        if invoice.status == .sending || (invoice.status == .accepted && invoice.upoXML.isEmpty) {
                            Button {
                                Task { await refresh() }
                            } label: {
                                HStack {
                                    Label("Odśwież status", systemImage: "arrow.clockwise")
                                    Spacer()
                                    if refreshing { ProgressView() }
                                }
                            }
                            .disabled(refreshing)
                        }
                    }

                    Section("Faktura") {
                        LabeledContent("Numer", value: invoice.invoiceNumber)
                        LabeledContent("Nabywca", value: invoice.buyerName)
                        LabeledContent("NIP", value: invoice.buyerNIP)
                        LabeledContent("Data wystawienia", value: invoice.issueDate.formatted)
                        LabeledContent("Brutto") { Text(invoice.amountGross.money(invoice.currency)).bold() }
                    }

                    Section("Pozycje") {
                        ForEach(invoice.items) { ItemRow(item: $0, currency: invoice.currency) }
                    }

                    Section("Dokumenty") {
                        if !invoice.generatedXML.isEmpty {
                            ShareLink(item: invoice.generatedXML, preview: SharePreview("\(invoice.invoiceNumber).xml")) {
                                Label("XML FA(3)", systemImage: "doc.text")
                            }
                        }
                        if invoice.upoXML.isEmpty {
                            Label("UPO pojawi się po przetworzeniu faktury przez KSeF.", systemImage: "clock")
                                .foregroundStyle(.secondary)
                        } else {
                            ShareLink(item: invoice.upoXML, preview: SharePreview("UPO \(invoice.invoiceNumber).xml")) {
                                Label("UPO (urzędowe potwierdzenie odbioru)", systemImage: "checkmark.seal")
                            }
                        }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle(invoice?.invoiceNumber ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotowe") {
                        dismiss()
                        onClose?()
                    }
                }
            }
            .task { invoice = try? model.sales?.find(invoiceID) }
        }
    }

    private func refresh() async {
        refreshing = true
        defer { refreshing = false }
        do {
            invoice = try await model.sendService().refresh(invoiceID)
            error = nil
        } catch {
            self.error = error.userMessage
        }
    }
}

extension OutgoingInvoiceStatus {
    var color: Color {
        switch self {
        case .draft: .secondary
        case .queued, .sending: .orange
        case .accepted: .green
        case .rejected: .red
        }
    }
}
