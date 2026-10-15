import SwiftUI
import Domain

/// Wizualny edytor układu strony: miniatura prawdziwej faktury, na której przeciąga się sekcje
/// (przytrzymaj i przesuń w górę lub w dół) oraz logo i kod QR (w lewo lub w prawo).
struct InvoiceLayoutEditor: View {
    @Binding var template: InvoiceTemplate
    let sample: PreparedInvoiceDocument?

    @State private var snapshot: InvoiceLayoutSnapshot?
    @State private var frames: [InvoiceSection: CGRect] = [:]
    @State private var dragging: InvoiceSection?
    @State private var dragStartMinY: CGFloat = 0
    @State private var dragTranslation: CGFloat = 0
    @State private var reorders = 0
    @State private var lifts = 0

    private static let page = "layout-page"

    /// Wygląd bez kolejności sekcji: zmiana kolejności nie wymaga ponownego renderowania fragmentów.
    private var renderKey: InvoiceTemplate {
        var key = template
        key.sectionOrder = InvoiceSection.defaultOrder
        return key
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Przytrzymaj sekcję i przeciągnij ją w górę lub w dół. Logo i kod QR przeciągnij w lewo albo w prawo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                if let snapshot {
                    PageCanvas(snapshot: snapshot, content: page)
                } else if sample == nil {
                    ContentUnavailableView("Nie można przygotować podglądu", systemImage: "exclamationmark.triangle")
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .padding()
        }
        .scrollDisabled(dragging != nil)
        .background(Color(.secondarySystemBackground))
        .safeAreaBar(edge: .bottom) { appearanceBar }
        .navigationTitle("Układ strony")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if template.hasCustomArrangement {
                ToolbarItem(placement: .primaryAction) {
                    Button("Przywróć") { withAnimation(.snappy) { template.resetArrangement() } }
                        .accessibilityIdentifier("layout-reset")
                }
            }
        }
        .sensoryFeedback(.selection, trigger: reorders)
        .sensoryFeedback(.impact(weight: .medium), trigger: lifts)
        .task(id: renderKey) {
            guard let sample else { return }
            // Krótkie opóźnienie: przy przesuwaniu suwaka koloru nie renderujemy każdej klatki.
            if snapshot != nil { try? await Task.sleep(for: .milliseconds(120)) }
            guard !Task.isCancelled else { return }
            let renderer = InvoiceVisualizationPDF(prepared: sample, template: renderKey)
            let result = await Task.detached(priority: .userInitiated) { renderer.layoutSnapshot() }.value
            if !Task.isCancelled { snapshot = result }
        }
    }

    // MARK: - Strona

    private func page(_ snapshot: InvoiceLayoutSnapshot, scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            HeaderPiece(snapshot: snapshot, scale: scale, side: template.resolvedLogoSide) { side in
                withAnimation(.snappy) { template.logoSide = side }
                reorders += 1
            }
            ForEach(template.sectionOrder, id: \.self) { section in
                if let piece = snapshot.pieces.first(where: { $0.section == section }) {
                    sectionView(piece, scale: scale)
                }
            }
        }
        .coordinateSpace(.named(Self.page))
    }

    private func sectionView(_ piece: InvoiceLayoutSnapshot.Piece, scale: CGFloat) -> some View {
        let isDragging = dragging == piece.section
        return SectionPiece(piece: piece, scale: scale, isDragging: isDragging, template: $template) { side in
            withAnimation(.snappy) { template.qrSide = side }
            reorders += 1
        }
        .padding(.top, piece.spacing * scale)
        .offset(y: isDragging ? dragStartMinY + dragTranslation - (frames[piece.section]?.minY ?? dragStartMinY) : 0)
        .zIndex(isDragging ? 1 : 0)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.page)) } action: { frames[piece.section] = $0 }
        .gesture(reorderGesture(piece.section))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(piece.section.label))
        .accessibilityAction(named: Text("Przenieś wyżej")) { move(piece.section, by: -1) }
        .accessibilityAction(named: Text("Przenieś niżej")) { move(piece.section, by: 1) }
        .accessibilityIdentifier("layout-section-\(piece.section.rawValue)")
    }

    private func move(_ section: InvoiceSection, by offset: Int) {
        withAnimation(.snappy) { template.move(section, by: offset) }
        reorders += 1
    }

    // MARK: - Przeciąganie sekcji

    private func reorderGesture(_ section: InvoiceSection) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.page)))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if dragging != section {
                    withAnimation(.snappy) {
                        dragging = section
                        dragStartMinY = frames[section]?.minY ?? 0
                        dragTranslation = 0
                    }
                    lifts += 1
                }
                dragTranslation = drag?.translation.height ?? 0
                reorderIfNeeded(section)
            }
            .onEnded { _ in
                withAnimation(.snappy) {
                    dragging = nil
                    dragTranslation = 0
                }
            }
    }

    /// Gdy środek przeciąganej sekcji minie środek sąsiada, sekcje zamieniają się miejscami.
    private func reorderIfNeeded(_ section: InvoiceSection) {
        guard let frame = frames[section], let index = template.sectionOrder.firstIndex(of: section) else { return }
        let center = dragStartMinY + dragTranslation + frame.height / 2
        let order = template.sectionOrder
        if index + 1 < order.count, let next = frames[order[index + 1]], center > next.midY {
            withAnimation(.snappy) { template.move(section, to: order[index + 1]) }
            reorders += 1
        } else if index > 0, let previous = frames[order[index - 1]], center < previous.midY {
            withAnimation(.snappy) { template.move(section, to: order[index - 1]) }
            reorders += 1
        }
    }

    // MARK: - Wygląd

    private var appearanceBar: some View {
        VStack(spacing: 10) {
            Picker("Układ", selection: $template.layout) {
                ForEach(InvoiceLayout.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack(spacing: 10) {
                ForEach(InvoiceTemplate.accentPresets, id: \.self) { hex in
                    Button { template.accentColor = hex } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 28, height: 28)
                            .overlay {
                                if template.accentColor == hex {
                                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Kolor \(hex)"))
                }
                Spacer(minLength: 0)
                ColorPicker("Własny kolor", selection: Binding(get: { template.color }, set: { template.accentColor = $0.hex }),
                            supportsOpacity: false)
                    .labelsHidden()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .glassEffect(in: .rect(cornerRadius: 22))
        .padding(.horizontal)
        .padding(.bottom, 6)
    }
}

/// Biała kartka A4 w skali szerokości ekranu ze stopką na dole.
private struct PageCanvas<Content: View>: View {
    let snapshot: InvoiceLayoutSnapshot
    let content: (InvoiceLayoutSnapshot, CGFloat) -> Content
    @State private var width: CGFloat = 0

    var body: some View {
        let scale = width / InvoiceLayoutSnapshot.pageSize.width
        VStack(spacing: 0) {
            content(snapshot, scale)
            Spacer(minLength: 16 * scale)
            Image(uiImage: snapshot.footer)
                .resizable()
                .frame(height: snapshot.footerHeight * scale)
                .accessibilityHidden(true)
        }
        .frame(minHeight: InvoiceLayoutSnapshot.pageSize.height * scale, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(.white, in: .rect(cornerRadius: 4))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .environment(\.colorScheme, .light)
    }
}

/// Nagłówek strony (stały, na górze) z logo do przeciągnięcia w lewo lub w prawo.
private struct HeaderPiece: View {
    let snapshot: InvoiceLayoutSnapshot
    let scale: CGFloat
    let side: InvoiceSide
    let onSide: (InvoiceSide) -> Void

    var body: some View {
        Image(uiImage: snapshot.header)
            .resizable()
            .frame(height: snapshot.headerHeight * scale)
            .accessibilityLabel(Text("Nagłówek"))
            .overlay(alignment: .topLeading) {
                if let frame = snapshot.logoFrame, let logo = snapshot.logo {
                    SideHandle(frame: frame, scale: scale, side: side, label: "Logo", onSide: onSide) {
                        Image(uiImage: logo)
                            .resizable()
                            .scaledToFit()
                            .padding(6 * scale)
                            .background(.white, in: .rect(cornerRadius: 8 * scale))
                    }
                    .accessibilityIdentifier("layout-logo")
                }
            }
    }
}

/// Fragment strony z jedną sekcją. Pusta sekcja to przerywana ramka z opisem.
private struct SectionPiece: View {
    let piece: InvoiceLayoutSnapshot.Piece
    let scale: CGFloat
    let isDragging: Bool
    @Binding var template: InvoiceTemplate
    let onQRSide: (InvoiceSide) -> Void

    var body: some View {
        Group {
            if let image = piece.image {
                Image(uiImage: image)
                    .resizable()
                    .frame(height: piece.height * scale)
                    .overlay(alignment: .topLeading) {
                        if let frame = piece.qrFrame, let ghost = image.crop(frame) {
                            SideHandle(frame: frame, scale: scale, side: template.qrSide, label: "Kod QR", onSide: onQRSide) {
                                Image(uiImage: ghost).resizable()
                            }
                            .accessibilityIdentifier("layout-qr")
                        }
                    }
            } else {
                placeholder
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(isDragging ? template.color : Color.secondary.opacity(0.25),
                              style: StrokeStyle(lineWidth: isDragging ? 2 : 0.75, dash: isDragging ? [] : [4, 3]))
                .padding(.horizontal, 20 * scale)
                .padding(.vertical, -3)
        }
        // Uchwyt na marginesie strony; nazwa sekcji tylko w trakcie przeciągania (nie zasłania treści).
        .overlay(alignment: isDragging ? .topLeading : .leading) {
            Group {
                if isDragging {
                    Label { Text(piece.section.label) } icon: { Image(systemName: "line.3.horizontal") }
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(template.color, in: .capsule)
                        .offset(x: 14 * scale, y: -12)
                } else {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 7, weight: .bold))
                        .frame(width: 15, height: 15)
                        .background(Color(white: 0.6), in: .circle)
                        .offset(x: 3)
                }
            }
            .foregroundStyle(.white)
            .accessibilityHidden(true)
        }
        .background(.white)
        .scaleEffect(isDragging ? 1.03 : 1)
        .shadow(color: .black.opacity(isDragging ? 0.2 : 0), radius: 10, y: 4)
        .contentShape(.rect)
    }

    @ViewBuilder private var placeholder: some View {
        HStack {
            Text(piece.section.emptyHint).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            if piece.section == .signatures {
                Button("Pokaż") { template.showSignatureFields = true }.font(.caption2.bold())
            }
        }
        .padding(.horizontal, 40 * scale)
        .frame(height: 30)
    }
}

/// Element przeciągany w poziomie (logo, kod QR): po puszczeniu trafia na bliższą stronę strony.
private struct SideHandle<Ghost: View>: View {
    let frame: CGRect
    let scale: CGFloat
    let side: InvoiceSide
    let label: LocalizedStringResource
    let onSide: (InvoiceSide) -> Void
    @ViewBuilder let ghost: Ghost
    @State private var dragX: CGFloat?

    var body: some View {
        let rect = CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale)
        ZStack(alignment: .topLeading) {
            if dragX != nil {
                // Miejsce, z którego element został podniesiony.
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(0.75))
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                ghost
                    .frame(width: rect.width, height: rect.height)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                    .scaleEffect(1.05)
                    .offset(x: rect.minX + (dragX ?? 0), y: rect.minY)
            }
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor.opacity(dragX == nil ? 0.6 : 0), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .contentShape(.rect)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { dragX = $0.translation.width }
                        .onEnded { value in
                            let pageMid = InvoiceLayoutSnapshot.pageSize.width * scale / 2
                            let center = rect.midX + value.translation.width
                            let target: InvoiceSide = center < pageMid ? .leading : .trailing
                            withAnimation(.snappy) { dragX = nil }
                            if target != side { onSide(target) }
                        }
                )
                .accessibilityElement()
                .accessibilityLabel(Text(label))
                .accessibilityValue(Text(side == .leading ? "Po lewej" : "Po prawej"))
                .accessibilityAction(named: Text("Przenieś w lewo")) { onSide(.leading) }
                .accessibilityAction(named: Text("Przenieś w prawo")) { onSide(.trailing) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension InvoiceSection {
    var label: LocalizedStringResource {
        switch self {
        case .parties: "Sprzedawca i nabywca"
        case .items: "Pozycje"
        case .summary: "Podsumowanie VAT"
        case .totals: "Do zapłaty"
        case .payment: "Płatność i kod QR"
        case .notes: "Uwagi i adnotacje"
        case .signatures: "Podpisy"
        }
    }

    /// Opis sekcji, która nie ma treści na fakturze podglądu.
    var emptyHint: LocalizedStringResource {
        switch self {
        case .signatures: "Podpisy — wyłączone"
        case .notes: "Uwagi i adnotacje — pojawią się, gdy faktura je ma"
        default: "\(label) — brak na tej fakturze"
        }
    }
}

private extension UIImage {
    /// Wycinek obrazu (prostokąt w punktach).
    func crop(_ rect: CGRect) -> UIImage? {
        let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        return cgImage?.cropping(to: pixels).map { UIImage(cgImage: $0, scale: scale, orientation: .up) }
    }
}
