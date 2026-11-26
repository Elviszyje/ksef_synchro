import SwiftUI
import Domain

/// Krótki opis pod kwotą na listach: etap płatności albo termin liczony od dziś.
struct DueSummary {
    enum Tone { case muted, warning, danger, accent }
    let text: LocalizedStringResource
    let tone: Tone

    var color: Color {
        switch tone {
        case .muted: .appMuted
        case .warning: .appWarning
        case .danger: .appDanger
        case .accent: .appAccent
        }
    }

    init(text: LocalizedStringResource, tone: Tone) {
        self.text = text
        self.tone = tone
    }

    init?(_ invoice: Invoice, today: LocalDate) {
        switch invoice.status {
        case .paid: self.init(text: "opłacona", tone: .muted)
        case .sentForPayment: self.init(text: "w paczce przelewów", tone: .accent)
        case .disputed: self.init(text: "sporna", tone: .danger)
        case .new, .accepted:
            if invoice.isCorrection {
                self.init(text: "korekta", tone: .muted)
            } else if let due = invoice.paymentDueDate {
                self.init(daysLeft: Self.days(from: today, to: due))
            } else {
                return nil
            }
        }
    }

    /// - Parameter daysLeft: dni do terminu; wartość ujemna oznacza termin przekroczony.
    init(daysLeft: Int) {
        switch daysLeft {
        case ..<0: self.init(text: "\(-daysLeft) dni po terminie", tone: .danger)
        case 0: self.init(text: "termin dziś", tone: .warning)
        case 1: self.init(text: "jutro", tone: .warning)
        case 2...3: self.init(text: "za \(daysLeft) dni", tone: .warning)
        default: self.init(text: "za \(daysLeft) dni", tone: .muted)
        }
    }

    static func days(from: LocalDate, to: LocalDate) -> Int {
        Calendar.current.dateComponents([.day], from: from.date(), to: to.date()).day ?? 0
    }
}

/// Wiersz faktury kosztowej: awatar dostawcy, numer, kwota i termin. Faktura w statusie „Nowa”
/// (jeszcze niesprawdzona) ma kropkę przy awatarze i pogrubioną nazwę.
struct InvoiceRow: View {
    let invoice: Invoice
    var today: LocalDate = .today()

    private var isNew: Bool { invoice.status == .new }

    var body: some View {
        HStack(spacing: 12) {
            InitialsAvatar(name: invoice.sellerName)
                .overlay(alignment: .topTrailing) {
                    if isNew {
                        Circle().fill(Color.appAccent)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(Color.appBackground, lineWidth: 2).padding(-2))
                            .offset(x: 2, y: -2)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(invoice.sellerName)
                    .font(.grotesk(15, isNew ? .bold : .medium, relativeTo: .headline))
                    .foregroundStyle(Color.appInk)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(invoice.invoiceNumber).font(.mono(12)).lineLimit(1)
                    if invoice.isSplitPayment { Text("· MPP").font(.mono(12)) }
                }
                .foregroundStyle(Color.appMuted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(invoice.amountGross.money(invoice.currency))
                    .font(.grotesk(15, isNew ? .bold : .medium, relativeTo: .subheadline))
                    .monospacedDigit()
                    .foregroundStyle(Color.appInk)
                    .lineLimit(1)
                if let due = DueSummary(invoice, today: today) {
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
        .accessibilityValue(Text(invoice.status.label))
    }
}

/// Rodzaj faktur pokazywany w zakładce Faktury.
enum InvoiceKind: Hashable {
    case cost, sales
}

/// Przełącznik „Kosztowe / Sprzedaż” jako pierwszy wiersz listy. Własne przyciski, a nie systemowa
/// kontrolka segmentowa — ta jest już używana przez pasek okresu tuż pod spodem.
struct InvoiceKindSection: View {
    @Binding var kind: InvoiceKind

    var body: some View {
        Section {
            HStack(spacing: 0) {
                segment("Kosztowe", .cost)
                segment("Sprzedaż", .sales)
            }
            .padding(4)
            .background(Color.appSurfaceRaised, in: .capsule)
            .padding(.horizontal)
            .padding(.vertical, 6)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .sensoryFeedback(.selection, trigger: kind)
        }
        .listSectionSeparator(.hidden)
    }

    private func segment(_ title: LocalizedStringKey, _ value: InvoiceKind) -> some View {
        Button { kind = value } label: {
            Text(title)
                .font(.grotesk(14, .medium, relativeTo: .subheadline))
                .foregroundStyle(kind == value ? Color.appInk : Color.appMuted)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(kind == value ? Color.appSurface : Color.clear, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(kind == value ? .isSelected : [])
        .accessibilityIdentifier(value == .cost ? "kind-cost" : "kind-sales")
    }
}

/// Zakładka Faktury: faktury kosztowe z KSeF albo sprzedażowe, przełączane u góry listy.
struct InvoicesTab: View {
    @Binding var kind: InvoiceKind

    var body: some View {
        switch kind {
        case .cost: InvoicesView(kind: $kind)
        case .sales: SalesListView(kind: $kind)
        }
    }
}

/// Komunikat nad listą (tryb demo, wynik synchronizacji) jako wiersz w formie karty.
struct BannerRow: View {
    let text: Text
    let systemImage: String

    var body: some View {
        Section {
            Label { text } icon: { Image(systemName: systemImage) }
                .font(.appFootnote)
                .foregroundStyle(Color.appMuted)
                .appCard(padding: 12, radius: 16)
                .padding(.horizontal)
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listSectionSeparator(.hidden)
    }
}
