import Domain
import UIKit

/// Strona faktury pocięta na fragmenty dla edytora układu: nagłówek, sekcje w kolejności szablonu
/// i stopka. Obrazy pochodzą z tego samego renderera co PDF, więc edytor pokazuje prawdziwy wygląd.
/// Współrzędne i rozmiary w punktach PDF (szerokość strony 595 pt).
nonisolated struct InvoiceLayoutSnapshot: Sendable {
    struct Piece: Identifiable, Sendable {
        let section: InvoiceSection
        /// nil — sekcja nie ma treści na tej fakturze (np. brak uwag, podpisy wyłączone).
        let image: UIImage?
        let height: CGFloat
        /// Odstęp nad sekcją, taki jak na stronie.
        let spacing: CGFloat
        /// Kolumna kodu QR w obrazie sekcji płatności.
        let qrFrame: CGRect?
        var id: InvoiceSection { section }
    }

    static let pageSize = InvoiceVisualizationPDF.page.size

    let header: UIImage
    /// Nagłówek z górnym marginesem strony (pas nowoczesnego układu zaczyna się na krawędzi).
    let headerHeight: CGFloat
    let logoFrame: CGRect?
    let logo: UIImage?
    let pieces: [Piece]
    let footer: UIImage
    let footerHeight: CGFloat
}

extension InvoiceVisualizationPDF {
    nonisolated func layoutSnapshot(scale: CGFloat = 2) -> InvoiceLayoutSnapshot {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        func image(height: CGFloat, _ draw: @escaping () -> Void) -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: Self.page.width, height: max(height, 1)), format: format)
                .image { _ in draw() }
        }

        let header = headerBlock()
        let headerHeight = Self.margin + header.height
        let headerImage = image(height: headerHeight) { header.draw(Self.margin) }

        let pieces = template.sectionOrder.map { section -> InvoiceLayoutSnapshot.Piece in
            let blocks = sectionBlocks(section)
            guard let first = blocks.first else {
                return .init(section: section, image: nil, height: 0, spacing: 14, qrFrame: nil)
            }
            var offsets: [CGFloat] = []
            var y: CGFloat = 0
            for (index, block) in blocks.enumerated() {
                if index > 0 { y += block.spacing }
                offsets.append(y)
                y += block.height
            }
            let height = y
            let picture = image(height: height) { for (block, top) in zip(blocks, offsets) { block.draw(top) } }
            let qr = section == .payment ? qrFrame(blockTop: 0, height: first.height) : nil
            return .init(section: section, image: picture, height: height, spacing: first.spacing, qrFrame: qr)
        }

        let footerHeight = self.footerHeight
        let footerSlice = footerHeight + Self.margin
        let footer = image(height: footerSlice) {
            UIGraphicsGetCurrentContext()?.translateBy(x: 0, y: footerSlice - Self.page.height)
            drawFooter(page: 1, of: 1, height: footerHeight)
        }
        return InvoiceLayoutSnapshot(header: headerImage, headerHeight: headerHeight, logoFrame: logoFrame(headerTop: Self.margin),
                                     logo: logo, pieces: pieces, footer: footer, footerHeight: footerSlice)
    }
}
