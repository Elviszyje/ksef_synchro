import SwiftUI
import Domain
import Persistence

/// Formularz faktury sprzedażowej. Pozycje można wybrać z katalogu (zapamiętanego
/// z poprzednich faktur) albo wpisać nowe — po zapisie trafiają do katalogu.
struct SalesInvoiceForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: OutgoingInvoice
    @State private var saveBuyer = true
    @State private var showItemPicker = false
    @State private var showBuyerPicker = false
    @State private var editingItem: OutgoingInvoiceItem?
    @State private var showXML = false
    @State private var issues: [SalesValidationIssue] = []
    @State private var error: String?
    @State private var suggestions: [String] = []
    @State private var confirmSend = false
    @State private var sending = false
    @State private var sentInvoiceID: UUID?

    init(initial: OutgoingInvoice) { _draft = State(initialValue: initial) }

    private var editable: Bool { draft.canBeEdited }

    var body: some View {
        NavigationStack {
            Form {
                if draft.status == .rejected && !draft.errorMessage.isEmpty {
                    Section {
                        Label { Text(draft.errorMessage) } icon: { Image(systemName: "xmark.octagon.fill") }
                            .foregroundStyle(.red)
                    } header: {
                        Text("Odrzucona przez KSeF")
                    } footer: {
                        Text("Popraw fakturę i wyślij ją ponownie.")
                    }
                }
                buyerSection
                itemsSection
                if draft.hasExemptItems { exemptionSection }
                detailsSection
                summarySection
                if !issues.isEmpty || error != nil { problemsSection }
                Section {
                    Button {
                        prepareSend()
                    } label: {
                        HStack {
                            Label("Wyślij do KSeF", systemImage: "paperplane.fill")
                            Spacer()
                            if sending { ProgressView() }
                        }
                    }
                    .disabled(sending || model.ksefToken == nil)
                } footer: {
                    if model.ksefToken == nil {
                        Text("Aby wysłać fakturę, zapisz token KSeF w Ustawieniach (z uprawnieniem do wystawiania faktur).")
                    } else if model.company?.ksefEnvironment == .test {
                        Text("Środowisko testowe KSeF — faktury nie mają skutków prawnych.")
                    }
                }
            }
            .disabled(!editable)
            .navigationTitle(draft.invoiceNumber.isEmpty ? String(localized: "Nowa faktura") : draft.invoiceNumber)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz", action: save).disabled(!editable)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button { showXML = true } label: { Label("Podgląd XML FA(3)", systemImage: "chevron.left.forwardslash.chevron.right") }
                }
            }
            .sheet(isPresented: $showItemPicker) {
                CatalogPickerSheet { item, isNew in
                    draft.items.append(item)
                    // Nowa pozycja od razu w edytorze, żeby wpisać cenę i stawkę.
                    if isNew { editingItem = item }
                }
            }
            .sheet(isPresented: $showBuyerPicker) {
                BuyerPickerSheet { buyer in
                    draft.buyerID = buyer.id
                    draft.buyerNIP = buyer.nip
                    draft.buyerName = buyer.name
                    draft.buyerAddress = buyer.address
                }
            }
            .sheet(item: $editingItem) { item in
                ItemEditor(item: item) { updated in
                    if let index = draft.items.firstIndex(where: { $0.id == updated.id }) { draft.items[index] = updated }
                }
            }
            .sheet(isPresented: $showXML) { XMLPreview(invoice: draft) }
            .confirmationDialog(sendTitle, isPresented: $confirmSend, titleVisibility: .visible) {
                Button("Wyślij do KSeF") { Task { await send() } }
            } message: {
                Text(sendMessage)
            }
            .sheet(item: Binding(get: { sentInvoiceID.map(IdentifiedID.init) }, set: { sentInvoiceID = $0?.id })) { sent in
                SalesInvoiceDetail(invoiceID: sent.id, onClose: { dismiss() })
            }
            .task { suggestions = (try? model.sales?.exemptionSuggestions()) ?? VATExemptionSuggestions.common }
        }
    }

    // MARK: Sekcje

    private var buyerSection: some View {
        Section {
            Button { showBuyerPicker = true } label: {
                Label("Wybierz zapisanego nabywcę", systemImage: "person.crop.circle")
            }
            LabeledContent("NIP") {
                TextField("NIP nabywcy", text: $draft.buyerNIP).keyboardType(.numberPad).multilineTextAlignment(.trailing)
            }
            LabeledContent("Nazwa") {
                TextField("Nazwa nabywcy", text: $draft.buyerName, axis: .vertical).multilineTextAlignment(.trailing)
            }
            LabeledContent("Adres") {
                TextField("Adres nabywcy", text: $draft.buyerAddress, axis: .vertical).multilineTextAlignment(.trailing)
            }
            Toggle("Zapamiętaj nabywcę", isOn: $saveBuyer)
        } header: {
            Text("Nabywca")
        }
    }

    private var itemsSection: some View {
        Section {
            ForEach(draft.items) { item in
                Button { editingItem = item } label: { ItemRow(item: item, currency: draft.currency) }
                    .tint(.primary)
            }
            .onDelete { draft.items.remove(atOffsets: $0) }
            .onMove { draft.items.move(fromOffsets: $0, toOffset: $1) }
            Button { showItemPicker = true } label: { Label("Dodaj pozycję", systemImage: "plus.circle.fill") }
        } header: {
            Text("Pozycje")
        } footer: {
            Text("Wybierz pozycję z katalogu albo dodaj nową. Nowe pozycje trafiają do katalogu po zapisaniu faktury.")
        }
    }

    private var exemptionSection: some View {
        Section {
            Picker("Rodzaj podstawy", selection: $draft.exemptionType) {
                ForEach(VATExemptionType.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            LabeledContent("Podstawa") {
                TextField("np. art. 113 ust. 1 ustawy o VAT", text: $draft.exemptionBasis, axis: .vertical)
                    .multilineTextAlignment(.trailing)
            }
            Menu {
                ForEach(suggestions, id: \.self) { basis in
                    Button(basis) { draft.exemptionBasis = basis }
                }
            } label: {
                Label("Wybierz z podpowiedzi", systemImage: "text.badge.checkmark")
            }
        } header: {
            Text("Zwolnienie z VAT")
        } footer: {
            Text("Faktura zawiera pozycje ze stawką ZW. KSeF wymaga wskazania podstawy prawnej zwolnienia: przepisu ustawy o VAT (lub aktu wykonawczego), dyrektywy 2006/112/WE albo innej podstawy. Wcześniej użyte podstawy są zapamiętywane.")
        }
    }

    private var detailsSection: some View {
        Section("Dane faktury") {
            TextField("Numer faktury", text: $draft.invoiceNumber)
            DatePicker("Data wystawienia", selection: dateBinding(\.issueDate), displayedComponents: .date)
            Toggle("Data dostawy inna niż wystawienia", isOn: Binding(
                get: { draft.deliveryDate != nil },
                set: { draft.deliveryDate = $0 ? draft.issueDate : nil }))
            if draft.deliveryDate != nil {
                DatePicker("Data dostawy", selection: Binding(
                    get: { draft.deliveryDate?.date() ?? Date() },
                    set: { draft.deliveryDate = LocalDate($0) }), displayedComponents: .date)
            }
            DatePicker("Termin płatności", selection: dateBinding(\.paymentDueDate), displayedComponents: .date)
            Picker("Forma płatności", selection: $draft.paymentForm) {
                Text("Przelew").tag(PaymentForm.transfer)
                Text("Gotówka").tag(PaymentForm.cash)
            }
            if draft.paymentForm == .transfer {
                Picker("Rachunek", selection: $draft.bankAccountNumber) {
                    if model.bankAccounts.isEmpty { Text("Dodaj rachunek w Ustawieniach").tag("") }
                    ForEach(model.bankAccounts) { account in
                        Text(account.accountNumber.groupedNRB).font(.caption.monospaced()).tag(account.accountNumber)
                    }
                }
            }
            TextField("Uwagi", text: $draft.notes, axis: .vertical)
        }
    }

    private var summarySection: some View {
        Section("Podsumowanie") {
            LabeledContent("Netto", value: draft.amountNet.money(draft.currency))
            LabeledContent("VAT", value: draft.amountVAT.money(draft.currency))
            LabeledContent("Brutto") { Text(draft.amountGross.money(draft.currency)).bold() }
        }
    }

    private var problemsSection: some View {
        Section {
            ForEach(issues, id: \.self) { issue in
                Label { Text(issue.message) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                    .foregroundStyle(.red)
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
    }

    // MARK: Akcje

    private func dateBinding(_ keyPath: WritableKeyPath<OutgoingInvoice, LocalDate>) -> Binding<Date> {
        Binding(get: { draft[keyPath: keyPath].date() }, set: { draft[keyPath: keyPath] = LocalDate($0) })
    }

    private func save() {
        if persist() { dismiss() }
    }

    /// Zapis szkicu; zwraca false i pokazuje problemy, gdy dane są niekompletne.
    private func persist() -> Bool {
        issues = draft.validationIssues
        guard issues.isEmpty, let sales = model.sales else { return false }
        do {
            draft = try sales.saveDraft(draft, saveBuyer: saveBuyer)
            error = nil
            return true
        } catch {
            self.error = error.userMessage
            return false
        }
    }

    private var isProduction: Bool { model.company?.ksefEnvironment == .production }

    private var sendTitle: LocalizedStringKey {
        isProduction ? "Wystawić fakturę w KSeF?" : "Wysłać do testowego KSeF?"
    }

    private var sendMessage: LocalizedStringKey {
        isProduction
            ? "Faktura \(draft.invoiceNumber) na \(draft.amountGross.money(draft.currency)) zostanie wysłana do produkcyjnego KSeF. Po przyjęciu jest wystawiona i nie można jej usunąć — błędy poprawia się fakturą korygującą."
            : "Faktura zostanie wysłana do środowiska testowego KSeF. Nie ma skutków prawnych."
    }

    private func prepareSend() {
        if persist() { confirmSend = true }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        do {
            let result = try await model.sendService().send(draft.id)
            sentInvoiceID = result.id
        } catch {
            self.error = error.userMessage
            draft = (try? model.sales?.find(draft.id)) ?? draft
        }
    }
}

struct ItemRow: View {
    let item: OutgoingInvoiceItem
    let currency: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name.isEmpty ? String(localized: "Nowa pozycja") : item.name)
                Text("\(item.quantity.formatted()) \(item.unit) × \(item.unitPriceNet.money(currency)) · \(item.vatRate.shortLabel)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.amountGross.money(currency)).font(.subheadline.monospacedDigit())
        }
    }
}

/// Edycja pojedynczej pozycji.
struct ItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: OutgoingInvoiceItem
    let onSave: (OutgoingInvoiceItem) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nazwa towaru lub usługi", text: $item.name, axis: .vertical)
                    TextField("Jednostka", text: $item.unit)
                    TextField("Ilość", value: $item.quantity, format: .number).keyboardType(.decimalPad)
                    TextField("Cena jednostkowa netto", value: $item.unitPriceNet, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad)
                    Picker("Stawka VAT", selection: $item.vatRate) {
                        ForEach(VATRate.allCases, id: \.self) { Text($0.shortLabel).tag($0) }
                    }
                }
                Section {
                    LabeledContent("Netto", value: item.amountNet.money())
                    LabeledContent("VAT", value: item.amountVAT.money())
                    LabeledContent("Brutto", value: item.amountGross.money())
                }
            }
            .navigationTitle("Pozycja")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotowe") { onSave(item); dismiss() }
                        .disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// Wybór pozycji z katalogu albo dodanie nowej.
