import SwiftUI
import GRDB
import Domain
import Persistence

/// Katalog zapamiętanych pozycji: przegląd, poprawki ceny/stawki, usuwanie.
struct CatalogView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var entries: [CatalogItem] = []
    @State private var editing: CatalogItem?

    var body: some View {
        List {
            ForEach(entries) { entry in
                Button { editing = entry } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                            Text("\(entry.unit) · \(entry.unitPriceNet.money()) netto · \(entry.vatRate.shortLabel)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(entry.useCount)×").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .tint(.primary)
            }
            .onDelete { offsets in offsets.map { entries[$0].id }.forEach { try? model.catalog?.delete($0) } }
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView("Katalog jest pusty", systemImage: "shippingbox",
                                       description: Text("Pozycje trafiają tu automatycznie po zapisaniu faktury sprzedażowej."))
            }
        }
        .searchable(text: $query, prompt: Text("Szukaj w katalogu"))
        .navigationTitle("Katalog pozycji")
        .sheet(item: $editing) { entry in
            CatalogEntryEditor(entry: entry) { try? model.catalog?.update($0) }
        }
        .task(id: query) { await observe() }
    }

    private func observe() async {
        guard let catalog = model.catalog else { return }
        do {
            for try await value in catalog.observe(query).values(in: model.database.reader) { entries = value }
        } catch {}
    }
}

struct CatalogEntryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var entry: CatalogItem
    let onSave: (CatalogItem) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nazwa towaru lub usługi", text: $entry.name, axis: .vertical)
                    TextField("Jednostka", text: $entry.unit)
                    TextField("Cena jednostkowa netto", value: $entry.unitPriceNet, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad)
                    Picker("Stawka VAT", selection: $entry.vatRate) {
                        ForEach(VATRate.allCases, id: \.self) { Text($0.shortLabel).tag($0) }
                    }
                } footer: {
                    Text("Zmiany dotyczą tylko przyszłych faktur.")
                }
            }
            .navigationTitle("Pozycja katalogu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") { onSave(entry); dismiss() }
                        .disabled(entry.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
