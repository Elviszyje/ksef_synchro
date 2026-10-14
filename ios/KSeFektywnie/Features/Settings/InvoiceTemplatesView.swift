import PDFKit
import PhotosUI
import SwiftUI
import Domain

/// Lista szablonów wizualizacji faktur sprzedażowych.
struct InvoiceTemplatesView: View {
    @Environment(AppModel.self) private var model
    @State private var templates: [InvoiceTemplate] = []
    @State private var creating: InvoiceTemplate?

    var body: some View {
        List {
            Section {
                ForEach(templates) { template in
                    NavigationLink { InvoiceTemplateEditor(template: template) } label: { TemplateRow(template: template) }
                        .deleteDisabled(template.isBuiltIn)
                }
                .onDelete { offsets in
                    for index in offsets where !templates[index].isBuiltIn { try? model.invoiceTemplates?.delete(templates[index].id) }
                }
            } footer: {
                Text("Szablon określa wygląd PDF faktur sprzedażowych: układ, kolor, logo, język etykiet i stopkę. Domyślny szablon jest wybrany w podglądzie faktury, a inny można wskazać w menu podglądu.")
            }
        }
        .navigationTitle("Szablony faktur")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    guard let company = model.company else { return }
                    creating = InvoiceTemplate(companyID: company.id, name: String(localized: "Nowy szablon"))
                } label: {
                    Label("Nowy szablon", systemImage: "plus")
                }
            }
        }
        .navigationDestination(item: $creating) { InvoiceTemplateEditor(template: $0) }
        .task { await observe() }
    }

    private func observe() async {
        guard let repo = model.invoiceTemplates else { return }
        do {
            for try await value in repo.observe().values(in: model.database.reader) { templates = value }
        } catch {}
    }
}

private struct TemplateRow: View {
    let template: InvoiceTemplate

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(template.color)
                .frame(width: 28, height: 36)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.85)).frame(height: 5).padding(4)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(template.displayName)
                Text("\(Text(template.layout.label)) · \(Text(template.language.label))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if template.isDefault {
                Text("Domyślny").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
        }
    }
}