struct CatalogPickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var entries: [CatalogItem] = []
    let onPick: (OutgoingInvoiceItem, _ isNew: Bool) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onPick(OutgoingInvoiceItem(name: query.trimmingCharacters(in: .whitespaces)), true)
                        dismiss()
                    } label: {
                        Label(query.isEmpty ? String(localized: "Nowa pozycja") : String(localized: "Nowa pozycja „\(query)”"),
                              systemImage: "plus")
                    }
                }
                if !entries.isEmpty {
                    Section("Z katalogu") {
                        ForEach(entries) { entry in
                            Button {
                                onPick(entry.makeItem(), false)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name)
                                    Text("\(entry.unit) · \(entry.unitPriceNet.money()) netto · \(entry.vatRate.shortLabel)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .tint(.primary)
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Szukaj w katalogu"))
            .navigationTitle("Dodaj pozycję")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } } }
            .task(id: query) { entries = (try? model.catalog?.items(matching: query)) ?? [] }
        }
    }
}

struct BuyerPickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var buyers: [Buyer] = []
    let onPick: (Buyer) -> Void

    var body: some View {
        NavigationStack {
            List(buyers) { buyer in
                Button {
                    onPick(buyer)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(buyer.name)
                        Text("NIP \(buyer.nip)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(.primary)
            }
            .overlay {
                if buyers.isEmpty {
                    ContentUnavailableView("Brak zapisanych nabywców", systemImage: "person.2",
                                           description: Text("Nabywcy są zapamiętywani przy zapisie faktury."))
                }
            }
            .searchable(text: $query, prompt: Text("Nazwa lub NIP"))
            .navigationTitle("Nabywcy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } } }
            .task(id: query) { buyers = (try? model.sales?.buyers(matching: query)) ?? [] }
        }
    }
}

struct XMLPreview: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let invoice: OutgoingInvoice

    var body: some View {
        NavigationStack {
            Group {
                switch result {
                case .success(let xml):
                    ScrollView {
                        Text(xml).font(.caption.monospaced()).textSelection(.enabled).padding()
                    }
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            ShareLink(item: xml, preview: SharePreview("\(invoice.invoiceNumber).xml"))
                        }
                    }
                case .failure(let error):
                    ContentUnavailableView("Nie można wygenerować XML", systemImage: "exclamationmark.triangle",
                                           description: Text(error.userMessage))
                }
            }
            .navigationTitle("XML FA(3)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Zamknij") { dismiss() } } }
        }
    }

    private var result: Result<String, Error> {
        Result {
            guard let seller = model.fa3Seller else { throw FA3GeneratorError.noItems }
            return try FA3Generator.generate(invoice, seller: seller)
        }
    }
}

extension VATExemptionType {
    var label: LocalizedStringResource {
        switch self {
        case .act: "Ustawa o VAT"
        case .directive: "Dyrektywa UE"
        case .other: "Inna podstawa"
        }
    }
}

extension SalesValidationIssue {
    var message: LocalizedStringResource {
        switch self {
        case .missingNumber: "Podaj numer faktury."
        case .invalidBuyerNIP: "Nieprawidłowy NIP nabywcy."
        case .missingBuyerName: "Podaj nazwę nabywcy."
        case .noItems: "Dodaj co najmniej jedną pozycję."
        case .itemWithoutName: "Każda pozycja musi mieć nazwę."
        case .missingBankAccount: "Wybierz rachunek do przelewu albo dodaj go w Ustawieniach."
        case .missingExemptionBasis: "Pozycje ze stawką ZW wymagają podania podstawy prawnej zwolnienia z VAT."
        }
    }
}