/// Edycja szablonu z podglądem pierwszej strony na fakturze przykładowej.
struct InvoiceTemplateEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var template: InvoiceTemplate
    private let original: InvoiceTemplate
    @State private var photo: PhotosPickerItem?
    @State private var thumbnail: UIImage?
    @State private var sample: PreparedInvoiceDocument?
    @State private var confirmDelete = false
    @State private var error: String?

    init(template: InvoiceTemplate) {
        _template = State(initialValue: template)
        original = template
    }

    private var isSaved: Bool { !original.isBuiltIn && model.salesTemplates.contains { $0.id == original.id && !$0.isBuiltIn } }

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    InvoicePDFPreview(source: sample.map { .success($0) } ?? .failure(InvoiceVisualizationError.unreadableXML),
                                      templates: [template])
                } label: {
                    HStack {
                        Spacer()
                        Group {
                            if let thumbnail {
                                Image(uiImage: thumbnail).resizable().scaledToFit()
                            } else {
                                ProgressView()
                            }
                        }
                        .frame(height: 300)
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        Spacer()
                    }
                }
                .accessibilityLabel(Text("Podgląd szablonu"))
                .accessibilityIdentifier("template-preview")
            } footer: {
                Text("Podgląd na ostatniej fakturze sprzedażowej albo na przykładowych danych.")
            }

            Section("Nazwa") {
                TextField("Nazwa szablonu", text: $template.name)
                Toggle("Szablon domyślny", isOn: $template.isDefault)
            }

            Section("Wygląd") {
                Picker("Układ", selection: $template.layout) {
                    ForEach(InvoiceLayout.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
                HStack(spacing: 10) {
                    ForEach(InvoiceTemplate.accentPresets, id: \.self) { hex in
                        Button {
                            template.accentColor = hex
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 30, height: 30)
                                .overlay { if template.accentColor == hex { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Kolor \(hex)"))
                    }
                    Spacer(minLength: 0)
                    ColorPicker("Własny kolor", selection: Binding(
                        get: { template.color },
                        set: { template.accentColor = $0.hex }), supportsOpacity: false)
                        .labelsHidden()
                }
            }

            Section {
                if let data = template.logoPNG, let image = UIImage(data: data) {
                    HStack {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 60)
                        Spacer()
                        Button("Usuń", role: .destructive) { template.logoPNG = nil; photo = nil }
                    }
                }
                PhotosPicker(selection: $photo, matching: .images) {
                    Label(template.logoPNG == nil ? "Dodaj logo" : "Zmień logo", systemImage: "photo")
                }
            } header: {
                Text("Logo")
            } footer: {
                Text("Najlepiej sprawdza się logo na przezroczystym albo białym tle.")
            }

            Section("Treść") {
                Picker("Język etykiet", selection: $template.language) {
                    ForEach(InvoiceLanguage.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("Kod QR KSeF", isOn: $template.showQRCode)
                Toggle("Kwota słownie", isOn: $template.showAmountInWords)
                Toggle("Miejsca na podpisy", isOn: $template.showSignatureFields)
            }

            Section {
                TextField("Dopisek pod sumą, np. „Dziękujemy za współpracę”", text: $template.closingNote, axis: .vertical)
                TextField("Stopka, np. KRS, kapitał zakładowy, telefon, e-mail", text: $template.footerText, axis: .vertical)
                    .lineLimit(2...5)
            } header: {
                Text("Dodatkowe teksty")
            } footer: {
                Text("Kod QR pojawia się tylko na fakturach przyjętych przez KSeF. Pozwala nabywcy sprawdzić fakturę w KSeF.")
            }

            if let error { Section { Text(error).foregroundStyle(.red) } }

            if isSaved {
                Section {
                    Button("Usuń szablon", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle(template.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Zapisz", action: save)
                    .disabled(template.name.trimmingCharacters(in: .whitespaces).isEmpty || (template == original && isSaved))
            }
        }
        .confirmationDialog("Usunąć szablon?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Usuń", role: .destructive) {
                try? model.invoiceTemplates?.delete(template.id)
                dismiss()
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await loadLogo(item) }
        }
        .task { sample = model.templateSample() }
        .task(id: template) {
            // Krótkie opóźnienie: podgląd nie przelicza się przy każdym znaku w polach tekstowych.
            try? await Task.sleep(for: .milliseconds(thumbnail == nil ? 0 : 250))
            guard !Task.isCancelled else { return }
            if sample == nil { sample = model.templateSample() }
            guard let sample else { return }
            let renderer = InvoiceVisualizationPDF(prepared: sample, template: template)
            let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                PDFDocument(data: renderer.render())?.page(at: 0)?.thumbnail(of: CGSize(width: 424, height: 600), for: .mediaBox)
            }.value
            if !Task.isCancelled { thumbnail = image }
        }
    }

    private func save() {
        var toSave = template
        // Wbudowany szablon zapisujemy jako nowy rekord z własnym identyfikatorem.
        if toSave.isBuiltIn { toSave.id = UUID() }
        do {
            try model.invoiceTemplates?.save(toSave)
            dismiss()
        } catch {
            self.error = error.userMessage
        }
    }

    private func loadLogo(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            error = String(localized: "Nie udało się wczytać obrazu.")
            return
        }
        template.logoPNG = Self.logoPNG(image)
        error = nil
    }

    /// Logo zmniejszone do 800 px po dłuższym boku (PNG z przezroczystością).
    static func logoPNG(_ image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 800 / max(longest, 1))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).pngData { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

extension InvoiceLayout {
    var label: LocalizedStringResource {
        switch self {
        case .classic: "Klasyczny"
        case .modern: "Nowoczesny"
        case .minimal: "Minimalistyczny"
        }
    }
}

extension InvoiceLanguage {
    var label: LocalizedStringResource {
        switch self {
        case .pl: "Polski"
        case .en: "Angielski"
        case .plEn: "Polski i angielski"
        }
    }
}

extension InvoiceTemplate {
    var color: Color { Color(hex: accentColor) }
}

extension Color {
    init(hex: String) {
        let c = InvoiceTemplate.rgb(hex) ?? InvoiceTemplate.rgb(InvoiceTemplate.accentPresets[0])!
        self.init(red: c.red, green: c.green, blue: c.blue)
    }

    var hex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return InvoiceTemplate.hex(red: r, green: g, blue: b)
    }
}
